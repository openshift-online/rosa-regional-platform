# Maestro Agent Helm Chart

Helm chart for deploying Maestro Agent on management clusters to receive workload distribution from the Maestro Server via AWS IoT Core MQTT broker.

## Overview

The Maestro Agent runs in management clusters and:
- Subscribes to MQTT topics on AWS IoT Core to receive ManifestWorks from Maestro Server
- Applies received ManifestWorks to the local management cluster
- Publishes agent status events back to Maestro Server
- Maintains network isolation from the regional cluster (no VPC peering required)

## Architecture

```
Regional Cluster                    Management Cluster
┌─────────────────┐                ┌──────────────────┐
│ Maestro Server  │                │ Maestro Agent    │
│ - Publishes     │                │ - Subscribes     │
│   sourceevents  │──┐          ┌──│   sourceevents   │
│ - Subscribes    │  │          │  │ - Publishes      │
│   agentevents   │◄─┘          └─►│   agentevents    │
└─────────────────┘                └──────────────────┘
        │                                   │
        └────────────► AWS IoT Core ◄───────┘
                       (MQTT Broker)
                       Port 8883
```

## Prerequisites

### Regional Cluster (Required)
1. Regional cluster Terraform applied with this cluster's ID in `management_cluster_ids`
2. Maestro infrastructure module has created:
   - IAM role for this agent
   - IoT Thing and certificate
   - Secrets Manager secret with MQTT certificate
3. Cross-account trust configured (if management cluster is in different AWS account)

### Management Cluster
1. EKS cluster with Pod Identity enabled
2. ASCP CSI driver installed (`aws-secrets-store-csi-driver` EKS addon)
3. ArgoCD running (if deploying via ArgoCD)
4. Network access to AWS IoT Core endpoint (port 8883)

## Installation

### Step 1: Get Configuration from Regional Cluster

From the regional cluster Terraform directory:

```bash
cd <regional-cluster-terraform-dir>
terraform output -json maestro_agent_configuration
```

Note the values for your management cluster ID.

### Step 2: Configure Management Cluster Terraform

In `terraform/config/management-cluster/terraform.tfvars`:

```hcl
maestro_enabled = true
maestro_agent_role_arn = "arn:aws:iam::123456789012:role/management-abc123-maestro-agent"
```

Apply Terraform:

```bash
cd terraform/config/management-cluster
terraform apply
```

### Step 3: Generate Values Override

```bash
./scripts/populate-maestro-agent-values.sh
```

This generates `charts/maestro-agent/values-override.yaml` with cluster-specific configuration.

### Step 4: Deploy Agent

**Option A: Via Helm (for testing)**

```bash
helm upgrade --install maestro-agent ./charts/maestro-agent \
  -n maestro --create-namespace \
  -f charts/maestro-agent/values.yaml \
  -f charts/maestro-agent/values-override.yaml
```

**Option B: Via ArgoCD (recommended)**

```bash
kubectl apply -f argocd/management-cluster/maestro-agent.yaml
```

## Configuration

### Required Values

These must be populated in `values-override.yaml`:

| Value | Description | Example |
|-------|-------------|---------|
| `maestro.consumerName` | Management cluster ID | `management-abc123` |
| `broker.endpoint` | AWS IoT Core MQTT endpoint | `xxx.iot.us-east-1.amazonaws.com` |
| `ascp.mqttCertSecretName` | Secrets Manager secret name | `management-abc123/maestro/agent-mqtt-cert` |

### Optional Values

See `values.yaml` for all configurable options:

- `deployment.replicas` - Number of agent replicas (default: 1)
- `deployment.requests/limits` - Resource requirements
- `maestro.glog_v` - Logging verbosity (default: 10)
- `image.tag` - Container image tag (default: latest)

## Cross-Account Setup

**CRITICAL**: If the management cluster runs in a different AWS account than the regional cluster, the regional cluster Terraform **must** configure cross-account access.

### Regional Cluster Requirements

In `terraform/config/regional-cluster/terraform.tfvars`:

```hcl
management_cluster_ids = ["management-abc123"]
management_cluster_account_ids = ["987654321098"]  # Management cluster account
```

This configures:
1. IAM role trust policy to allow management cluster account to assume the role
2. Secrets Manager resource policy to allow management cluster account to read secrets

## Verification

### Check Agent Status

```bash
kubectl get pods -n maestro
kubectl logs -n maestro -l app=maestro-agent --tail=50
```

Look for:
- `MQTT connection successful`
- `Subscribed to topic: sources/maestro/consumers/{cluster-id}/sourceevents`

### Test End-to-End

From regional cluster with access to Maestro Server:

```bash
# Port-forward to Maestro Server
kubectl port-forward -n maestro svc/maestro-grpc 8090:8090

# Create test ConfigMap ManifestWork
grpcurl -plaintext -d '{
  "manifest": {
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {"name": "test-from-maestro", "namespace": "default"},
    "data": {"message": "Hello from Maestro!"}
  }
}' -H "consumer-name: management-abc123" \
  localhost:8090 maestro.ManifestWorkService/Create
```

On management cluster:

```bash
kubectl get configmap test-from-maestro -n default
```

## Troubleshooting

### Agent Pod Not Starting

Check ASCP CSI driver:
```bash
kubectl get csidriver secrets-store.csi.k8s.io
kubectl get pods -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver
```

Check Pod Identity:
```bash
kubectl get sa maestro-agent -n maestro -o yaml
# Should have annotation: eks.amazonaws.com/role-arn
```

### Secrets Not Mounting

Verify secret exists in regional account:
```bash
aws secretsmanager describe-secret --secret-id management-abc123/maestro/agent-mqtt-cert
```

Check SecretProviderClass:
```bash
kubectl describe secretproviderclass -n maestro
```

Check pod events:
```bash
kubectl describe pod -n maestro -l app=maestro-agent
```

### MQTT Connection Failures

Check agent logs:
```bash
kubectl logs -n maestro -l app=maestro-agent
```

Common issues:
- **Certificate invalid**: Check secret contents and expiry
- **Endpoint unreachable**: Verify network access to IoT Core endpoint
- **Access denied**: Verify cross-account IAM trust and IoT policy

### Cross-Account Access Denied

If you see IAM or Secrets Manager access denied errors:

1. Verify regional cluster has `management_cluster_account_ids` configured
2. Check IAM role trust policy:
   ```bash
   aws iam get-role --role-name management-abc123-maestro-agent
   ```
3. Check Secrets Manager resource policy:
   ```bash
   aws secretsmanager get-resource-policy --secret-id management-abc123/maestro/agent-mqtt-cert
   ```

## Resources Created

- **Deployment**: maestro-agent (1 replica)
- **ServiceAccount**: maestro-agent (with Pod Identity annotation)
- **ConfigMap**: maestro-agent-mqtt-config (MQTT broker configuration)
- **SecretProviderClass**: maestro-agent-secrets (ASCP CSI driver)

No services are created (agent subscribes only, no HTTP/gRPC endpoints).

## Uninstallation

```bash
helm uninstall maestro-agent -n maestro
```

Or via ArgoCD:

```bash
kubectl delete application maestro-agent -n argocd
```

**Note**: This does not delete the namespace or resources created in the regional cluster.

## References

- [Maestro Server Chart](../maestro-server/)
- [Plan Document](/home/psavage/.claude/plans/buzzing-dazzling-crystal.md)
- [ARO-HCP Maestro Agent](https://github.com/Azure/ARO-HCP/tree/main/maestro/agent)
- [AWS Secrets Store CSI Driver](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
