import os
import json
import subprocess
import sys
import boto3

def run_command(command, cwd=None, env=None):
    """Execute a shell command with proper error handling"""
    print(f"Running: {command} in {cwd or '.'}")
    result = subprocess.run(
        command, shell=True, cwd=cwd, env=env, check=True, text=True
    )
    return result

def main():
    # Ensure required environment variables are set
    management_state_bucket = os.environ.get("MANAGEMENT_STATE_BUCKET")
    central_state_bucket = os.environ.get("CENTRAL_STATE_BUCKET")
    region = os.environ.get("AWS_REGION", "us-east-1")

    if not management_state_bucket:
        print("Error: MANAGEMENT_STATE_BUCKET environment variable not set.")
        sys.exit(1)

    if not central_state_bucket:
        print("Error: CENTRAL_STATE_BUCKET environment variable not set.")
        sys.exit(1)

    print(f"\n{'='*70}")
    print(f"Regional Pipeline - Management Cluster Deployment")
    print(f"Region: {region}")
    print(f"Management State Bucket: {management_state_bucket}")
    print(f"Central State Bucket: {central_state_bucket}")
    print(f"{'='*70}\n")

    # 1. Apply Management Deploy Terraform to mint Management accounts
    deploy_dir = "terraform/config/management-deploy"
    print(f"Initializing and Applying Management Account Minting in {deploy_dir}...")

    # Initialize Backend for Management Account Minting
    # State stored in Central bucket for consistency
    key = "management-deploy/terraform.tfstate"
    init_cmd = (
        f"terraform init -reconfigure "
        f"-backend-config=\"bucket={central_state_bucket}\" "
        f"-backend-config=\"key={key}\" "
        f"-backend-config=\"region={region}\""
    )

    run_command(init_cmd, cwd=deploy_dir)

    # Apply with region filter to only create Management clusters for this region
    apply_cmd = f"terraform apply -auto-approve -var=\"region={region}\""
    run_command(apply_cmd, cwd=deploy_dir)

    # 2. Get Terraform Outputs
    print("\nReading Terraform outputs for Management cluster definitions...")
    output_proc = subprocess.run(
        "terraform output -json accounts",
        shell=True, cwd=deploy_dir, check=True, capture_output=True, text=True
    )

    try:
        accounts = json.loads(output_proc.stdout)
    except json.JSONDecodeError:
        print("Error decoding JSON output or no accounts found.")
        print(output_proc.stdout)
        accounts = {}

    if not accounts:
        print("No Management cluster accounts defined for this region. Exiting.")
        return

    # 3. Iterate through Management Accounts and Deploy Clusters
    sts = boto3.client("sts")
    external_id = f"regional-pipeline-{region}"

    for account_name, config in accounts.items():
        # Filter: Only process Management clusters in this region
        if config.get("region") != region:
            print(f"\nSkipping {account_name} - not in this region ({config.get('region')} != {region})")
            continue

        if config.get("type") != "management":
            print(f"\nSkipping {account_name} - not a Management cluster (type: {config.get('type')})")
            continue

        print(f"\n{'='*70}")
        print(f"Processing Management Cluster: {account_name}")
        print(f"  Account ID: {config['id']}")
        print(f"  Region: {config['region']}")
        print(f"  Type: {config['type']}")
        print(f"  Capacity: {config.get('capacity', 'N/A')}")
        print(f"{'='*70}\n")

        # Assume ManagementClusterDeployRole (more restrictive than OrganizationAccountAccessRole)
        role_arn = f"arn:aws:iam::{config['id']}:role/ManagementClusterDeployRole"
        print(f"Assuming role: {role_arn}")
        print(f"External ID: {external_id}")

        try:
            assumed_role = sts.assume_role(
                RoleArn=role_arn,
                RoleSessionName="RegionalPipelineDeploySession",
                ExternalId=external_id
            )
        except Exception as e:
            print(f"Failed to assume role {role_arn}: {e}")
            print("\nIMPORTANT: Ensure ManagementClusterDeployRole exists in the Management account")
            print(f"           with trust policy allowing this Regional account and ExternalId={external_id}")
            sys.exit(1)

        credentials = assumed_role["Credentials"]

        # Prepare Environment for Management Cluster Deployment
        env = os.environ.copy()

        # Inject temporary credentials
        env["AWS_ACCESS_KEY_ID"] = credentials["AccessKeyId"]
        env["AWS_SECRET_ACCESS_KEY"] = credentials["SecretAccessKey"]
        env["AWS_SESSION_TOKEN"] = credentials["SessionToken"]

        # Set target region
        env["AWS_DEFAULT_REGION"] = config["region"]
        env["AWS_REGION"] = config["region"]

        # Target directory for Management Cluster Terraform
        target_dir = "terraform/config/management-cluster"
        make_target = "pipeline-provision-management"

        # Initialize Terraform Backend in Regional state bucket
        # Each Management cluster gets its own state file
        key = f"{account_name}/terraform.tfstate"
        print(f"\nInitializing Terraform Backend: s3://{management_state_bucket}/{key}")

        init_cmd = (
            f"terraform init -reconfigure "
            f"-backend-config=\"bucket={management_state_bucket}\" "
            f"-backend-config=\"key={key}\" "
            f"-backend-config=\"region={region}\""
        )

        run_command(init_cmd, cwd=target_dir, env=env)

        # Run Provisioning via Make target
        # This assumes Makefile exists at repository root
        print(f"\nRunning Make Target: {make_target}")
        run_command(f"make {make_target}", cwd=".", env=env)

        print(f"\n✅ Management Cluster {account_name} deployed successfully!")

    print(f"\n{'='*70}")
    print("Regional Pipeline deployment completed successfully!")
    print(f"{'='*70}\n")

if __name__ == "__main__":
    main()
