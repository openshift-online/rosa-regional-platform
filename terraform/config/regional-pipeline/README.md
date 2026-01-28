# Regional Pipeline Infrastructure

This directory contains the Terraform configuration for the **Regional Pipeline** - deployed in each Regional AWS Account to manage Management Clusters.

## Scope

**The Regional Pipeline is responsible for:**
- ✅ Monitoring Management Cluster capacity needs
- ✅ Deploying Management Clusters (EKS with HyperShift) in the same region
- ✅ Scaling Management Cluster capacity independently
- ✅ Managing lifecycle of Management Clusters

**The Regional Pipeline is NOT responsible for:**
- ❌ Deploying Regional Clusters (handled by Central Pipeline)
- ❌ Cross-region operations
- ❌ Creating Regional AWS accounts

**See [Pipeline Architecture](../../../docs/pipeline-architecture.md) for the complete two-tier pipeline design.**

## Architecture

The Regional Pipeline uses **AWS CodePipeline** and **AWS CodeBuild** running in a **Regional AWS Account**.

1.  **Source:** Listens for changes on the specified branch of the GitHub repository (via CodeStar Connection).
2.  **Build/Deploy:**
    *   Runs the `terraform/config/regional-pipeline/scripts/orchestrate_regional_deploy.py` script.
    *   Reads Management Cluster definitions for this region only.
    *   Assumes restricted roles in Management AWS Accounts.
    *   Calls `make pipeline-provision-management` in each Management Account.

## Resources Created

*   **CodeStar Connection:** Connection to GitHub (requires manual activation after creation).
*   **S3 Buckets:**
    *   `regional-pipeline-artifacts-*`: Stores CodePipeline artifacts for this region.
    *   `management-cluster-tf-state-*`: State store for Management Clusters in this region.
*   **IAM Roles:**
    *   `regional-pipeline-codebuild-role`: For CodeBuild. Has permissions to:
        *   Access regional S3 buckets
        *   Read central state bucket (management-deploy state)
        *   Assume roles in Management Accounts (same region only)
    *   `regional-pipeline-role`: For CodePipeline orchestration.
    *   `ManagementClusterDeployRole`: Template for role created in Management Accounts.
*   **CodePipeline:** The pipeline definition for Management Clusters.
*   **CodeBuild Project:** The build environment for Management deployments.

**Security Features:**
- ✅ Region-scoped permissions (cannot affect other regions)
- ✅ More restrictive than Central Pipeline (no org-wide access)
- ✅ Cross-account access uses dedicated role (not OrganizationAccountAccessRole)
- ✅ External ID required for cross-account assumption
- ✅ All S3 buckets encrypted and private

## Deployment

**The Regional Pipeline is deployed AUTOMATICALLY by the Central Pipeline** when provisioning a new Regional Cluster.

### Manual Deployment (For Testing)

If you need to deploy manually (e.g., for testing):

```bash
cd terraform/config/regional-pipeline

# Initialize with Central state bucket
terraform init -reconfigure \
  -backend-config="bucket=<central-state-bucket>" \
  -backend-config="key=rosa-regional-<region>-pipeline/terraform.tfstate" \
  -backend-config="region=<central-region>"

# Deploy with required variables
terraform apply \
  -var="region=us-east-1" \
  -var="repository_id=owner/repo-name" \
  -var="branch_name=main" \
  -var="central_state_bucket=<central-state-bucket>"
```

### Post-Deployment Steps

1. **Activate CodeStar Connection** in AWS Console (same as Central Pipeline)
2. **Create Management Cluster definitions** in Git repository
3. **Pipeline automatically triggers** on Git push

## Security Model

### Trust Relationships

The Regional Pipeline uses a **three-tier trust model**:

```
Central Account
    ↓ (trusts via Organizations)
Regional Account (Regional Pipeline runs here)
    ↓ (trusts via ManagementClusterDeployRole with ExternalID)
Management Account (Management Cluster infrastructure)
```

### Key Security Controls

1. **Region Isolation**
   - Regional Pipeline can only deploy in its own region
   - Cannot affect resources in other regions
   - Condition: `aws:RequestedRegion = <this-region>`

