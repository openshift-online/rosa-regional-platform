# ROSA Regional Platform - ArgoCD Configuration

This directory contains the ArgoCD configuration structure for the ROSA Regional Platform, implementing a shard-based approach where each region operates independently with its own ArgoCD instances.

## Architecture Overview

```
argocd/
├── config.yaml                    # 🎯 Single source of truth for all shards
├── scripts/render.py              # 🔄 Generates region-specific values
├── rendered/                      # 📁 Generated outputs (DO NOT EDIT)
│   └── {environment}/{sector}/{region}/
│       ├── managementcluster-values.yaml
│       └── regionalcluster-values.yaml
├── managementcluster/             # 🏗️  Management cluster helm charts
│   ├── argocd/                    # ArgoCD self-management
│   └── hypershift/                # HyperShift operator
└── regionalcluster/               # 🏗️  Regional cluster helm charts
    └── argocd/                    # ArgoCD self-management
```

## How It Works

### 1. Configuration Sources

**Default Values**: Stored in helm chart `values.yaml` files
```bash
argocd/managementcluster/argocd/values.yaml     # Management cluster defaults
argocd/managementcluster/hypershift/values.yaml # HyperShift defaults
argocd/regionalcluster/argocd/values.yaml       # Regional cluster defaults
```

**Region Overrides**: Defined in the single registry file
```bash
argocd/config.yaml                              # All shard configurations
```

### 2. Render Process

The render script merges configuration in this order:
1. **Chart defaults** (from `values.yaml` files) - baseline configuration
2. **Region overrides** (from `config.yaml`) - shard-specific customizations
3. **Output**: Override-only files in `rendered/` directory

```bash
# Generate all region-specific values
argocd/scripts/render.py
```

### 3. Chart Version Control

**Dynamic Chart Versions**: Uses ArgoCD Application templates (not Chart.yaml dependencies)

```yaml
# ArgoCD Application template references dynamic versions
spec:
  source:
    chart: argo-cd
    targetRevision: {{ .Values.argocd.chart-version | quote }}  # 🎯 Dynamic per region!
```

**Per-Region Versions**: Controlled via config.yaml
```yaml
# config.yaml example
shards:
  - region: "eu-west-1"
    values:
      managementcluster:
        argocd:
          chart-version: "9.0.0"    # Override for this region
      regionalcluster:
        argocd:
          chart-version: "9.0.0"    # Both clusters use same version
```

## Configuration Workflow

### To Add a New Region

1. **Add shard to config.yaml**:
```yaml
shards:
  - region: "ap-southeast-1"
    environment: "production"
    sector: "prod"
    values:
      managementcluster:
        hypershift:
          oidcStorageS3Bucket:
            name: "hypershift-mc-ap-southeast-1"
            region: "ap-southeast-1"
```

2. **Run render script**:
```bash
argocd/scripts/render.py
```

3. **Deploy**: Use rendered values files for cluster provisioning

### To Update Chart Versions

**Global Default**: Edit helm chart values.yaml
```bash
# Update default for all regions
vim argocd/managementcluster/argocd/values.yaml
```

**Region-Specific**: Add override to config.yaml
```yaml
# Override for specific region only
shards:
  - region: "us-east-1"
    values:
      managementcluster:
        argocd:
          chart-version: "9.2.0"  # Only this region gets 9.2.0
```

### To Update Application Configuration

**Global Settings**: Edit helm chart values
```bash
# Change ArgoCD server replicas for all regions
vim argocd/managementcluster/argocd/values.yaml
```

**Region Overrides**: Use config.yaml namespaced values
```yaml
shards:
  - region: "eu-west-1"
    values:
      managementcluster:
        # ArgoCD chart configuration
        argocd:
          chart-version: "9.1.0"
        # HyperShift chart configuration
        hypershift:
          hypershift:
            image: "quay.io/acm-d/rhtap-hypershift-operator:v4.14.0"
```

## Value Namespacing

**Problem**: Multiple charts have overlapping configuration keys (e.g., `replicas`, `image`)

**Solution**: Namespace values by chart to prevent conflicts

```yaml
# ✅ Namespaced approach
argocd:           # ArgoCD chart values
  chart-version: "9.3.4"
  server:
    replicas: 2

hypershift:       # HyperShift chart values
  image: "custom-image"
  replicas: 1

prometheus:       # Future: Prometheus chart values
  retention: "30d"
```

## Cluster Types

### Management Cluster (MC)
**Purpose**: Hosts customer control planes via HyperShift
**Charts**: ArgoCD + HyperShift
**Scaling**: Multiple per region as demand grows

### Regional Cluster (RC)
**Purpose**: Core platform services (CLM, Maestro, API Gateway)
**Charts**: ArgoCD only
**Scaling**: One per region

## Key Features

✅ **Per-Region Chart Versions**: Different regions can run different software versions
✅ **Namespaced Values**: No conflicts between chart configurations
✅ **Override-Only Output**: Rendered files contain only region-specific changes
✅ **GitOps Native**: Uses ArgoCD Applications instead of static Chart dependencies
✅ **Clean Separation**: Defaults in charts, overrides in config.yaml
✅ **Auto-Discovery**: Render script automatically finds cluster types

## Important Notes

### DO NOT EDIT
- Files in `rendered/` directory - they are auto-generated
- `Chart.yaml` dependencies - we use ArgoCD Applications instead

### DO EDIT
- `config.yaml` - for region-specific overrides
- `values.yaml` files in charts - for global defaults

### Workflow Summary
1. **Defaults**: Edit `values.yaml` in helm charts
2. **Overrides**: Edit `config.yaml`
3. **Render**: Run `argocd/scripts/render.py`
4. **Deploy**: Use generated files in `rendered/`

## Examples

### Example: Adding Production Environment

```yaml
# config.yaml
shards:
  - region: "eu-west-1"
    environment: "production"
    sector: "prod"
    values:
      # Use stable versions for production
      managementcluster:
        argocd:
          chart-version: "9.1.0"    # Stable version
        hypershift:
          oidcStorageS3Bucket:
            name: "hypershift-mc-prod-eu-west-1"
            region: "eu-west-1"
      regionalcluster:
        argocd:
          chart-version: "9.1.0"    # Match MC version
```

### Example: Emergency ArgoCD Downgrade

```yaml
# Quickly downgrade all ArgoCD instances in us-east-1
shards:
  - region: "us-east-1"
    environment: "integration"
    sector: "dev"
    values:
      managementcluster:
        argocd:
          chart-version: "9.0.1"    # Emergency downgrade
      regionalcluster:
        argocd:
          chart-version: "9.0.1"    # Match version
```

Run `argocd/scripts/render.py` and deploy the generated override files.

---

*This configuration system provides maximum flexibility while maintaining operational simplicity through GitOps automation.*