import boto3
import sys
import os
import argparse
import json
import subprocess
from botocore.exceptions import ClientError

TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'AccountPool')
REGION = os.environ.get('AWS_REGION', 'us-east-2')

def run_cloud_nuke(credentials):
    env = os.environ.copy()
    env['AWS_ACCESS_KEY_ID'] = credentials['AccessKeyId']
    env['AWS_SECRET_ACCESS_KEY'] = credentials['SecretAccessKey']
    if credentials.get('SessionToken'):
        env['AWS_SESSION_TOKEN'] = credentials['SessionToken']

    # Calculate absolute path to config file
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = os.path.join(script_dir, '..', 'configs', 'cloud-nuke.yaml')

    cmd = [
        "cloud-nuke", "aws",
        "--region", REGION,
        "--config", config_path,
        "--force",
        "--timeout", "30m"
    ]

    try:
        # Stream output to stderr to allow viewing progress while keeping stdout clean for JSON
        subprocess.run(
            cmd,
            env=env,
            check=True,
            capture_output=False,
            text=True,
            stdout=sys.stderr, # Redirect stdout to stderr
            stderr=sys.stderr  # Redirect stderr to stderr
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"cloud-nuke failed with exit code {e.returncode}", file=sys.stderr)
        return False
    except FileNotFoundError:
        print(f"cloud-nuke binary not found.", file=sys.stderr)
        return False

def run_terraform_destroy(credentials, terraform_path):
    env = os.environ.copy()
    env['AWS_ACCESS_KEY_ID'] = credentials['AccessKeyId']
    env['AWS_SECRET_ACCESS_KEY'] = credentials['SecretAccessKey']
    if credentials.get('SessionToken'):
        env['AWS_SESSION_TOKEN'] = credentials['SessionToken']

    try:
        # Run init first to ensure providers are available
        init_cmd = ["terraform", "init"]
        subprocess.run(
            init_cmd,
            cwd=terraform_path,
            env=env,
            check=True,
            capture_output=False,
            text=True
        )

        cmd = [
            "terraform", "destroy",
            "-auto-approve"
        ]

        # Stream output to stdout/stderr
        subprocess.run(
            cmd,
            cwd=terraform_path,
            env=env,
            check=True,
            capture_output=False,
            text=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"terraform command failed with exit code {e.returncode}", file=sys.stderr)
        return False
    except FileNotFoundError:
        print(f"terraform binary not found.", file=sys.stderr)
        return False

