# AWS Account Minting Process

The AWS account minting process in this project is an automated, declarative approach to creating and managing isolated AWS accounts for Regional and Management clusters. Here's how it works:

## Overview

The process uses AWS Organizations to create dedicated AWS accounts for each cluster, ensuring complete isolation and clean security boundaries. It's driven by a GitOps workflow where YAML configuration files trigger automated account creation and cluster provisioning.

---

## The Three-Stage Process

### Stage 1: Account Definition (Declarative Configuration)

New AWS accounts are defined by creating simple YAML files in `terraform/config/region-deploy/regions/`:

**Example:** `us-east-2.yaml`
```yaml
name: "rosa-regional-us-east-2"
email: "something@example.com"  # Must be globally unique
region: "us-east-2"
type: "regional"  # Options: regional, management
```

The `main.tf` reads all YAML files using:
- `fileset()` to discover all `*.yaml` files
- `yamldecode()` to parse configurations
- `for_each` loop over all regions

### Stage 2: Account Minting (AWS Organizations API)

When the Central Pipeline triggers, the `orchestrate_deploy.py` script:

1. **Initializes Terraform** for the `region-deploy` module with the central state bucket
2. **Runs `terraform apply`** which:
   - Calls `aws_organizations_account` resource for each YAML config
   - Creates new AWS accounts via AWS Organizations API
   - Automatically creates `OrganizationAccountAccessRole` in each new account
   - Sets `close_on_deletion = false` to prevent accidental account deletion

3. **Reads Terraform outputs** containing:
   - Account ID
   - Account ARN
   - Account name
   - Target region
   - Cluster type (regional/management)

### Stage 3: Cluster Provisioning (Cross-Account Deployment)

For each minted account, the orchestration script (`orchestrate_deploy.py:58-129`):

1. **Assumes Role** into the child account:
   ```python
   role_arn = f"arn:aws:iam::{config['id']}:role/OrganizationAccountAccessRole"
   assumed_role = sts.assume_role(RoleArn=role_arn, RoleSessionName="PipelineDeploySession")
   ```
   - Uses STS API to get temporary credentials (Access Key, Secret Key, Session Token)
   - These credentials are short-lived and secure

2. **Injects Credentials** into environment variables:
   ```python
   env["AWS_ACCESS_KEY_ID"] = credentials["AccessKeyId"]
   env["AWS_SECRET_ACCESS_KEY"] = credentials["SecretAccessKey"]
   env["AWS_SESSION_TOKEN"] = credentials["SessionToken"]
   env["AWS_REGION"] = config["region"]
   ```

3. **Initializes Remote State** in the central bucket:
   - State key: `<account-name>/terraform.tfstate`
   - Stored centrally but manages child account resources
   - Uses partial backend configuration with `-backend-config` flags

4. **Provisions Infrastructure** by running:
   - `make pipeline-provision-regional` for Regional Clusters (RC)
   - `make pipeline-provision-management` for Management Clusters (MC)

---

## Security Model

### Cross-Account Role Assumption

- **No long-lived credentials** - uses temporary STS tokens only
- **Least privilege** - `OrganizationAccountAccessRole` only exists in child accounts
- **Trust relationship** - Child accounts trust the central management account
- **Audit trail** - All role assumptions logged to CloudTrail

### IAM Permissions Required

The `central-pipeline-codebuild-role` needs:

```hcl
organizations:CreateAccount
organizations:DescribeAccount
organizations:ListAccounts
organizations:MoveAccount
organizations:TagResource
sts:AssumeRole (on arn:aws:iam::*:role/OrganizationAccountAccessRole)
```

See: [terraform/config/central-pipeline/main.tf](../terraform/config/central-pipeline/main.tf#L70-L147)

---

## Pipeline Flow

```
[Git Commit] → [CodePipeline] → [CodeBuild] → [orchestrate_deploy.py]
                                                      ↓
                                         [Stage 1: Apply region-deploy]
                                                      ↓
                                         [AWS Organizations creates accounts]
                                                      ↓
                                         [Read terraform output: accounts map]
                                                      ↓
                                         [For each account: Assume Role]
                                                      ↓
                                         [Initialize terraform backend]
                                                      ↓
                                         [Deploy cluster infrastructure]
```

---

## Key Features

1. **Declarative**: Add a YAML file, commit, push → accounts are created
2. **Idempotent**: Re-running is safe; AWS Organizations handles existing accounts
3. **Isolated**: Each cluster gets its own AWS account boundary
4. **Centralized State**: All Terraform state stored in central S3 bucket with org-wide access policy
5. **No Manual Steps**: Fully automated from YAML to running cluster
6. **Safety**: `close_on_deletion = false` prevents accidental account closure

---

## State Management

The central state bucket (created in `terraform/config/central-pipeline/main.tf`) uses:

- **Versioning enabled** for rollback capability
- **Bucket policy** allowing organization-wide access:
  ```hcl
  Condition = {
    StringEquals = {
      "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
    }
  }
  ```
- **State key structure**: `<account-name>/terraform.tfstate` for isolation

This design enables the central pipeline to manage infrastructure across dozens of isolated AWS accounts without manual intervention or long-lived credentials.

---

## Related Documentation

- [Central Pipeline Configuration](../terraform/config/central-pipeline/README.md)
- [Region Deploy Configuration](../terraform/config/region-deploy/README.md)
- [Orchestration Script Details](../terraform/config/region-deploy/scripts/README.md)
- [Central Pipeline FAQ](../terraform/config/central-pipeline/FAQ.md)
