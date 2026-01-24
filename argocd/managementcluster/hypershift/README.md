# Hypershift Install Helm Chart

This Helm chart installs the Hypershift Operator on a Kubernetes cluster.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Cluster admin privileges (the chart creates ClusterRoleBindings)

### Required CRDs (Prerequisites)

The following CRDs **must be installed before** installing the Hypershift Operator. These are located in the `crds/` directory and are **NOT** part of the operator itself:

- ServiceMonitors (monitoring.coreos.com)
- PrometheusRules (monitoring.coreos.com)
- PodMonitors (monitoring.coreos.com)
- Routes (route.openshift.io)

Helm will automatically install CRDs from the `crds/` directory before installing the chart resources.

## Installation

### Install the chart (including prerequisite CRDs)

```bash
helm install hypershift-install ./hypershift-install-chart
```

This will:
1. First install the prerequisite CRDs from the `crds/` directory
2. Then create the namespace, serviceaccount, clusterrolebinding, and installation job

### Install with custom values

```bash
helm install hypershift-install ./hypershift-install-chart \
  --set job.image=quay.io/acm-d/rhtap-hypershift-operator:v1.0.0 \
  --set namespace.name=my-hypershift-ns
```

### Install with a custom values file

```bash
helm install hypershift-install ./hypershift-install-chart -f custom-values.yaml
```

## Uninstallation

```bash
helm uninstall hypershift-install
```

**Note:** The prerequisite CRDs installed by this chart are not removed automatically during uninstallation. To manually remove them:

```bash
kubectl delete crd servicemonitors.monitoring.coreos.com
kubectl delete crd prometheusrules.monitoring.coreos.com
kubectl delete crd podmonitors.monitoring.coreos.com
kubectl delete crd routes.route.openshift.io
```

**Warning:** Only delete these CRDs if no other applications or operators depend on them (e.g., Prometheus Operator).

## Configuration

The following table lists the configurable parameters of the chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `namespace.name` | Name of the namespace to create | `hypershift-install` |
| `serviceAccount.name` | Name of the ServiceAccount | `hypershift-installer` |
| `clusterRoleBinding.name` | Name of the ClusterRoleBinding | `hypershift-installer-cluster-role` |
| `clusterRoleBinding.clusterRole` | ClusterRole to bind | `cluster-admin` |
| `job.name` | Name of the installation job | `install-hypershift` |
| `job.image` | Hypershift operator image | `quay.io/acm-d/rhtap-hypershift-operator:latest` |

**Note:** The following job settings are hardcoded and not configurable:
- Job timeout: 1800 seconds (30 minutes)
- Backoff limit: 1
- Enable conversion webhook: false
- Limit CRD install: AWS

## Chart Components

### Prerequisite CRDs (in `crds/` directory)

These CRDs are **required prerequisites** for the Hypershift Operator and are **NOT** part of the operator itself. They are typically provided by other operators like Prometheus Operator or OpenShift:

- **ServiceMonitors** (monitoring.coreos.com) - Defines how to scrape metrics from services
- **PrometheusRules** (monitoring.coreos.com) - Defines Prometheus alerting and recording rules
- **PodMonitors** (monitoring.coreos.com) - Defines how to scrape metrics from pods
- **Routes** (route.openshift.io) - OpenShift-specific ingress resources

### Operator Installation Resources (in `templates/` directory)

1. **Namespace**: Creates a dedicated namespace for Hypershift installation
2. **ServiceAccount**: Creates a service account with cluster-admin permissions
3. **ClusterRoleBinding**: Binds the service account to cluster-admin role
4. **Job**: Runs the Hypershift Operator installation process

## Verifying the Installation

Check the job status:

```bash
kubectl get jobs -n hypershift-install
kubectl logs -n hypershift-install job/install-hypershift
```

Check installed prerequisite CRDs:

```bash
kubectl get crds | grep -E "servicemonitors|prometheusrules|podmonitors|routes"
```

Check Hypershift Operator installation:

```bash
kubectl get all -n hypershift-install
```

## Customization Examples

### Use a specific image tag

```yaml
# custom-values.yaml
job:
  image: quay.io/acm-d/rhtap-hypershift-operator:v1.2.3
```

### Install in a different namespace

```yaml
# custom-values.yaml
namespace:
  name: my-hypershift-namespace
```
