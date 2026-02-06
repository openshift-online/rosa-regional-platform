# Centralized Deployment Pipeline Guide

This repository uses a Centralized Pipeline architecture to deploy infrastructure across Regional and Management AWS accounts using AWS Developer Tools (CodePipeline, CodeBuild) and Terraform.

## Architecture

1.  **Central Account:** Hosts the "Central Pipeline".
    *   Watches `deploy/*/regional.yaml`.
    *   Provisions **Regional EKS Clusters**.
    *   Provisions **Regional Pipelines** into the Regional Account.
2.  **Regional Account:** Hosts the "Regional Pipeline".
    *   Watches `deploy/*/management/*.yaml`.
    *   Provisions **Management EKS Clusters**.

---

## Prerequisites

1.  **AWS Accounts:**
    *   **Central Account**: The control plane.
    *   **Regional Account(s)**: Where regional infra lives.
    *   **Management Account(s)**: Where management clusters live.
2.  **IAM Roles:**
    *   `OrganizationAccountAccessRole` must exist in Regional and Management accounts and trust the upstream account (Central or Regional).
3.  **GitHub Repository:**
    *   Connected via AWS CodeStar Connections (managed by Terraform).

---

## 1. Bootstrap (One-Time Setup)

Perform these steps in the **Central Account** to set up the state buckets and the initial pipeline.

### Step 1: Create State Bucket
Run the bootstrap script to create the S3 bucket for Terraform state (uses lockfile-based locking).

```bash
./scripts/bootstrap-state.sh
# Note the bucket name output, e.g., terraform-state-123456789012
```

> **NOTE:** The `bootstrap-state.sh` script creates the state bucket required for all Terraform operations in the central account. Operators must run this bootstrap step first and capture the bucket name for use in subsequent `terraform init` commands. This bucket stores state for both the Pipeline Provisioner and individual Regional/Management cluster pipelines.

### Step 2: Deploy Central Pipeline
Initialize and apply the Terraform configuration for the Central Pipeline.

```bash
cd terraform/config/pipeline-regional-cluster

# 1. Initialize Backend (Replace with your Bucket Name)
terraform init \
  -backend-config="bucket=terraform-state-YOUR_CENTRAL_ACCOUNT_ID" \
  -backend-config="key=pipeline-regional-cluster.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"

# 2. Apply
terraform apply \
  -var="github_repo_owner=openshift-online" \
  -var="github_repo_name=YOUR_REPO_NAME" \
  -var="github_branch=main"
```

### Step 3: Authorize GitHub Connection
1.  Log in to the **AWS Console (Central Account)**.
2.  Go to **Developer Tools > Settings > Connections**.
3.  Find `pipeline-provisioner-github` (Status: Pending).
4.  Click **"Update Pending Connection"** and authorize with GitHub.

---

## 2. Automated Deployment (GitOps)

Once the pipeline is bootstrapped, you can deploy new environments simply by adding YAML files to the repository.

### Deploy a New Region
Create a file `deploy/<region-name>/regional.yaml`:

```yaml
# deploy/us-east-1/regional.yaml
account_id: "987654321098"   # Regional AWS Account ID
region: "us-east-1"          # Target AWS Region
alias: "regional-us-east-1"  # Unique Alias
```

1.  Commit and push this file.
2.  The **Central Pipeline** will trigger.
3.  It will provision the **Regional Cluster** and the **Regional Pipeline** in the target account.
4.  **IMPORTANT:** Once deployed, log in to the **Regional Account** console and authorize the new GitHub connection (named `rc-gh-*` where `*` is a hash-based identifier).

### Deploy a Management Cluster
Create a file `deploy/<region-name>/management/<cluster-name>.yaml`:

```yaml
# deploy/us-east-1/management/prod-cluster.yaml
account_id: "123456789012"   # Management AWS Account ID
region: "us-east-1"          # Target Region
alias: "prod-management"     # Unique Alias
```

1.  Commit and push this file.
2.  The **Regional Pipeline** (running in the Regional Account) will trigger.
3.  It will provision the **Management Cluster** in the target account.

---

## 3. Manual / Test Deployment

You can bypass the GitOps flow and trigger a deployment manually for testing purposes.

### Deploy Central -> Regional Manually
Run Terraform with manual override variables. This configures the pipeline to deploy to a specific target immediately upon execution.

```bash
cd terraform/config/pipeline-regional-cluster

terraform apply \
  -var="github_repo_owner=openshift-online" \
  -var="github_repo_name=YOUR_REPO_NAME" \
  -var="github_branch=your-feature-branch" \
  -var="target_account_id=REGIONAL_ACCOUNT_ID" \
  -var="target_region=us-east-1" \
  -var="target_alias=test-regional"
```

*   The pipeline will run and deploy to the specified Regional Account.
*   It will **skip** processing `deploy/*/regional.yaml` files when manual variables are present.

### Troubleshooting

*   **Error: `Project cannot be found`**: Check that you deployed the Terraform stack to the same region where the pipeline expects it (default `us-east-1`).
*   **Error: `Missing rendered ArgoCD config`**: The pipeline sets `SKIP_ARGOCD_VALIDATION=true` to allow infrastructure-only deployment. Ensure your buildspec includes this export.
*   **State Locking Error**: The infrastructure uses lockfile-based locking. If Terraform state is locked, ensure no other processes are running and use `terraform force-unlock <LOCK_ID>` if needed.
