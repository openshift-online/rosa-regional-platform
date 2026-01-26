#!/bin/bash
# =============================================================================
# TargetGroupBinding Health Check Script (EKS Auto Mode)
#
# This script verifies that the TargetGroupBinding CR is correctly configured
# and that the API Gateway -> ALB -> Pod path is working with EKS Auto Mode.
#
# EKS Auto Mode uses native targetgroupbindings.eks.amazonaws.com/v1 CRDs,
# NOT the AWS Load Balancer Controller's elbv2.k8s.aws API.
#
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - kubectl configured to access the EKS Auto Mode cluster
#   - jq installed
#   - awscurl installed (for API Gateway testing)
#
# Usage:
#   ./scripts/check-targetgroupbinding.sh <target-group-arn> [namespace]
#
# Example:
#   ./scripts/check-targetgroupbinding.sh \
#     arn:aws:elasticloadbalancing:us-west-2:123456789:targetgroup/regional-x8k2-api/abc123 \
#     rosa-regional
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_check() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_fail() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "  $1"
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target-group-arn> [namespace]"
    echo ""
    echo "Arguments:"
    echo "  target-group-arn  ARN of the AWS Target Group (from Terraform output)"
    echo "  namespace         Kubernetes namespace (default: all namespaces)"
    echo ""
    echo "Get the target group ARN from Terraform:"
    echo "  cd terraform/config/regional-cluster"
    echo "  terraform output -raw target_group_arn"
    exit 1
fi

TARGET_GROUP_ARN="$1"
NAMESPACE="${2:-}"

# Extract region from ARN
REGION=$(echo "$TARGET_GROUP_ARN" | cut -d: -f4)
if [[ -z "$REGION" ]]; then
    echo "Error: Could not extract region from target group ARN"
    exit 1
fi

echo "Target Group ARN: $TARGET_GROUP_ARN"
echo "Region: $REGION"
echo "Namespace: ${NAMESPACE:-all}"

# -----------------------------------------------------------------------------
# Check 1: AWS Target Group exists and is healthy
# -----------------------------------------------------------------------------

print_header "1. AWS Target Group Status"

print_check "Fetching target group details..."
TG_INFO=$(aws elbv2 describe-target-groups \
    --target-group-arns "$TARGET_GROUP_ARN" \
    --region "$REGION" \
    --output json 2>/dev/null || echo '{"TargetGroups":[]}')

TG_COUNT=$(echo "$TG_INFO" | jq '.TargetGroups | length')
if [[ "$TG_COUNT" -eq 0 ]]; then
    print_fail "Target group not found: $TARGET_GROUP_ARN"
    exit 1
fi

TG_NAME=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].TargetGroupName')
TG_TYPE=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].TargetType')
TG_PORT=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].Port')
TG_PROTOCOL=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].Protocol')
TG_VPC=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].VpcId')

print_pass "Target group found: $TG_NAME"
print_info "Type: $TG_TYPE"
print_info "Port: $TG_PORT"
print_info "Protocol: $TG_PROTOCOL"
print_info "VPC: $TG_VPC"

if [[ "$TG_TYPE" != "ip" ]]; then
    print_fail "Target type is '$TG_TYPE' but must be 'ip' for TargetGroupBinding"
    echo ""
    echo "The target group must use 'ip' target type for TargetGroupBinding to work."
    echo "Check your Terraform configuration: target_type = \"ip\""
    exit 1
fi
print_pass "Target type is 'ip' (required for TargetGroupBinding)"

# -----------------------------------------------------------------------------
# Check 2: Registered targets in the target group
# -----------------------------------------------------------------------------

print_header "2. Registered Targets"

print_check "Fetching registered targets..."
TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --region "$REGION" \
    --output json)

TARGET_COUNT=$(echo "$TARGETS" | jq '.TargetHealthDescriptions | length')

if [[ "$TARGET_COUNT" -eq 0 ]]; then
    print_fail "No targets registered in the target group"
    echo ""
    echo "This means either:"
    echo "  1. TargetGroupBinding CR doesn't exist in Kubernetes"
    echo "  2. EKS Auto Mode is not properly configured or IAM permissions are missing"
    echo "  3. The service selector doesn't match any pods"
    echo "  4. Pods are not ready"
