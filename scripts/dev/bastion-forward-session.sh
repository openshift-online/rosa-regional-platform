#!/bin/bash
# Port forwarding session to bastion ECS task
# Usage: ./bastion-forward-session.sh [regional|management] [portNumber] [localPortNumber]
#   cluster_type:    Cluster type - regional or management (default: regional)
#   portNumber:      Remote port to forward (default: 8443)
#   localPortNumber: Local port to bind (default: 8443)

set -euo pipefail

# Parse arguments - detect if first arg is cluster type or port number
if [[ "${1:-}" =~ ^(regional|management)$ ]]; then
  CLUSTER_TYPE="$1"
  PORT_NUMBER="${2:-8443}"
  LOCAL_PORT_NUMBER="${3:-8443}"
else
  CLUSTER_TYPE="regional"
  PORT_NUMBER="${1:-8443}"
  LOCAL_PORT_NUMBER="${2:-8443}"
fi

TASK_FILE="bastion_task_${CLUSTER_TYPE}.json"

# Check if task file exists
if [ ! -f "$TASK_FILE" ]; then
  echo "Error: Task file '$TASK_FILE' not found"
  echo "Please run bastion-start-task.sh $CLUSTER_TYPE first to start a bastion task"
  exit 1
fi

# Load task info
CLUSTER=$(jq -r '.cluster' $TASK_FILE)
TASK_ID=$(jq -r '.task_id' $TASK_FILE)
RUNTIME_ID=$(jq -r '.runtime_id' $TASK_FILE)

echo "🔗 Starting port forwarding session to $CLUSTER_TYPE cluster bastion..."
echo "   Remote port: ${PORT_NUMBER} → Local port: ${LOCAL_PORT_NUMBER}"
echo ""

aws ssm start-session \
  --target "ecs:${CLUSTER}_${TASK_ID}_${RUNTIME_ID}" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"${PORT_NUMBER}\"],\"localPortNumber\":[\"${LOCAL_PORT_NUMBER}\"]}"
