#!/bin/bash
# =============================================================================
# API Gateway Full Stack Verification Script
#
# This script verifies the entire API Gateway → ALB → Pod flow is working.
# Run this after deploying the infrastructure to verify everything is set up.
#
# Prerequisites:
#   - AWS CLI configured
#   - Terraform state available (run from terraform/config/regional-cluster)
#   - awscurl installed (for API Gateway testing)
#
# Usage:
#   cd terraform/config/regional-cluster
#   ../../../scripts/check-api-gateway.sh
#
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Track overall status
OVERALL_STATUS=0

# =============================================================================
# Get Terraform Outputs
# =============================================================================
TOP=$(pwd)
cd $TOP/terraform/config/regional-cluster

print_header "1. Reading Terraform Outputs"

if [[ ! -f "terraform.tfstate" ]] && [[ ! -d ".terraform" ]]; then
    print_fail "Not in a Terraform directory. Run from terraform/config/regional-cluster"
    exit 1
fi

print_check "Getting Terraform outputs..."

CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
CLUSTER_ARN=$(terraform output -raw cluster_arn 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
TARGET_GROUP_ARN=$(terraform output -raw api_target_group_arn 2>/dev/null || echo "")
ALB_SG=$(terraform output -raw api_alb_security_group_id 2>/dev/null || echo "")
NODE_SG=$(terraform output -raw node_security_group_id 2>/dev/null || echo "")
INVOKE_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null || echo "")
API_ID=$(terraform output -raw api_gateway_id 2>/dev/null || echo "")

# Extract region from cluster ARN
REGION=$(echo "$CLUSTER_ARN" | cut -d: -f4)

if [[ -z "$CLUSTER_NAME" ]] || [[ -z "$TARGET_GROUP_ARN" ]]; then
    print_fail "Could not read Terraform outputs. Run 'terraform apply' first."
    exit 1
fi

print_pass "Cluster: $CLUSTER_NAME"
print_pass "Region: $REGION"
print_pass "VPC: $VPC_ID"
print_pass "Target Group: $TARGET_GROUP_ARN"
print_pass "ALB Security Group: $ALB_SG"
print_pass "Node Security Group: $NODE_SG"
print_pass "Invoke URL: $INVOKE_URL"

# =============================================================================
# Check API Gateway
# =============================================================================

print_header "2. API Gateway"

print_check "Checking API Gateway exists..."
API_INFO=$(aws apigateway get-rest-api --rest-api-id "$API_ID" --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$API_INFO" ]]; then
    API_NAME=$(echo "$API_INFO" | jq -r '.name')
    print_pass "API Gateway exists: $API_NAME"
else
    print_fail "API Gateway not found: $API_ID"
    OVERALL_STATUS=1
fi

# =============================================================================
# Check VPC Link
# =============================================================================

print_header "3. VPC Link"

print_check "Checking VPC Link..."
VPC_LINKS=$(aws apigatewayv2 get-vpc-links --region "$REGION" 2>/dev/null || echo '{"Items":[]}')
VPC_LINK_COUNT=$(echo "$VPC_LINKS" | jq '[.Items[] | select(.Name | contains("'$CLUSTER_NAME'") or contains("api"))] | length')

if [[ "$VPC_LINK_COUNT" -gt 0 ]]; then
    print_pass "VPC Link found"
    echo "$VPC_LINKS" | jq -r '.Items[] | select(.Name | contains("'$CLUSTER_NAME'") or contains("api")) | "    - \(.Name): \(.VpcLinkStatus)"'
else
    print_fail "No VPC Link found"
    OVERALL_STATUS=1
fi

# =============================================================================
# Check ALB
# =============================================================================

print_header "4. Application Load Balancer"

print_check "Checking ALB..."
# Extract ALB ARN from target group
TG_INFO=$(aws elbv2 describe-target-groups --target-group-arns "$TARGET_GROUP_ARN" --region "$REGION" 2>/dev/null || echo '{"TargetGroups":[]}')
ALB_ARNS=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].LoadBalancerArns[]?' 2>/dev/null || echo "")