else
    print_pass "Found $TARGET_COUNT registered target(s)"
    echo ""
    echo "  IP ADDRESS        PORT    STATE           REASON"
    echo "  ────────────────  ──────  ──────────────  ──────────────────────"
    
    HEALTHY_COUNT=0
    UNHEALTHY_COUNT=0
    
    echo "$TARGETS" | jq -r '.TargetHealthDescriptions[] | 
        "  \(.Target.Id | . + " " * (16 - length))  \(.Target.Port)    \(.TargetHealth.State | . + " " * (14 - length))  \(.TargetHealth.Reason // "-")"'
    
    HEALTHY_COUNT=$(echo "$TARGETS" | jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length')
    UNHEALTHY_COUNT=$(echo "$TARGETS" | jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State != "healthy")] | length')
    
    echo ""
    if [[ "$HEALTHY_COUNT" -gt 0 ]]; then
        print_pass "$HEALTHY_COUNT healthy target(s)"
    fi
    if [[ "$UNHEALTHY_COUNT" -gt 0 ]]; then
        print_fail "$UNHEALTHY_COUNT unhealthy target(s)"
    fi
fi

# -----------------------------------------------------------------------------
# Check 3: TargetGroupBinding CR in Kubernetes
# -----------------------------------------------------------------------------

print_header "3. TargetGroupBinding Custom Resource"

print_check "Checking if TargetGroupBinding CRD exists..."
if ! kubectl get crd targetgroupbindings.eks.amazonaws.com &>/dev/null; then
    print_fail "TargetGroupBinding CRD not found (eks.amazonaws.com)"
    echo ""
    echo "EKS Auto Mode may not be enabled on this cluster."
    echo "Verify Auto Mode is enabled with:"
    echo "  aws eks describe-cluster --name <cluster-name> --query 'cluster.computeConfig.enabled'"
    echo ""
    echo "If you see 'targetgroupbindings.elbv2.k8s.aws', you're using AWS Load Balancer Controller"
    echo "instead of EKS Auto Mode. This script expects EKS Auto Mode."
else
    print_pass "TargetGroupBinding CRD exists (eks.amazonaws.com)"
fi

print_check "Searching for TargetGroupBinding referencing this target group..."