2. **Restricted AssumeRole**
   - Does NOT use OrganizationAccountAccessRole
   - Uses dedicated ManagementClusterDeployRole
   - Requires ExternalID: `regional-pipeline-<region>`
   - Scoped to specific resource types (EKS, EC2, etc.)

3. **Read-Only Central Access**
   - Can read management-deploy state from Central bucket
   - Cannot write to Central bucket
   - Cannot access other state files

4. **Limited IAM Permissions**
   - Cannot create arbitrary IAM roles
   - Only EKS and service-linked roles
   - Cannot modify policies or create users

5. **S3 Bucket Policies**
   - Management state bucket only accessible from Regional Account
   - Not org-wide like Central state bucket
   - Principle of least privilege

### Comparison to Central Pipeline

| Feature | Central Pipeline | Regional Pipeline |
|---------|-----------------|-------------------|
| **Scope** | Organization-wide | Single region |
| **Account Creation** | Yes (Organizations API) | No |
| **Cross-Account** | All accounts in org | Management accounts only |
| **AssumeRole** | OrganizationAccountAccessRole | ManagementClusterDeployRole |
| **State Bucket Access** | Org-wide | Region-scoped |
| **Blast Radius** | High (entire org) | Low (single region) |
| **Trust Model** | Service principal only | Service principal + ExternalID |

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `region` | AWS Region for this Regional Pipeline | Yes | N/A |
| `repository_id` | GitHub repository ID (owner/repo) | Yes | N/A |
| `branch_name` | Branch to trigger pipeline | No | `main` |
| `central_state_bucket` | Central state bucket name | Yes | N/A |

## Outputs

*   `pipeline_url`: AWS Console URL for the Regional Pipeline
*   `management_state_bucket`: S3 bucket for Management Cluster state
*   `codestar_connection_arn`: CodeStar connection ARN
*   `codestar_connection_status`: Connection status
*   `codebuild_role_arn`: CodeBuild role ARN (for Management account trust)
*   `management_deploy_role_name`: Role name to create in Management accounts

## Management Cluster Deployment

When the Regional Pipeline runs:

1. **Reads management-deploy state** from Central bucket
2. **Filters for Management Clusters** in this region
3. **For each Management Account:**
   - Assumes ManagementClusterDeployRole (with ExternalID)
   - Initializes Terraform backend (regional state bucket)
   - Runs `make pipeline-provision-management`
   - Deploys EKS cluster with HyperShift

## ManagementClusterDeployRole

This role is created in each Management Account with these permissions:

**Allowed:**
- ✅ EKS full access (create/manage clusters)
- ✅ EC2 full access (VPC, subnets, security groups)
- ✅ IAM limited (only eks-* and service-linked roles)
- ✅ CloudWatch Logs
- ✅ Auto Scaling
- ✅ ECS (for bootstrap tasks)

**Denied (by omission):**
- ❌ Organizations API
- ❌ Create arbitrary IAM roles
- ❌ S3 bucket policy changes
- ❌ Account-level changes

## Monitoring

### CloudWatch Logs

Pipeline logs are written to:
```
/aws/codebuild/management-cluster-deploy
```

### Metrics to Monitor

- Pipeline execution frequency
- Management Cluster creation rate
- Failed deployments
- AssumeRole failures (security concern)

## Disaster Recovery

### Regional Pipeline Failure

**Impact:** Cannot scale Management capacity in this region

**Recovery:**
1. Existing Management Clusters continue operating
2. Other regions unaffected
3. Redeploy Regional Pipeline from Central Pipeline
4. Or manual deployment using steps above

### State Corruption

**Recovery:**
1. S3 versioning enabled - restore previous version
2. Regional Pipeline state stored in Central bucket (backed up)
3. Management Cluster states in regional bucket (versioned)

## Related Documentation

- [Pipeline Architecture](../../../docs/pipeline-architecture.md)
- [Security Trust Policies](../../../docs/security-trust-policies.md)
- [Central Pipeline Configuration](../central-pipeline/README.md)
- [State Bucket Architecture](../../../docs/state-bucket-architecture.md)