if [[ -n "$ALB_ARNS" ]]; then
    for ALB_ARN in $ALB_ARNS; do
        ALB_INFO=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" 2>/dev/null)
        ALB_NAME=$(echo "$ALB_INFO" | jq -r '.LoadBalancers[0].LoadBalancerName')
        ALB_STATE=$(echo "$ALB_INFO" | jq -r '.LoadBalancers[0].State.Code')
        ALB_SCHEME=$(echo "$ALB_INFO" | jq -r '.LoadBalancers[0].Scheme')
        
        if [[ "$ALB_STATE" == "active" ]]; then
            print_pass "ALB active: $ALB_NAME ($ALB_SCHEME)"
        else
            print_fail "ALB not active: $ALB_NAME (state: $ALB_STATE)"
            OVERALL_STATUS=1
        fi
    done
else
    print_fail "ALB not attached to target group"
    OVERALL_STATUS=1
fi

# =============================================================================
# Check Target Group
# =============================================================================

print_header "5. Target Group"

print_check "Checking target group configuration..."
TG_TYPE=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].TargetType')
TG_PORT=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].Port')
TG_HEALTH_PATH=$(echo "$TG_INFO" | jq -r '.TargetGroups[0].HealthCheckPath')

print_info "Target Type: $TG_TYPE"
print_info "Port: $TG_PORT"
print_info "Health Check Path: $TG_HEALTH_PATH"

if [[ "$TG_TYPE" == "ip" ]]; then
    print_pass "Target type is 'ip' (required for TargetGroupBinding)"
else
    print_fail "Target type is '$TG_TYPE' - must be 'ip' for TargetGroupBinding"
    OVERALL_STATUS=1
fi

# =============================================================================
# Check Target Health
# =============================================================================

print_header "6. Target Health"

print_check "Checking registered targets..."
TARGETS=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GROUP_ARN" --region "$REGION" 2>/dev/null)
TARGET_COUNT=$(echo "$TARGETS" | jq '.TargetHealthDescriptions | length')

if [[ "$TARGET_COUNT" -eq 0 ]]; then
    print_fail "No targets registered"
    print_info "This could mean:"
    print_info "  - TargetGroupBinding doesn't exist in Kubernetes"
    print_info "  - AWS Load Balancer Controller is not running"
    print_info "  - No pods match the service selector"
    OVERALL_STATUS=1
else
    print_pass "Found $TARGET_COUNT target(s)"
    echo ""
    echo "  IP ADDRESS        PORT    STATE           REASON"
    echo "  ────────────────  ──────  ──────────────  ────────────────────"
    
    HEALTHY=0
    UNHEALTHY=0
    
    while IFS= read -r line; do
        IP=$(echo "$line" | jq -r '.Target.Id')
        PORT=$(echo "$line" | jq -r '.Target.Port')
        STATE=$(echo "$line" | jq -r '.TargetHealth.State')
        REASON=$(echo "$line" | jq -r '.TargetHealth.Reason // "-"')
        
        printf "  %-16s  %-6s  %-14s  %s\n" "$IP" "$PORT" "$STATE" "$REASON"
        
        if [[ "$STATE" == "healthy" ]]; then
            ((HEALTHY++))
        else
            ((UNHEALTHY++))
        fi
    done < <(echo "$TARGETS" | jq -c '.TargetHealthDescriptions[]')
    
    echo ""
    if [[ "$HEALTHY" -gt 0 ]]; then
        print_pass "$HEALTHY healthy target(s)"
    fi
    if [[ "$UNHEALTHY" -gt 0 ]]; then
        print_fail "$UNHEALTHY unhealthy target(s)"
        OVERALL_STATUS=1
    fi
fi

# =============================================================================
# Check Security Groups
# =============================================================================

print_header "7. Security Groups"

print_check "Checking ALB → Node security group rules..."

# Check if node SG has ingress from ALB SG
NODE_SG_RULES=$(aws ec2 describe-security-group-rules \
    --filter "Name=group-id,Values=$NODE_SG" \
    --region "$REGION" 2>/dev/null || echo '{"SecurityGroupRules":[]}')

ALB_TO_NODE_RULE=$(echo "$NODE_SG_RULES" | jq --arg alb "$ALB_SG" --arg port "$TG_PORT" \
    '[.SecurityGroupRules[] | select(.IsEgress == false and .ReferencedGroupInfo.GroupId == $alb and .FromPort == ($port | tonumber))] | length')

