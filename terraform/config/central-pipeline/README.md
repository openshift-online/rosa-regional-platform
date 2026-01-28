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
    *   `pipeline-artifacts-*`: Stores CodePipeline artifacts.
    *   `regional-cluster-tf-state-*`: Centralized state store for all child clusters and the account minting process. **Includes a Bucket Policy allowing Organization-wide access.**
*   **DynamoDB:** (Not currently used, state locking is implicit in serial pipeline execution).
*   **IAM Roles:**
    *   `central-pipeline-role`: For CodePipeline.
    *   `central-pipeline-codebuild-role`: For CodeBuild. Has permissions to:
        *   Manage S3 buckets.
        *   Create/Move/Tag AWS Accounts (`organizations:*`).
        *   Assume `OrganizationAccountAccessRole` in child accounts.
*   **CodePipeline:** The pipeline definition.
*   **CodeBuild Project:** The build environment definition.

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
*   `tf_state_bucket`: The name of the S3 bucket created for storing Terraform state.
*   `codestar_connection_arn`: The ARN of the CodeStar connection to GitHub.
*   `codestar_connection_status`: The status of the CodeStar connection (needs manual activation).

## Post-Deployment Setup

After running `terraform apply`, you must manually activate the CodeStar connection:

1. Navigate to the AWS Console: **Developer Tools** > **Settings** > **Connections**
2. Find the connection named `github-connection` with status `PENDING`
3. Click **Update pending connection**
4. Follow the OAuth flow to authorize the connection with GitHub
5. Once authorized, the connection status will change to `AVAILABLE`
6. The pipeline will now be able to trigger on repository changes
