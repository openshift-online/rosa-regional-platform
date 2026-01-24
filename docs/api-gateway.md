# API Gateway Setup Guide

This document describes the API Gateway infrastructure and the steps required to set it up from scratch.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS (SigV4 Signed Request)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AWS API GATEWAY (REST API)                            │
│                        Type: REGIONAL                                        │
│                        Auth: AWS_IAM (SigV4)                                 │
│                        Routes: {proxy+} catch-all                            │
│                                                                              │
│                        Identity Headers Added:                               │
│                        - X-Amz-Caller-Arn                                    │
│                        - X-Amz-Account-Id                                    │
│                        - X-Amz-User-Id                                       │
│                        - X-Amz-Source-Ip                                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTP (Port 80)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              VPC LINK (v2)                                   │
│                              Private connection into VPC                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTP (Port 80)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     INTERNAL APPLICATION LOAD BALANCER                       │
│                     Type: Internal ALB                                       │
│                     Listener: Port 80 → Target Group                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTP (Port 8080)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TARGET GROUP (IP type)                             │
│                           Health Check: /v0/live                             │
│                           Port: 8080 (configurable)                          │
│                                                                              │
│                           Targets managed by TargetGroupBinding CR           │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Pod IPs registered by AWS LBC
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           KUBERNETES PODS                                    │
│                           rosa-regional-frontend                             │
│                           Port: 8080                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Terraform Changes Summary

### 1. EKS Cluster Module (`terraform/modules/eks-cluster/`)

**outputs.tf** - Added `node_security_group_id` output:
```hcl
output "node_security_group_id" {
  description = "EKS node security group ID (for Auto Mode, this is the cluster primary SG)"
  value       = module.eks.cluster_primary_security_group_id
}
```

> **Important**: EKS Auto Mode uses `cluster_primary_security_group_id` for nodes/pods, NOT `cluster_security_group_id`. This was a key finding during troubleshooting.

### 2. API Gateway Module (`terraform/modules/api-gateway/`)

**variables.tf** - Added `node_security_group_id` variable:
```hcl
variable "node_security_group_id" {
  description = "EKS node/pod security group ID - ALB needs to send traffic to pods via this SG"
  type        = string
}
```

**security-groups.tf** - Added ingress rule to node security group:
```hcl
resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = var.node_security_group_id
  description                  = "Allow ALB health checks and traffic to pods"
  ip_protocol                  = "tcp"
  from_port                    = var.target_port
  to_port                      = var.target_port
  referenced_security_group_id = aws_security_group.alb.id
}
```

### 3. Regional Cluster Config (`terraform/config/regional-cluster/`)

**main.tf** - Pass node security group to API Gateway module:
```hcl
module "api_gateway" {
  source = "../../modules/api-gateway"

  vpc_id                 = module.regional_cluster.vpc_id
  private_subnet_ids     = module.regional_cluster.private_subnets
  resource_name_base     = module.regional_cluster.resource_name_base
  region_name            = var.region_name
  node_security_group_id = module.regional_cluster.node_security_group_id
}
```

**outputs.tf** - Added node security group output:
```hcl
output "node_security_group_id" {
  description = "EKS node/pod security group ID (Auto Mode primary SG)"
  value       = module.regional_cluster.node_security_group_id
}
```

## In-Cluster Changes (Kubernetes)

### 1. AWS Load Balancer Controller

The AWS LBC must be installed in the cluster to manage TargetGroupBinding CRs.

**Installation Steps:**

```bash
# Step 1: From LOCAL machine - Set up IAM resources
cd terraform/config/regional-cluster
../../../scripts/install-aws-load-balancer-controller.sh --from-terraform

# Step 2: From BASTION - Install Helm chart
./install-aws-load-balancer-controller-helm.sh \
  --cluster-name <cluster-name> \
  --vpc-id <vpc-id> \
  --region <region>
```

**What gets created:**
- IAM Policy: `AWSLoadBalancerControllerIAMPolicy`
- IAM Role: `{cluster-name}-aws-lbc` with Pod Identity trust
- Pod Identity Association: `kube-system/aws-load-balancer-controller`
- Helm Release: `aws-load-balancer-controller` in `kube-system`

### 2. TargetGroupBinding Custom Resource

Create a TargetGroupBinding to register pod IPs with the ALB target group:

```yaml
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: rosa-regional-frontend
  namespace: rosa-regional-frontend
spec:
  serviceRef:
    name: rosa-regional-frontend
    port: 8080
  targetGroupARN: <from terraform output api_target_group_arn>
  targetType: ip
```