def release_account(account_id, status='AVAILABLE', terraform_path=None):
    print(f"Starting release_account.py for account {account_id} with status {status} in region {REGION}", file=sys.stderr)
    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table(TABLE_NAME)
    IAM_USER_NAME = 'sandbox-temporary-user'

    try:
        # Check current status first
        print(f"Checking current status of account {account_id}...", file=sys.stderr)
        response = table.get_item(Key={'account_id': account_id})
        item = response.get('Item')

        if not item:
            error_msg = {
                "status": "error",
                "message": f"Account {account_id} not found",
                "account_id": account_id
            }
            print(json.dumps(error_msg), file=sys.stderr)
            sys.exit(1)

        current_status = item.get('status')
        # Allow releasing if status is IN_USE or FAILED (re-releasing a failed account to AVAILABLE or resetting it)
        if current_status not in ['IN_USE', 'FAILED']:
            error_msg = {
                "status": "error",
                "message": f"Account {account_id} is not leased (current status: {current_status})",
                "account_id": account_id,
                "current_status": current_status
            }
            print(json.dumps(error_msg), file=sys.stderr)
            sys.exit(1)

        # If we are setting status to FAILED, we skip cleanup to allow debugging
        if status == 'FAILED':
            print(f"Marking account {account_id} as FAILED. Skipping cleanup.", file=sys.stderr)
            table.update_item(
                Key={'account_id': account_id},
                UpdateExpression="SET #s = :failed",
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={':failed': 'FAILED'}
            )
            print(f"Successfully marked account {account_id} as FAILED")
            return

        # Attempt to clean up the temporary user
        try:
            print(f"Assuming OrganizationAccountAccessRole for account {account_id}...", file=sys.stderr)
            sts = boto3.client('sts', region_name=REGION)
            role_arn = f"arn:aws:iam::{account_id}:role/OrganizationAccountAccessRole"

            assumed_role_object = sts.assume_role(
                RoleArn=role_arn,
                RoleSessionName="ReleaseSession",
                DurationSeconds=3600
            )
            credentials = assumed_role_object['Credentials']

            # Run terraform destroy if path is provided
            if terraform_path:
                print(f"Running terraform destroy on account {account_id} in {terraform_path}...", file=sys.stderr)
                if not run_terraform_destroy(credentials, terraform_path):
                    print(f"Error: terraform destroy failed for account {account_id}. Marking as DIRTY.", file=sys.stderr)
                    # Mark as DIRTY
                    table.update_item(
                        Key={'account_id': account_id},
                        UpdateExpression="SET #s = :dirty REMOVE lease_timestamp",
                        ExpressionAttributeNames={'#s': 'status'},
                        ExpressionAttributeValues={':dirty': 'DIRTY'}
                    )
                    error_msg = {
                        "status": "error",
                        "message": f"terraform destroy failed for account {account_id}",
                        "account_id": account_id
                    }
                    print(json.dumps(error_msg), file=sys.stderr)
                    sys.exit(1)

            # Run cloud-nuke
            print(f"Running cloud-nuke on account {account_id} (using assumed role credentials)...", file=sys.stderr)
            if not run_cloud_nuke(credentials):
                print(f"Error: cloud-nuke failed for account {account_id}. Marking as DIRTY.", file=sys.stderr)
                # Mark as DIRTY
                table.update_item(
                    Key={'account_id': account_id},
                    UpdateExpression="SET #s = :dirty REMOVE lease_timestamp",
                    ExpressionAttributeNames={'#s': 'status'},
                    ExpressionAttributeValues={':dirty': 'DIRTY'}
                )
                error_msg = {
                    "status": "error",
                    "message": f"cloud-nuke failed for account {account_id}",
                    "account_id": account_id
                }
                print(json.dumps(error_msg), file=sys.stderr)
                sys.exit(1)

            iam_resource = boto3.resource(
                'iam',
                aws_access_key_id=credentials['AccessKeyId'],
                aws_secret_access_key=credentials['SecretAccessKey'],
                aws_session_token=credentials['SessionToken'],
                region_name=REGION
            )

            user = iam_resource.User(IAM_USER_NAME)

            # Check if exists
            try:
                user.load()
                # Delete login profile if exists
                try:
                    user.LoginProfile().delete()
                except ClientError:
                    pass

                # Delete access keys
                for key in user.access_keys.all():
                    key.delete()

                # Detach policies
                for policy in user.attached_policies.all():
                    user.detach_policy(PolicyArn=policy.arn)

                # Delete inline policies
                for policy in user.policies.all():
                    policy.delete()

                # Delete user
                user.delete()
                print(f"Successfully deleted user {IAM_USER_NAME} in account {account_id}")
            except ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchEntity':
                    print(f"User {IAM_USER_NAME} not found in account {account_id}, nothing to delete.")
                else:
                    raise e

        except Exception as e:
            # We log the error but proceed to release the account in DynamoDB
            print(f"Warning: Failed to cleanup user {IAM_USER_NAME} in account {account_id}: {e}", file=sys.stderr)
            print("Marking account as DIRTY due to cleanup failure.", file=sys.stderr)

            table.update_item(
                Key={'account_id': account_id},
                UpdateExpression="SET #s = :dirty REMOVE lease_timestamp",
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={':dirty': 'DIRTY'}
            )
            sys.exit(1)


        # Proceed to release
        table.update_item(
            Key={'account_id': account_id},
            UpdateExpression="SET #s = :status REMOVE lease_timestamp",
            ConditionExpression="attribute_exists(account_id)",
            ExpressionAttributeNames={'#s': 'status'},
            ExpressionAttributeValues={':status': status}
        )
        print(f"Successfully released account {account_id} with status {status}")

    except ClientError as e:
        error_msg = {
            "status": "error",
            "message": f"Error releasing account {account_id}: {e}",
            "account_id": account_id
        }
        print(json.dumps(error_msg), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        error_msg = {
            "status": "error",
            "message": f"Unexpected error releasing account {account_id}: {e}",
            "account_id": account_id
        }
        print(json.dumps(error_msg), file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Release a leased AWS account.')
    parser.add_argument('account_id', type=str, help='The ID of the account to release')
    parser.add_argument('--status', type=str, default='AVAILABLE', choices=['AVAILABLE', 'FAILED'], help='The target status for the account (AVAILABLE or FAILED)')
    parser.add_argument('--terraform-path', type=str, help='Path to terraform configuration to destroy')
    args = parser.parse_args()

    release_account(args.account_id, args.status, args.terraform_path)