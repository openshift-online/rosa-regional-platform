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

1.  **AWS CodeStar Connection:** A connection to GitHub must be created manually in the AWS Console (Developer Tools > Settings > Connections). The ARN of this connection is required.
2.  **AWS Organization:** The account running this pipeline should be the Management Account or a Delegated Administrator for the Organization.

## Deployment

To deploy this pipeline for the first time:

```bash
cd terraform/central-pipeline
terraform init
terraform apply \
  -var="codestar_connection_arn=arn:aws:codestar-connections:us-east-1:123456789012:connection/..." \
  -var="repository_id=openshift-online/rosa-regional-platform" \
  -var="branch_name=main"
```

## Inputs

| Name | Description | Default |
| :--- | :--- | :--- |
| `region` | AWS Region for the pipeline resources. | `us-east-1` |
| `codestar_connection_arn` | **Required.** ARN of the CodeStar connection to GitHub. | N/A |
| `repository_id` | GitHub repository ID (owner/repo). | `openshift-online/rosa-regional-platform` |
| `branch_name` | Branch to trigger the pipeline. | `main` |

## Outputs

*   `pipeline_url`: The AWS Console URL for the created pipeline.
*   `tf_state_bucket`: The name of the S3 bucket created for storing Terraform state.
