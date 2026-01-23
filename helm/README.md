# Helm Charts

Custom Helm charts for applications that don't have dedicated repositories.

These charts will be referenced by ArgocD `Application` or `ApplicationSets` under `argocd/config/**` to be deployed on target clusters.

## Usage

### Test a chart
```bash
helm template ./charts/<chart-name> --set key=value
```

## Development

- Follow Helm best practices for chart structure
- Include comprehensive README.md for each chart
- Use semantic versioning in Chart.yaml
- Test charts with `helm template` and `helm lint`

For detailed chart documentation, see individual chart README files.