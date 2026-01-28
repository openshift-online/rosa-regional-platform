import os
import json
import subprocess
import sys
import boto3

def run_command(command, cwd=None, env=None):
    print(f"Running: {command} in {cwd or '.'}")
    result = subprocess.run(
        command, shell=True, cwd=cwd, env=env, check=True, text=True
    )
    return result

def main():
    # Ensure variables are set
    state_bucket = os.environ.get("TF_STATE_BUCKET")
    backend_region = os.environ.get("TF_BACKEND_REGION", "us-east-1")
    
    if not state_bucket:
        print("Error: TF_STATE_BUCKET environment variable not set.")
        sys.exit(1)

    # 1. Apply Region Deploy Terraform
    deploy_dir = "terraform/region-deploy"
    print(f"Initializing and Applying Account Minting in {deploy_dir}...")
    
    # Initialize Backend for Account Minting (Central State)
    key = "region-deploy/terraform.tfstate"
    init_cmd = (
        f"terraform init -reconfigure "
        f"-backend-config=\"bucket={state_bucket}\" "
        f"-backend-config=\"key={key}\" "
        f"-backend-config=\"region={backend_region}\"" 
    )
    
    # We use the current environment (Central) for this
    run_command(init_cmd, cwd=deploy_dir)
    run_command("terraform apply -auto-approve", cwd=deploy_dir)

    # 2. Get Outputs
    print("Reading Terraform outputs...")
    output_proc = subprocess.run(
        "terraform output -json accounts",
        shell=True, cwd=deploy_dir, check=True, capture_output=True, text=True
    )
    try:
        accounts = json.loads(output_proc.stdout)
    except json.JSONDecodeError:
        # Handle case where outputs might be empty or wrapped
        print("Error decoding JSON output or no accounts found.")
        print(output_proc.stdout)
        accounts = {}

    if not accounts:
        print("No accounts defined. Exiting.")
        return

    # 3. Iterate and Provision
    sts = boto3.client("sts")
    
    for account_name, config in accounts.items():
        print(f"\n========================================================")
        print(f"Processing Account: {account_name} ({config['id']})")
        print(f"Region: {config['region']}")
        print(f"Type: {config['type']}")
        print(f"========================================================\n")
        
        # Assume Role
        role_arn = f"arn:aws:iam::{config['id']}:role/OrganizationAccountAccessRole"
        print(f"Assuming role: {role_arn}")
        
        try:
            assumed_role = sts.assume_role(
                RoleArn=role_arn,
                RoleSessionName="PipelineDeploySession"
            )
        except Exception as e:
            print(f"Failed to assume role {role_arn}: {e}")
            sys.exit(1)

        credentials = assumed_role["Credentials"]
        
        # Prepare Environment for Child Process
        # We start with a clean copy of the current env
        env = os.environ.copy()
        
        # Inject temporary credentials
        env["AWS_ACCESS_KEY_ID"] = credentials["AccessKeyId"]
        env["AWS_SECRET_ACCESS_KEY"] = credentials["SecretAccessKey"]
        env["AWS_SESSION_TOKEN"] = credentials["SessionToken"]
        
        # Set target region
        env["AWS_DEFAULT_REGION"] = config["region"]
        env["AWS_REGION"] = config["region"]

        # Determine Target Directory and Make Target
        cluster_type = config["type"]
        if cluster_type == "management":
            target_dir = "terraform/config/management-cluster"
            make_target = "pipeline-provision-management"
        elif cluster_type == "regional":
            target_dir = "terraform/config/regional-cluster"
            make_target = "pipeline-provision-regional"
        else:
            print(f"Unknown cluster type: {cluster_type}, skipping.")
            continue

        # Initialize Backend (Partial Config)
        # We need the Child Account to access the Central Bucket.
        # Ensure the Bucket Policy allows this.
        
        key = f"{account_name}/terraform.tfstate"
        print(f"Initializing Terraform Backend: s3://{state_bucket}/{key}")
        
        # 'terraform init' needs to happen in the target_dir
        # We use -reconfigure to ensure we switch backends correctly between iterations
        init_cmd = (
            f"terraform init -reconfigure "
            f"-backend-config=\"bucket={state_bucket}\" "
            f"-backend-config=\"key={key}\" "
            f"-backend-config=\"region={backend_region}\"" 
        )
        
        run_command(init_cmd, cwd=target_dir, env=env)

        # Run Provisioning
        # We run 'make' from the root directory so it finds the Makefile
        print(f"Running Make Target: {make_target}")
        run_command(f"make {make_target}", cwd=".", env=env)

if __name__ == "__main__":
    main()