if [[ -n "$NAMESPACE" ]]; then
    TGB_JSON=$(kubectl get targetgroupbinding -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
else
    TGB_JSON=$(kubectl get targetgroupbinding -A -o json 2>/dev/null || echo '{"items":[]}')
fi

# Filter by target group ARN
MATCHING_TGB=$(echo "$TGB_JSON" | jq --arg arn "$TARGET_GROUP_ARN" '.items[] | select(.spec.targetGroupARN == $arn)')

if [[ -z "$MATCHING_TGB" ]]; then
    print_fail "No TargetGroupBinding found for this target group ARN"
    echo ""
    echo "Create a TargetGroupBinding CR for EKS Auto Mode like this:"
    echo ""
    echo "apiVersion: eks.amazonaws.com/v1"
    echo "kind: TargetGroupBinding"
    echo "metadata:"
    echo "  name: frontend-api"
    echo "  namespace: <your-namespace>"
    echo "spec:"
    echo "  serviceRef:"
    echo "    name: <your-service-name>"
    echo "    port: $TG_PORT"
    echo "  targetGroupARN: $TARGET_GROUP_ARN"
    echo "  targetType: ip"
else
    TGB_NAME=$(echo "$MATCHING_TGB" | jq -r '.metadata.name')
    TGB_NS=$(echo "$MATCHING_TGB" | jq -r '.metadata.namespace')
    TGB_SVC=$(echo "$MATCHING_TGB" | jq -r '.spec.serviceRef.name')
    TGB_SVC_PORT=$(echo "$MATCHING_TGB" | jq -r '.spec.serviceRef.port')
    TGB_TYPE=$(echo "$MATCHING_TGB" | jq -r '.spec.targetType // "ip"')
    
    print_pass "Found TargetGroupBinding: $TGB_NS/$TGB_NAME"
    print_info "Service: $TGB_SVC:$TGB_SVC_PORT"
    print_info "Target Type: $TGB_TYPE"
    
    # Check service exists
    print_check "Checking if referenced service exists..."
    if kubectl get svc "$TGB_SVC" -n "$TGB_NS" &>/dev/null; then
        print_pass "Service $TGB_SVC exists"
        
        # Get service details
        SVC_JSON=$(kubectl get svc "$TGB_SVC" -n "$TGB_NS" -o json)
        SVC_SELECTOR=$(echo "$SVC_JSON" | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')
        print_info "Selector: $SVC_SELECTOR"
        
        # Check endpoints
        print_check "Checking service endpoints..."
        ENDPOINTS=$(kubectl get endpoints "$TGB_SVC" -n "$TGB_NS" -o json 2>/dev/null || echo '{"subsets":[]}')
        EP_COUNT=$(echo "$ENDPOINTS" | jq '[.subsets[]?.addresses[]?] | length')
        
        if [[ "$EP_COUNT" -eq 0 ]]; then
            print_fail "Service has no endpoints (no matching pods or pods not ready)"
        else
            print_pass "Service has $EP_COUNT endpoint(s)"
            echo "$ENDPOINTS" | jq -r '.subsets[]?.addresses[]? | "    - \(.ip)"'
        fi
    else
        print_fail "Service $TGB_SVC not found in namespace $TGB_NS"
    fi
fi

# -----------------------------------------------------------------------------
# Check 4: EKS Auto Mode and IAM Configuration
# -----------------------------------------------------------------------------

print_header "4. EKS Auto Mode and IAM Permissions"

# Get cluster name from kubectl context
CLUSTER_NAME=$(kubectl config current-context | sed 's/.*\///' 2>/dev/null || echo "")

if [[ -z "$CLUSTER_NAME" ]]; then
    print_fail "Could not determine cluster name from kubectl context"
    echo ""
    echo "Skipping Auto Mode and IAM checks."
else
    print_check "Checking if EKS Auto Mode is enabled..."
    AUTO_MODE_ENABLED=$(aws eks describe-cluster \
        --name "$CLUSTER_NAME" \
        --region "$REGION" \
        --query 'cluster.computeConfig.enabled' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [[ "$AUTO_MODE_ENABLED" == "True" ]] || [[ "$AUTO_MODE_ENABLED" == "true" ]]; then
        print_pass "EKS Auto Mode is enabled"

        # Check cluster IAM role for AmazonEKSLoadBalancingPolicy
        print_check "Checking cluster IAM role for AmazonEKSLoadBalancingPolicy..."
        CLUSTER_ROLE_ARN=$(aws eks describe-cluster \
            --name "$CLUSTER_NAME" \
            --region "$REGION" \
            --query 'cluster.roleArn' \
            --output text 2>/dev/null || echo "")

        if [[ -n "$CLUSTER_ROLE_ARN" ]]; then
            ROLE_NAME=$(echo "$CLUSTER_ROLE_ARN" | awk -F'/' '{print $NF}')
            print_info "Cluster IAM Role: $ROLE_NAME"

            # Check attached policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
                --role-name "$ROLE_NAME" \
                --query 'AttachedPolicies[].PolicyName' \
                --output json 2>/dev/null || echo '[]')

            if echo "$ATTACHED_POLICIES" | jq -e '.[] | select(. == "AmazonEKSLoadBalancingPolicy")' &>/dev/null; then
                print_pass "AmazonEKSLoadBalancingPolicy is attached to cluster role"
            else
                print_fail "AmazonEKSLoadBalancingPolicy is NOT attached to cluster role"
                echo ""
                echo "Required for TargetGroupBinding to register pod IPs with target groups."
                echo "Attach the policy with:"
                echo "  aws iam attach-role-policy \\"
                echo "    --role-name $ROLE_NAME \\"
                echo "    --policy-arn arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
            fi

            # Show all Auto Mode policies
            print_check "Verifying all Auto Mode IAM policies..."
            REQUIRED_POLICIES=("AmazonEKSClusterPolicy" "AmazonEKSComputePolicy" "AmazonEKSBlockStoragePolicy" "AmazonEKSLoadBalancingPolicy" "AmazonEKSNetworkingPolicy")
            MISSING_POLICIES=()

            for policy in "${REQUIRED_POLICIES[@]}"; do
                if echo "$ATTACHED_POLICIES" | jq -e --arg p "$policy" '.[] | select(. == $p)' &>/dev/null; then
                    print_info "✓ $policy"
                else
                    print_info "✗ $policy (MISSING)"
                    MISSING_POLICIES+=("$policy")
                fi
            done

            if [[ ${#MISSING_POLICIES[@]} -eq 0 ]]; then
                print_pass "All required Auto Mode policies are attached"
            else
                print_fail "${#MISSING_POLICIES[@]} required policy(ies) missing"
            fi
        else
            print_fail "Could not retrieve cluster IAM role ARN"
        fi
    else
        print_fail "EKS Auto Mode is NOT enabled (status: $AUTO_MODE_ENABLED)"
        echo ""
        echo "This cluster may be using AWS Load Balancer Controller instead."
        echo "This script is designed for EKS Auto Mode clusters."
        echo ""
        echo "To enable Auto Mode, see:"
        echo "https://docs.aws.amazon.com/eks/latest/userguide/automode.html"
    fi
fi

# -----------------------------------------------------------------------------
# Check 5: ALB health (if we can find it)
# -----------------------------------------------------------------------------

print_header "5. Application Load Balancer"

print_check "Finding ALB for this target group..."
TG_LB_ARNS=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].LoadBalancerArns[]?' 2>/dev/null || echo "")

if [[ -z "$TG_LB_ARNS" ]]; then
    print_fail "Target group is not attached to any load balancer"
    echo ""
    echo "This is expected if Terraform hasn't created the ALB listener yet."
else
    for LB_ARN in $TG_LB_ARNS; do
        LB_INFO=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$LB_ARN" \
            --region "$REGION" \
            --output json 2>/dev/null || echo '{"LoadBalancers":[]}')
        
        LB_NAME=$(echo "$LB_INFO" | jq -r '.LoadBalancers[0].LoadBalancerName')
        LB_STATE=$(echo "$LB_INFO" | jq -r '.LoadBalancers[0].State.Code')
        LB_DNS=$(echo "$LB_INFO" | jq -r '.LoadBalancers[0].DNSName')
        LB_SCHEME=$(echo "$LB_INFO" | jq -r '.LoadBalancers[0].Scheme')
        
        if [[ "$LB_STATE" == "active" ]]; then
            print_pass "ALB is active: $LB_NAME"
        else
            print_fail "ALB state: $LB_STATE"
        fi
        print_info "DNS: $LB_DNS"
        print_info "Scheme: $LB_SCHEME"
    done
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

print_header "Summary"

echo ""
if [[ "$TARGET_COUNT" -gt 0 ]] && [[ "$HEALTHY_COUNT" -gt 0 ]]; then
    print_pass "TargetGroupBinding appears to be working correctly!"
    echo ""
    echo "Next steps:"
    echo "  1. Test the API Gateway endpoint using awscurl:"
    echo "     awscurl --service execute-api --region $REGION \\"
    echo "       https://<api-id>.execute-api.$REGION.amazonaws.com/prod/v0/live"
    echo ""
    echo "  2. Get the invoke URL from Terraform:"
    echo "     cd terraform/config/regional-cluster && terraform output invoke_url"
else
    print_fail "TargetGroupBinding may not be working correctly"
    echo ""
    echo "Troubleshooting checklist for EKS Auto Mode:"
    echo "  [ ] EKS Auto Mode is enabled on the cluster"
    echo "  [ ] Cluster IAM role has AmazonEKSLoadBalancingPolicy attached"
    echo "  [ ] TargetGroupBinding CR exists with correct targetGroupARN"
    echo "  [ ] TargetGroupBinding uses eks.amazonaws.com/v1 API (not elbv2.k8s.aws)"
    echo "  [ ] Target group uses 'ip' target type"
    echo "  [ ] Service exists and has the correct selector"
    echo "  [ ] Pods are running and passing readiness probes"
    echo "  [ ] Pod security groups allow traffic from ALB security group"
    echo "  [ ] Health check path (/v0/live) returns HTTP 200"
fi

echo ""