if [[ "$ALB_TO_NODE_RULE" -gt 0 ]]; then
    print_pass "Node SG has ingress rule from ALB SG on port $TG_PORT"
else
    print_fail "Missing ingress rule: Node SG ($NODE_SG) needs ingress from ALB SG ($ALB_SG) on port $TG_PORT"
    OVERALL_STATUS=1
fi

# =============================================================================
# Check AWS Load Balancer Controller Pod Identity
# =============================================================================

print_header "8. AWS Load Balancer Controller Pod Identity"

print_check "Checking Pod Identity association..."
LBC_ASSOC=$(aws eks list-pod-identity-associations \
    --cluster-name "$CLUSTER_NAME" \
    --namespace "kube-system" \
    --service-account "aws-load-balancer-controller" \
    --region "$REGION" 2>/dev/null || echo '{"associations":[]}')

ASSOC_COUNT=$(echo "$LBC_ASSOC" | jq '.associations | length')

if [[ "$ASSOC_COUNT" -gt 0 ]]; then
    # list-pod-identity-associations doesn't return roleArn, need to describe
    ASSOC_ID=$(echo "$LBC_ASSOC" | jq -r '.associations[0].associationId')
    ASSOC_DETAILS=$(aws eks describe-pod-identity-association \
        --cluster-name "$CLUSTER_NAME" \
        --association-id "$ASSOC_ID" \
        --region "$REGION" 2>/dev/null || echo '{"association":{}}')
    ASSOC_ROLE=$(echo "$ASSOC_DETAILS" | jq -r '.association.roleArn')
    
    if [[ "$ASSOC_ROLE" != "null" ]] && [[ -n "$ASSOC_ROLE" ]]; then
        print_pass "Pod Identity association exists"
        print_info "Role: $ASSOC_ROLE"
    else
        print_fail "Pod Identity association has NULL role ARN"
        print_info "Run: ./scripts/install-aws-load-balancer-controller.sh --fix --from-terraform"
        OVERALL_STATUS=1
    fi
else
    print_fail "No Pod Identity association for AWS Load Balancer Controller"
    print_info "Run: ./scripts/install-aws-load-balancer-controller.sh --from-terraform"
    OVERALL_STATUS=1
fi

# =============================================================================
# Test API Gateway Endpoint
# =============================================================================

print_header "9. API Gateway Endpoint Test"

if command -v awscurl &>/dev/null; then
    print_check "Testing API Gateway endpoint..."
    
    HEALTH_URL="${INVOKE_URL}/v0/live"
    print_info "URL: $HEALTH_URL"
    
    RESPONSE=$(awscurl --service execute-api --region "$REGION" "$HEALTH_URL" 2>/dev/null || echo "FAILED")
    
    if echo "$RESPONSE" | grep -q '"status"'; then
        print_pass "API Gateway response: $RESPONSE"
    elif echo "$RESPONSE" | grep -q "Forbidden"; then
        print_fail "API Gateway returned Forbidden"
        print_info "Your IAM user/role needs execute-api:Invoke permission"
        OVERALL_STATUS=1
    else
        print_fail "API Gateway test failed: $RESPONSE"
        OVERALL_STATUS=1
    fi
else
    print_info "awscurl not installed - skipping API Gateway test"
    print_info "Install with: pip install awscurl"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Summary"

if [[ "$OVERALL_STATUS" -eq 0 ]]; then
    print_pass "All checks passed! API Gateway is fully operational."
    echo ""
    echo "Test the API with:"
    echo "  awscurl --service execute-api --region $REGION \\"
    echo "    $INVOKE_URL/v0/live"
else
    print_fail "Some checks failed. Review the errors above."
    echo ""
    echo "Common fixes:"
    echo "  1. Security group rules: terraform apply"
    echo "  2. Pod Identity issues: ./scripts/install-aws-load-balancer-controller.sh --fix --from-terraform"
    echo "  3. No targets: Check TargetGroupBinding and AWS LBC in cluster"
    echo "  4. Unhealthy targets: Check pod health and security groups"
fi

echo ""

cd $TOP

exit $OVERALL_STATUS

