# frontend-api Helm Chart

Helm chart for the ROSA Regional Frontend API with Envoy sidecar proxy.

## Overview

This chart deploys:
- Frontend API application with authorization middleware
- Envoy sidecar for unified traffic routing
- Service exposing ports 8080 (Envoy), 8000 (API), 8081 (health), 9090 (metrics)
- TargetGroupBinding for AWS Application Load Balancer integration

## Prerequisites

- Kubernetes cluster (EKS recommended)
- AWS Load Balancer Controller installed
- Target Group ARN for the Application Load Balancer

## Configuration

See [values.yaml](values.yaml) for all configuration options. Key settings:

```yaml
frontendApi:
  namespace: frontend-api

  app:
    name: frontend-api
    image:
      repository: quay.io/cdoan0/rosa-regional-frontend-api
      tag: nodb
    args:
      allowedAccounts: "123456789012"  # Comma-separated AWS account IDs
      maestroUrl: http://maestro:8000

  envoy:
    enabled: true

  targetGroup:
    arn: "PLACEHOLDER"  # AWS Target Group ARN
    targetType: ip
```

## Installation

### Basic Installation

```bash
helm install frontend-api ./deployment/helm/rosa-regional-frontend
```

### Production Installation with Custom Values

```bash
helm install frontend-api ./deployment/helm/rosa-regional-frontend \
  --set frontendApi.targetGroup.arn="arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/frontend-api/abc123def456" \
  --set frontendApi.app.args.allowedAccounts="111111111111,222222222222,333333333333"
```

### Using a Custom Values File

Create a `custom-values.yaml`:

```yaml
frontendApi:
  app:
    image:
      tag: "v1.2.3"
    args:
      allowedAccounts: "111111111111,222222222222"
      maestroUrl: http://maestro.maestro.svc.cluster.local:8000
      logLevel: debug

  targetGroup:
    arn: "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/frontend-api/abc123def456"

  deployment:
    replicas: 3

  app:
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 1Gi
```

Install with custom values:

```bash
helm install frontend-api ./deployment/helm/rosa-regional-frontend \
  -f custom-values.yaml
```

## Upgrading

```bash
helm upgrade frontend-api ./deployment/helm/rosa-regional-frontend \
  --set frontendApi.targetGroup.arn="arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/frontend-api/abc123def456" \
  --set frontendApi.app.args.allowedAccounts="111111111111,222222222222"
```

## Uninstallation

```bash
helm uninstall frontend-api
```

To also delete the namespace:

```bash
kubectl delete namespace frontend-api
```

## Parameters

### Application Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `frontendApi.namespace` | Namespace to deploy into | `frontend-api` |
| `frontendApi.app.name` | Application name | `frontend-api` |
| `frontendApi.app.image.repository` | Container image repository | `quay.io/cdoan0/rosa-regional-frontend-api` |
| `frontendApi.app.image.tag` | Container image tag | `nodb` |
| `frontendApi.app.args.allowedAccounts` | Comma-separated AWS account IDs | `"123456789012"` |
| `frontendApi.app.args.maestroUrl` | Maestro service URL | `http://maestro:8000` |
| `frontendApi.app.args.logLevel` | Log level (debug, info, warn, error) | `info` |
| `frontendApi.deployment.replicas` | Number of replicas | `1` |

### Envoy Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `frontendApi.envoy.enabled` | Enable Envoy sidecar | `true` |
| `frontendApi.envoy.image.repository` | Envoy image repository | `envoyproxy/envoy` |
| `frontendApi.envoy.image.tag` | Envoy image tag | `v1.31-latest` |

### Target Group Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `frontendApi.targetGroup.arn` | AWS Target Group ARN | `"PLACEHOLDER"` |
| `frontendApi.targetGroup.targetType` | Target type (ip or instance) | `ip` |

## Architecture

```
┌─────────────────────────────────────────┐
│   Application Load Balancer (ALB)      │
└────────────────┬────────────────────────┘
                 │ :8080
                 │
┌────────────────▼────────────────────────┐
│           Envoy Sidecar :8080           │
│  Routes based on path:                  │
│  • /api/* → app:8000                    │
│  • /v0/live → app:8081 (/healthz)       │
│  • /v0/ready → app:8081 (/readyz)       │
│  • /metrics → app:9090                  │
└────────────────┬────────────────────────┘
                 │
     ┌───────────┼───────────┐
     │           │           │
     ▼           ▼           ▼
   :8000       :8081       :9090
    API       Health      Metrics
```

## Health Checks

The application exposes health endpoints on port 8081:
- `/healthz` - Liveness probe
- `/readyz` - Readiness probe

Kubernetes probes check these endpoints directly (not through Envoy).

## API Endpoints

All API endpoints require the `X-Amz-Account-Id` header with an allowed AWS account ID:

```bash
curl -s http://localhost:8080/api/v0/management_clusters \
  -H "X-Amz-Account-Id: 123456789012"
```

## Troubleshooting

### Check pod status
```bash
kubectl get pods -n frontend-api
kubectl describe pod -n frontend-api <pod-name>
```

### View logs
```bash
# Application logs
kubectl logs -n frontend-api <pod-name> -c frontend-api

# Envoy logs
kubectl logs -n frontend-api <pod-name> -c envoy
```

### Check TargetGroupBinding
```bash
kubectl get targetgroupbinding -n frontend-api
kubectl describe targetgroupbinding -n frontend-api frontend-api
```

### Test health endpoints
```bash
# Port-forward to test locally
kubectl port-forward -n frontend-api svc/frontend-api 8080:8080

# Test via Envoy
curl http://localhost:8080/v0/live
curl http://localhost:8080/v0/ready
```
