# EKS Cluster Module

Creates private EKS clusters with security-first configuration.

## Usage

```hcl
module "eks_cluster" {
  source = "./terraform/modules/eks-cluster"

  cluster_name = "my-dev-cluster"
  cluster_type = "regional"
  region       = "us-west-2"
  aws_profile  = "regional-aws-account-1"

  # Optional overrides
  cluster_version         = "1.34"
  node_instance_types     = ["t3.medium", "t3a.medium"]
  node_group_desired_size = 3

  tags = {
    Environment = "integration"
    Team        = "RRP-DEV"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `cluster_name` | Name of the EKS cluster | `string` | n/a | yes |
| `cluster_type` | Type of cluster: regional or management | `string` | n/a | yes |
| `region` | AWS region for resources | `string` | n/a | yes |
| `aws_profile` | AWS CLI profile for authentication | `string` | n/a | yes |
| `cluster_version` | Kubernetes version | `string` | `"1.34"` | no |
| `vpc_cidr` | VPC CIDR block | `string` | `"10.0.0.0/16"` | no |
| `availability_zones` | List of availability zones | `list(string)` | `[]` | no |
| `private_subnet_cidrs` | CIDR blocks for private subnets | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]` | no |
| `public_subnet_cidrs` | CIDR blocks for public subnets | `list(string)` | `["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]` | no |
| `enable_single_nat_gateway` | Use single NAT gateway for cost optimization | `bool` | `true` | no |
| `node_instance_types` | EC2 instance types for nodes | `list(string)` | `["t3.medium", "t3a.medium"]` | no |
| `node_group_desired_size` | Desired number of nodes | `number` | `2` | no |
| `node_group_min_size` | Minimum number of nodes | `number` | `1` | no |
| `node_group_max_size` | Maximum number of nodes | `number` | `4` | no |
| `node_disk_size` | EBS volume size for nodes (GB) | `number` | `20` | no |
| `enable_cluster_encryption` | Enable encryption at rest for EKS secrets | `bool` | `false` | no |
| `enable_pod_security_standards` | Enable Pod Security Standards | `bool` | `true` | no |
| `tags` | Resource tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS cluster API endpoint |
| `cluster_certificate_authority_data` | Base64 encoded certificate data |
| `vpc_id` | VPC ID where cluster is deployed |
| `private_subnets` | Private subnet IDs where worker nodes are deployed |
| `cluster_security_group_id` | EKS cluster security group ID |

## Requirements

- Terraform >= 1.5
- AWS Provider >= 6.0
