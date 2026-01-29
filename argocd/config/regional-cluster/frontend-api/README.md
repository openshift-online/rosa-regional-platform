# frontend-api Helm Chart

Helm chart for frontend-api with Envoy sidecar and AWS Load Balancer Controller integration.

## Prerequisites

- AWS Load Balancer Controller installed in the cluster
- Target Group ARN created (typically via Terraform infrastructure provisioning)

## Configuration

### Required Configuration

You'll need to provide the actual Target Group ARN via helm values when deploying (overriding the "PLACEHOLDER" value).

Key configuration values:
- `frontend-api.targetGroup.arn`: AWS Target Group ARN (required - must override the PLACEHOLDER default)
- `frontend-api.targetGroup.targetType`: Target type (default: "ip")
- `frontend-api.app.image.repository`: Container image repository
- `frontend-api.app.image.tag`: Container image tag

See [values.yaml](values.yaml) for all available configuration options.

## Installation

### Basic Installation

```bash
helm install frontend-api ./argocd/config/regional-cluster/frontend-api \
  --namespace frontend-api \
  --create-namespace \
  --set frontend-api.targetGroup.arn=arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-tg/abc123def456
```

### With Custom Values File

```bash
# Create a values override file
cat > my-values.yaml <<EOF
frontend-api:
  targetGroup:
    arn: arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-tg/abc123def456
  app:
    image:
      tag: v1.2.3
EOF

# Install with custom values
helm install frontend-api ./argocd/config/regional-cluster/frontend-api \
  --namespace frontend-api \
  --create-namespace \
  --values my-values.yaml
```

## ArgoCD

When using with ArgoCD, set the Target Group ARN in the Application spec or ApplicationSet values file:

```yaml
spec:
  source:
    helm:
      values: |
        frontend-api:
          targetGroup:
            arn: arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-tg/abc123def456
```
