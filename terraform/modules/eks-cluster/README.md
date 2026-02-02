# EKS Cluster Module

Creates private EKS clusters with security-first configuration and standardized naming/tagging.

## Features

- **Automatic Resource Naming**: Generates unique resource names with cluster type + random suffix
- **Provider-Level Tagging**: Enforces required organizational tags via AWS provider default_tags
- **Fully Private Clusters**: EKS control plane with private endpoint only
- **GitOps Bootstrap**: Automated ArgoCD installation via Lambda for self-management
- **Security Hardening**: KMS encryption, IMDSv2 enforcement, and network segmentation
- **High Availability**: Multi-AZ NAT Gateways for fault-tolerant egress connectivity

## Security & Scalability Enhancements

### Network Security
- **KMS Encryption**: Kubernetes secrets encrypted at rest using customer-managed keys
- **Dedicated Security Groups**: VPC endpoints use isolated security groups (port 443 from VPC CIDR only)
- **Restricted Egress**: Cluster egress limited to HTTPS for container registries and VPC internal traffic
- **Auto Mode Authentication**: EKS authentication configured for API_AND_CONFIG_MAP mode

### High Availability Network Architecture
- **Multi-AZ NAT Deployment**: One NAT Gateway per availability zone eliminates single points of failure
- **Per-AZ Route Tables**: Traffic distribution across availability zones for fault isolation
- **Improved Resilience**: AZ outages don't impact other zones' external connectivity

## Naming Convention

All resources are automatically named using the pattern: `{cluster_type}-{random_suffix}`

**Examples:**
- EKS Cluster: `management-x8k2`
- VPC: `management-x8k2-vpc`
- Node Group: `management-x8k2-main-node-group`
- IAM Roles: `management-x8k2-ebs-csi-driver`

The random suffix (4 lowercase alphanumeric characters) prevents naming conflicts and is automatically generated.

## Required Provider Configuration

**IMPORTANT**: You must configure the required tags in your AWS provider's `default_tags`:

```hcl
provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      app-code      = "APP001"        # CMDB Application ID (required)
      service-phase = "development"   # development, staging, or production (required)
      cost-center   = "123"          # 3-digit cost center code (required)
    }
  }
}
```

## Usage

### Management Cluster

```hcl
module "management_cluster" {
  source = "./terraform/modules/eks-cluster"

  cluster_type = "management"

  # Bootstrap configuration for management cluster
  bootstrap_enabled           = true
  bootstrap_repository_url    = "https://github.com/openshift-online/rosa-regional-platform"
  bootstrap_repository_branch = "main"

  # Optional cluster configuration
  cluster_version         = "1.34"
  node_instance_types     = ["t3.medium", "t3a.medium"]
  node_group_desired_size = 1
  node_group_min_size     = 1
  node_group_max_size     = 2
}
```

### Regional Cluster

```hcl
module "regional_cluster" {
  source = "./terraform/modules/eks-cluster"

  cluster_type = "regional"

  # Bootstrap configuration for regional cluster
  bootstrap_enabled           = true
  bootstrap_repository_url    = "https://github.com/openshift-online/rosa-regional-platform"
  bootstrap_repository_branch = "main"

  # Optional cluster configuration
  node_group_desired_size = 2
  node_group_min_size     = 1
  node_group_max_size     = 4
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `cluster_type` | Type of cluster: `regional` or `management` | `string` | n/a | yes |
| `cluster_version` | Kubernetes version | `string` | `"1.34"` | no |
| `vpc_cidr` | VPC CIDR block | `string` | `"10.0.0.0/16"` | no |
| `availability_zones` | List of availability zones (auto-detected if empty) | `list(string)` | `[]` | no |
| `private_subnet_cidrs` | CIDR blocks for private subnets | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]` | no |
| `public_subnet_cidrs` | CIDR blocks for public subnets | `list(string)` | `["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]` | no |
| `node_instance_types` | EC2 instance types for nodes | `list(string)` | `["t3.medium", "t3a.medium"]` | no |
| `node_group_desired_size` | Desired number of nodes | `number` | `2` | no |
| `node_group_min_size` | Minimum number of nodes | `number` | `1` | no |
| `node_group_max_size` | Maximum number of nodes | `number` | `4` | no |
| `node_disk_size` | EBS volume size for nodes (GiB) | `number` | `20` | no |
| `enable_pod_security_standards` | Enable Pod Security Standards | `bool` | `true` | no |
| `bootstrap_enabled` | Enable ArgoCD bootstrap for GitOps management | `bool` | `true` | no |
| `argocd_namespace` | Kubernetes namespace for ArgoCD installation | `string` | `"argocd"` | no |
| `argocd_chart_version` | ArgoCD Helm chart version | `string` | `"9.3.0"` | no |
| `bootstrap_repository_url` | Git repository URL for ArgoCD configuration | `string` | `"https://github.com/openshift-online/rosa-regional-platform"` | no |
| `bootstrap_repository_branch` | Git branch to track | `string` | `"main"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name (includes random suffix) |
| `cluster_endpoint` | EKS cluster API endpoint |
| `cluster_certificate_authority_data` | Base64 encoded certificate data |
| `vpc_id` | VPC ID where cluster is deployed |
| `private_subnets` | Private subnet IDs where worker nodes are deployed |
| `cluster_security_group_id` | EKS cluster security group ID |
| `bootstrap_report` | Bootstrap process information and status |

## Bootstrap Functionality

When `bootstrap_enabled` is `true`, the module automatically installs ArgoCD for GitOps management:

1. **Lambda Function**: Executes within cluster VPC for secure bootstrap operations
2. **Tool Installation**: Downloads kubectl, helm, and AWS CLI at runtime
3. **ArgoCD Installation**: Installs ArgoCD via Helm with cluster-only access
4. **GitOps Configuration**: Creates Application of Applications for self-management
5. **Synchronous Execution**: Bootstrap completes during `terraform apply` with visible logs

### Bootstrap Process

The Lambda function:
- Runs in the cluster's private subnets for network access
- Updates kubeconfig using EKS access entries and Pod Identity
- Installs ArgoCD using Helm from the official repository
- Creates bootstrap application pointing to your repository
- Enables ArgoCD to take over cluster management

## Requirements

- Terraform >= 1.14.3
- AWS Provider >= 6.0
- Random Provider >= 3.4
- Required provider `default_tags` configuration
