# Terraform State Bucket Architecture

This document explains the S3 bucket architecture for storing Terraform state across the Regional Platform.

## Overview

The platform uses a centralized state management approach with three distinct S3 buckets, each serving a specific purpose in the infrastructure lifecycle.

## Three-Bucket Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Central Pipeline Account                      │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ S3 Bucket: central-pipeline-state-*                      │   │
│  │ Purpose: Stores central-pipeline's own Terraform state   │   │
│  │ Access: Central account only                             │   │
│  │ Contains:                                                 │   │
│  │   └─ central-pipeline/terraform.tfstate                  │   │
│  │      (CodePipeline, CodeBuild, IAM roles, etc.)          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ S3 Bucket: pipeline-artifacts-*                          │   │
│  │ Purpose: CodePipeline artifacts and build outputs        │   │
│  │ Access: Central account only                             │   │
│  │ Contains: Source code zips, build artifacts              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ S3 Bucket: regional-cluster-tf-state-*                   │   │
│  │ Purpose: State for ALL child clusters and account mint   │   │
│  │ Access: Organization-wide (via bucket policy)            │   │
│  │ Contains:                                                 │   │
│  │   ├─ region-deploy/terraform.tfstate                     │   │
│  │   │  (AWS Organizations account minting)                 │   │
│  │   │                                                       │   │
│  │   ├─ rosa-regional-us-east-1/terraform.tfstate           │   │
│  │   │  (Regional Cluster in us-east-1)                     │   │
│  │   │                                                       │   │
│  │   ├─ rosa-management-us-east-1/terraform.tfstate         │   │
│  │   │  (Management Cluster in us-east-1)                   │   │
│  │   │                                                       │   │
│  │   ├─ rosa-regional-us-west-2/terraform.tfstate           │   │
│  │   └─ rosa-management-us-west-2/terraform.tfstate         │   │
│  │      ... (one per region/cluster)                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Bucket Details

### 1. Central Pipeline State Bucket

**Name Pattern**: `central-pipeline-state-{random}`

**Purpose**: Stores the Terraform state for the central-pipeline infrastructure itself.

**State Files**:
- `central-pipeline/terraform.tfstate` - Pipeline, CodeBuild, IAM roles, S3 buckets

**Access Control**:
- Only accessible from the central account
- No cross-account access needed
- Private bucket with encryption and versioning

**Bootstrap Process**:
1. Initial deployment uses **local state** (backend.tf commented out)
2. First `terraform apply` creates this bucket
3. After creation, uncomment backend.tf and migrate state to S3
4. Future deployments use remote S3 state

**Configuration**:
```hcl
resource "aws_s3_bucket" "central_pipeline_state" {
  bucket_prefix = "central-pipeline-state-"
}
```

### 2. Pipeline Artifacts Bucket

**Name Pattern**: `pipeline-artifacts-{random}`

**Purpose**: Stores CodePipeline artifacts during pipeline execution.

**Contents**:
- Source code archives from GitHub
- Build outputs from CodeBuild
- Temporary files during pipeline execution

**Access Control**:
- Used by CodePipeline and CodeBuild service roles
- Central account only
- Private bucket with encryption and versioning

**Lifecycle**:
- Artifacts are ephemeral
- Can be configured with lifecycle policies for cleanup
- Not used for long-term storage

### 3. Regional Cluster State Bucket

**Name Pattern**: `regional-cluster-tf-state-{random}`

**Purpose**: Centralized state storage for ALL child cluster infrastructure and account minting.

**State Files**:
- `region-deploy/terraform.tfstate` - AWS Organizations account definitions
- `{account-name}/terraform.tfstate` - Individual cluster state files

**Access Control**:
```hcl
# Organization-wide access via bucket policy
Condition = {
  StringEquals = {
    "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
  }
}
```

**Why Centralized?**
- Single source of truth for all cluster states
- Simplified backup and disaster recovery
- Easier to audit and monitor all infrastructure
- No per-account state bucket setup needed
- Organization policy enforces access control

**Security**:
- Bucket policy restricts access to organization members only
- Server-side encryption (AES256)
- Versioning enabled for rollback
- Public access blocked

## Security Features

All three buckets include:

