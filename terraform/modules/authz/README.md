# ROSA Authorization Module

This Terraform module creates AWS resources for ROSA Cedar/AVP-based authorization.

## Overview

The module provisions:

- **DynamoDB Tables**: Storage for accounts, admins, groups, policies, and attachments
- **IAM Roles**: Pod Identity role for Frontend API access to DynamoDB and Amazon Verified Permissions (AVP)
- **Pod Identity Association**: Binds IAM role to Kubernetes service account

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ROSA Frontend API                                │
│                    (rosa-frontend-api namespace)                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Pod Identity
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      IAM Role: authz-frontend-api                        │
│                                                                          │
│  Permissions:                                                            │
│  - DynamoDB: GetItem, PutItem, Query, Scan, UpdateItem, DeleteItem      │
│  - AVP: CreatePolicyStore, CreatePolicy, IsAuthorized, etc.             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │ DynamoDB  │   │ DynamoDB  │   │    AVP    │
            │  Tables   │   │   GSIs    │   │           │
            └───────────┘   └───────────┘   └───────────┘
```

## DynamoDB Tables

| Table | Hash Key | Range Key | GSIs |
|-------|----------|-----------|------|
| `{prefix}-authz-accounts` | `accountId` | - | - |
| `{prefix}-authz-admins` | `accountId` | `principalArn` | - |
| `{prefix}-authz-groups` | `accountId` | `groupId` | - |
| `{prefix}-authz-group-members` | `accountId` | `groupId#memberArn` | `member-groups-index` |
| `{prefix}-authz-policies` | `accountId` | `policyId` | - |
| `{prefix}-authz-attachments` | `accountId` | `attachmentId` | `target-index`, `policy-index` |

## Usage

```hcl
module "authz" {
  source = "../../modules/authz"

  resource_name_base = module.regional_cluster.resource_name_base
  eks_cluster_name   = module.regional_cluster.cluster_name

  # Optional: Production settings
  enable_point_in_time_recovery = true
  enable_deletion_protection    = true

  # Optional: Custom namespace/service account
  frontend_api_namespace       = "rosa-frontend-api"
  frontend_api_service_account = "rosa-frontend-api"

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `resource_name_base` | Base name for all resources | `string` | - | yes |
| `eks_cluster_name` | EKS cluster name for Pod Identity | `string` | - | yes |
| `billing_mode` | DynamoDB billing mode | `string` | `"PAY_PER_REQUEST"` | no |
| `enable_point_in_time_recovery` | Enable PITR for tables | `bool` | `false` | no |
| `enable_deletion_protection` | Enable deletion protection | `bool` | `false` | no |
| `frontend_api_namespace` | K8s namespace for Frontend API | `string` | `"rosa-frontend-api"` | no |
| `frontend_api_service_account` | K8s service account name | `string` | `"rosa-frontend-api"` | no |
| `tags` | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `accounts_table_name` | Name of the accounts table |
| `admins_table_name` | Name of the admins table |
| `groups_table_name` | Name of the groups table |
| `members_table_name` | Name of the members table |
| `policies_table_name` | Name of the policies table |
| `attachments_table_name` | Name of the attachments table |
| `table_names` | Map of all table names |
| `table_arns` | Map of all table ARNs |
| `frontend_api_role_arn` | IAM role ARN for Frontend API |
| `authz_configuration_summary` | Summary for application config |

## Application Configuration

The Frontend API should be configured with the table names from the outputs:

```yaml
authz:
  enabled: true
  awsRegion: us-east-1
  tables:
    accounts: ${accounts_table_name}
    admins: ${admins_table_name}
    groups: ${groups_table_name}
    members: ${members_table_name}
    policies: ${policies_table_name}
    attachments: ${attachments_table_name}
```

## Security

- All DynamoDB tables use encryption at rest (AWS managed keys)
- IAM role uses EKS Pod Identity (no static credentials)
- Least-privilege permissions for DynamoDB and AVP access
- Optional deletion protection for production environments
- Optional point-in-time recovery for data protection
