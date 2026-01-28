# Central Pipeline Infrastructure

This directory contains the Terraform configuration for the centralized CI/CD pipeline that drives the entire Regional Platform.

## Architecture

The pipeline uses **AWS CodePipeline** and **AWS CodeBuild** to orchestrate the deployment of the platform.

1.  **Source:** Listens for changes on the specified branch of the GitHub repository (via CodeStar Connection).
2.  **Build/Deploy:**
    *   Runs the `terraform/region-deploy/scripts/orchestrate_deploy.py` script.
    *   Mints/Updates AWS Accounts based on `region-deploy` configuration.
    *   Provisions/Updates Management and Regional clusters inside those accounts.

## Resources Created

*   **CodeStar Connection:** Connection to GitHub (requires manual activation in AWS Console after creation).
*   **S3 Buckets:**
    *   `central-pipeline-state-*`: Stores the central-pipeline's own Terraform state (with versioning and encryption).
    *   `pipeline-artifacts-*`: Stores CodePipeline artifacts (with versioning and encryption).
    *   `regional-cluster-tf-state-*`: Centralized state store for all child clusters and the account minting process (with versioning, encryption, and Organization-wide access policy).
*   **DynamoDB:** (Not currently used, state locking is implicit in serial pipeline execution).
*   **IAM Roles:**
    *   `central-pipeline-role`: For CodePipeline.
    *   `central-pipeline-codebuild-role`: For CodeBuild. Has permissions to:
        *   Manage S3 buckets.
        *   Create/Move/Tag AWS Accounts (`organizations:*`).
        *   Assume `OrganizationAccountAccessRole` in child accounts.
*   **CodePipeline:** The pipeline definition.
*   **CodeBuild Project:** The build environment definition.

**Security Features:**
- All S3 buckets have versioning enabled for rollback capability
- All S3 buckets use server-side encryption (AES256)
- All S3 buckets block public access at the bucket level

## Prerequisites

Before deploying this pipeline, you must have:

1.  **AWS Organization:** The account running this pipeline should be the Management Account or a Delegated Administrator for the Organization.

**Note:** The CodeStar connection to GitHub will be created automatically by Terraform, but it requires manual activation in the AWS Console after creation (see Post-Deployment Setup below).

## Deployment

To deploy this pipeline for the first time:

```bash
cd terraform/config/central-pipeline
terraform init
terraform apply \
  -var="repository_id=owner/repo-name" \
  -var="branch_name=main"
```

Replace `owner/repo-name` with your GitHub repository (e.g., `openshift-online/rosa-regional-platform`).

## Inputs

| Name | Description | Default |
| :--- | :--- | :--- |
| `region` | AWS Region for the pipeline resources. | `us-east-1` |
| `repository_id` | **Required.** GitHub repository ID (owner/repo format). | N/A |
| `branch_name` | Branch to trigger the pipeline. | `main` |

## Outputs

*   `pipeline_url`: The AWS Console URL for the created pipeline.
*   `central_pipeline_state_bucket`: The name of the S3 bucket for storing this module's own Terraform state.
*   `tf_state_bucket`: The name of the S3 bucket for storing child cluster Terraform state (Regional/Management).
*   `codestar_connection_arn`: The ARN of the CodeStar connection to GitHub.
*   `codestar_connection_status`: The status of the CodeStar connection (needs manual activation).

## Post-Deployment Setup

### Step 1: Activate CodeStar Connection

After running `terraform apply`, you must manually activate the CodeStar connection:

1. Navigate to the AWS Console: **Developer Tools** > **Settings** > **Connections**
2. Find the connection named `github-connection` with status `PENDING`
3. Click **Update pending connection**
4. Follow the OAuth flow to authorize the connection with GitHub
5. Once authorized, the connection status will change to `AVAILABLE`
6. The pipeline will now be able to trigger on repository changes

### Step 2: Migrate to Remote State (Optional but Recommended)

By default, this configuration uses local state. For production deployments, you should migrate to remote state in S3:

1. **Note the state bucket name** from the Terraform output:
   ```bash
   terraform output central_pipeline_state_bucket
   # Example output: central-pipeline-state-abc123xyz
   ```

2. **Edit `backend.tf`**:
   - Uncomment the entire `terraform` block
   - Update the `bucket` value with the actual bucket name from step 1
   - Update the `region` if different from `us-east-1`

3. **Migrate the state**:
   ```bash
   terraform init -migrate-state
   ```

4. **Confirm migration** when prompted. Terraform will:
   - Copy your local state to S3
   - Configure the backend to use S3 going forward

5. **Verify** the state file exists in S3:
   ```bash
   aws s3 ls s3://central-pipeline-state-abc123xyz/central-pipeline/
   ```

6. **Delete local state** (optional, after verifying remote state works):
   ```bash
   rm terraform.tfstate terraform.tfstate.backup
   ```

**Why Remote State?**
- **Team Collaboration**: Multiple team members can work with the same state
- **State Locking**: Prevents concurrent modifications (with DynamoDB table)
- **Versioning**: S3 versioning enabled for state rollback
- **Encryption**: State is encrypted at rest in S3
- **Disaster Recovery**: State survives local machine failures