### Versioning
```hcl
resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

**Benefits**:
- State rollback capability if corruption occurs
- Audit trail of all state changes
- Recovery from accidental deletions

### Encryption
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

**Benefits**:
- Data encrypted at rest
- Meets compliance requirements
- No additional cost (SSE-S3)

### Public Access Block
```hcl
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Benefits**:
- Prevents accidental public exposure
- Defense in depth against misconfigurations
- Enforced at bucket level

## State File Organization

### Central Pipeline State

```
s3://central-pipeline-state-{id}/
└── central-pipeline/
    └── terraform.tfstate
```

### Child Cluster States

```
s3://regional-cluster-tf-state-{id}/
├── region-deploy/
│   └── terraform.tfstate          # Account minting
│
├── rosa-regional-us-east-1/
│   └── terraform.tfstate          # Regional Cluster (EKS, VPC, RDS, etc.)
│
├── rosa-management-us-east-1/
│   └── terraform.tfstate          # Management Cluster (EKS, VPC, etc.)
│
├── rosa-regional-us-west-2/
│   └── terraform.tfstate
│
└── rosa-management-us-west-2/
    └── terraform.tfstate
```

## Backend Configuration Examples

### Central Pipeline (backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket = "central-pipeline-state-abc123"
    key    = "central-pipeline/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### Region Deploy (partial config via CLI)

```bash
terraform init -reconfigure \
  -backend-config="bucket=regional-cluster-tf-state-xyz789" \
  -backend-config="key=region-deploy/terraform.tfstate" \
  -backend-config="region=us-east-1"
```

### Child Cluster (partial config via orchestration script)

```bash
terraform init -reconfigure \
  -backend-config="bucket=regional-cluster-tf-state-xyz789" \
  -backend-config="key=rosa-regional-us-east-1/terraform.tfstate" \
  -backend-config="region=us-east-1"
```

## State Locking

**Current**: No state locking implemented (DynamoDB table not created)

**Rationale**:
- Serial pipeline execution prevents concurrent modifications
- Single-operator model (CodeBuild only)
- Can be added later if needed

**Future Enhancement** (Optional):
```hcl
resource "aws_dynamodb_table" "state_lock" {
  name         = "central-pipeline-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

Add to backend config:
```hcl
terraform {
  backend "s3" {
    bucket         = "central-pipeline-state-abc123"
    key            = "central-pipeline/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "central-pipeline-state-lock"
  }
}
```

## Disaster Recovery

### Backup Strategy

1. **S3 Versioning**: All buckets have versioning enabled
2. **Cross-Region Replication** (Optional):
   - Can configure CRR for state buckets
   - Replicates to secondary region
   - Disaster recovery for region failures

3. **State File Exports** (Manual):
   ```bash
   # Download state files locally for backup
   aws s3 sync s3://regional-cluster-tf-state-xyz789/ ./state-backup/
   ```

### Recovery Procedures

**Corrupted State File**:
1. List versions: `aws s3api list-object-versions --bucket {bucket} --prefix {key}`
2. Download previous version: `aws s3api get-object --bucket {bucket} --key {key} --version-id {id} state.tfstate`
3. Restore if needed

**Deleted State File**:
1. If versioning enabled, restore from version history
2. Otherwise, use backup copy
3. Last resort: `terraform import` to rebuild state

**Lost Entire Bucket**:
1. Restore from cross-region replica (if configured)
2. Restore from local/external backups
3. Manual recreation as last resort

## Cost Considerations

### Storage Costs

**Typical State File Sizes**:
- Central pipeline state: ~50 KB
- Region-deploy state: ~10 KB
- Regional cluster state: ~200 KB
- Management cluster state: ~150 KB

**Monthly Cost Estimate** (10 regions):
- Storage: (50KB + 10KB + 20 × 175KB) ≈ 3.6 MB
- Versioning overhead: ~2x = 7.2 MB
- S3 Standard: $0.023/GB = **<$0.01/month**

**Requests**:
- Pipeline executions: ~100 API calls per run
- Cost: Negligible (<$0.01/month)

**Total Estimated Cost**: **<$1/month** for all state storage

## Related Documentation

- [Central Pipeline Configuration](../terraform/config/central-pipeline/README.md)
- [Account Minting Process](account-minting-process.md)
- [Region Deploy Configuration](../terraform/config/region-deploy/README.md)
