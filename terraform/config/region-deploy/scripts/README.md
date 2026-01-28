# Orchestration Script (`orchestrate_deploy.py`)

This script is the core engine of the Central Deployment Pipeline. It bridges the gap between the "Central" environment (where the pipeline runs) and the "Child" environments (the individual AWS accounts for Regional and Management clusters).

## Purpose

The script performs two main functions:
1.  **Minting Accounts:** It runs Terraform in the `terraform/region-deploy` directory to create or update AWS Accounts based on the YAML definitions in `terraform/region-deploy/regions/`.
2.  **Provisioning Clusters:** It iterates through the created accounts, assumes the administrative role into each one, and triggers the deployment of the specific cluster infrastructure (Management or Regional).

## Workflow

1.  **Account Deployment (Central Context):**
    *   Initializes Terraform for `terraform/region-deploy` using the Central State Bucket.
    *   Runs `terraform apply` to ensure all `aws_organizations_account` resources exist.
    *   Reads the `accounts` output to get a list of Account IDs, Regions, and Types.

2.  **Cluster Provisioning (Child Context):**
    *   Iterates through each account found in the output.
    *   **Assumes Role:** Uses `sts:AssumeRole` to obtain temporary credentials for the `OrganizationAccountAccessRole` in the target child account.
    *   **Backend Injection:** Dynamically initializes the Terraform backend for the cluster configuration (`terraform/config/regional-cluster` or `terraform/config/management-cluster`).
        *   It points the backend to the **Central State Bucket**.
        *   It sets the state key to `<account-name>/terraform.tfstate`.
        *   This ensures that even though the cluster lives in a child account, its state is stored centrally and securely.
    *   **Execution:** Runs the appropriate Makefile target (`pipeline-provision-regional` or `pipeline-provision-management`) using the injected credentials.

## Prerequisites

### Environment Variables

The script relies on the following environment variables, which are typically set by the AWS CodeBuild project:

| Variable | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `TF_STATE_BUCKET` | The name of the S3 bucket used for storing Terraform state (both for the region-deploy and the child clusters). | **Yes** | N/A |
| `TF_BACKEND_REGION`| The AWS region where the state bucket resides. | No | `us-east-1` |

### Dependencies

*   **Python 3.x**
*   **Boto3:** `pip install boto3`
*   **Terraform:** Must be installed and available in the system `PATH`.
*   **AWS Credentials:** The environment running the script must have an IAM Role capable of:
    *   `organizations:CreateAccount` (and related read/write permissions).
    *   `s3:*` on the state bucket.
    *   `sts:AssumeRole` on `arn:aws:iam::*:role/OrganizationAccountAccessRole`.

## Usage

### In CodeBuild (Standard)

The script is designed to be run directly by the `buildspec.yml`:

```yaml
phases:
  build:
    commands:
      - python3 terraform/region-deploy/scripts/orchestrate_deploy.py
```

### Local Execution (for Debugging)

To run the script locally, you must export the required variables and have valid AWS credentials for the Central account.

```bash
# 1. Export the State Bucket Name (found in the Central Pipeline Terraform outputs)
export TF_STATE_BUCKET="regional-cluster-tf-state-xxxxxxxx"

# 2. Run the script from the repository root
python3 terraform/region-deploy/scripts/orchestrate_deploy.py
```

**Note:** When running locally, ensure your AWS CLI profile has the necessary permissions to assume roles into the child accounts.