### 3. Application Pod Identity (if app needs AWS access)

If your application needs to call AWS services (e.g., DynamoDB):

```bash
# Create IAM role
aws iam create-role \
  --role-name rosa-regional-frontend \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "pods.eks.amazonaws.com"},
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }]
  }'

# Attach required policies
aws iam attach-role-policy \
  --role-name rosa-regional-frontend \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

# Create Pod Identity association
aws eks create-pod-identity-association \
  --cluster-name <cluster-name> \
  --namespace rosa-regional-frontend \
  --service-account rosa-regional-frontend \
  --role-arn arn:aws:iam::<account-id>:role/rosa-regional-frontend \
  --region <region>
```

## Deployment Order

```
1. Terraform Apply
   └── Creates: VPC, EKS, API Gateway, ALB, Target Group, Security Groups

2. Install AWS Load Balancer Controller
   ├── Local: IAM Policy, Role, Pod Identity Association
   └── Bastion: Helm chart installation

3. Deploy Application
   └── Deployment, Service, ServiceAccount

4. Create TargetGroupBinding
   └── LBC registers pod IPs in target group

5. Test API Gateway
   └── awscurl with SigV4 signing
```

## Verification Scripts

### Available Scripts

| Script | Purpose | Run From |
|--------|---------|----------|
| `check-targetgroupbinding.sh` | Verify TargetGroupBinding, target health, LBC status | Local |
| `install-aws-load-balancer-controller.sh` | IAM setup for LBC (includes `--verify` and `--fix` options) | Local |
| `install-aws-load-balancer-controller-helm.sh` | Helm installation of LBC | Bastion |

### Usage Examples

```bash
# Verify TargetGroupBinding setup
./scripts/check-targetgroupbinding.sh \
  $(terraform output -raw api_target_group_arn) \
  rosa-regional-frontend

# Verify LBC IAM setup
./scripts/install-aws-load-balancer-controller.sh --verify --from-terraform

# Fix broken Pod Identity association
./scripts/install-aws-load-balancer-controller.sh --fix --from-terraform
```

## Testing the API

```bash
# Get the invoke URL
cd terraform/config/regional-cluster
terraform output api_gateway_invoke_url

# Test with awscurl (SigV4 signing required)
awscurl --service execute-api --region <region> \
  https://<api-id>.execute-api.<region>.amazonaws.com/prod/v0/live

# Expected response
{"status":"ok"}
```

## Troubleshooting

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Pod Identity null role** | LBC logs show auth errors | Run `--fix` option on install script |
| **Region mismatch** | "not a valid target group ARN" | Ensure LBC Helm `--region` matches target group region |
| **Security group blocking** | Health check timeout | Verify `node_security_group_id` has ingress from ALB SG |
| **Wrong security group** | Health checks fail despite rules | EKS Auto Mode uses `cluster_primary_security_group_id`, not `cluster_security_group_id` |
| **Forbidden on API Gateway** | `{"message":"Forbidden"}` | Add `execute-api:Invoke` permission to caller's IAM |
| **Wrong stage name** | 403 or 404 errors | Use correct stage (default: `prod`, not `api`) |

### Diagnostic Commands

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <arn> \
  --region <region>

# Check Pod Identity associations
aws eks list-pod-identity-associations \
  --cluster-name <cluster> \
  --region <region>

# Check which security group nodes use (EKS Auto Mode)
aws ec2 describe-instances \
  --instance-ids <node-instance-id> \
  --region <region> \
  --query 'Reservations[0].Instances[0].SecurityGroups'

# Check LBC logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Test health endpoint from inside cluster
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -- \
  curl -v http://<pod-ip>:8080/v0/live
```

## Key Learnings

1. **EKS Auto Mode Security Groups**: Auto Mode uses `cluster_primary_security_group_id` for nodes/pods, which is different from the standard `cluster_security_group_id`. Security group rules must be added to the correct SG.

2. **Pod Identity Association**: Must have a valid role ARN. A `null` role ARN causes authentication failures. Use `--verify` to check and `--fix` to repair.

3. **LBC Region Configuration**: The AWS Load Balancer Controller Helm chart must be configured with the same region as the target group. Mismatched regions cause "not a valid target group ARN" errors.

4. **Two-Step LBC Installation**: For private EKS clusters, IAM setup runs locally (AWS API calls) and Helm installation runs from bastion (needs kubectl access).

5. **API Gateway Stage Names**: The URL path includes the stage name (default: `prod`). Using the wrong stage returns 403 Forbidden.
