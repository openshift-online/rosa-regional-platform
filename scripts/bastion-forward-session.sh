#!/bin/bash
# Port forwarding session to bastion ECS task
# Usage: ./bastion-forward-session.sh [portNumber] [localPortNumber]
#   portNumber:      Remote port to forward (default: 8443)
#   localPortNumber: Local port to bind (default: 8443)

PORT_NUMBER="${1:-8443}"
LOCAL_PORT_NUMBER="${2:-8443}"

# Load task info
CLUSTER=$(jq -r '.cluster' bastion_task.json)
TASK_ID=$(jq -r '.task_id' bastion_task.json)
RUNTIME_ID=$(jq -r '.runtime_id' bastion_task.json)

echo "🔗 Starting port forwarding session..."
echo "   Remote port: ${PORT_NUMBER} → Local port: ${LOCAL_PORT_NUMBER}"
echo ""

aws ssm start-session \
  --target "ecs:${CLUSTER}_${TASK_ID}_${RUNTIME_ID}" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"${PORT_NUMBER}\"],\"localPortNumber\":[\"${LOCAL_PORT_NUMBER}\"]}"
