#!/bin/bash
# Quick validation for ArgoCD rendered config before provisioning
set -euo pipefail

CLUSTER_TYPE="${1:-}"
ENVIRONMENT="${2:-integration}"
REGION="${3:-$(aws configure get region 2>/dev/null || echo "us-east-1")}"

if [[ -z "$CLUSTER_TYPE" ]]; then
    echo "Usage: $0 <cluster-type> [environment] [region]"
    exit 1
fi

REQUIRED_FILES=(
    "argocd/rendered/${ENVIRONMENT}/${REGION}/${CLUSTER_TYPE}-values.yaml"
    "argocd/rendered/${ENVIRONMENT}/${REGION}/${CLUSTER_TYPE}-manifests/applicationset.yaml"
)

missing_files=()
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "❌ ERROR: Missing rendered ArgoCD config for ${ENVIRONMENT}/${REGION}"
    echo ""
    echo "Missing: ${missing_files[*]}"
    echo ""
    echo "Fix: 1) Add ${ENVIRONMENT}/${REGION} to argocd/config.yaml"
    echo "     2) Run ./argocd/scripts/render.py"
    echo "     3) Commit and push to your target branch"
    exit 1
fi

echo "✓ ArgoCD config exists for ${ENVIRONMENT}/${REGION}"