#!/bin/bash

set -euo pipefail

# Usage information
usage() {
  echo "Usage: $0 [regional|management]"
  echo ""
  echo "Start (if needed) and connect to a bastion ECS task"
  echo ""
  echo "Arguments:"
  echo "  regional    - Use regional cluster bastion (default)"
  echo "  management  - Use management cluster bastion"
  exit 1
}

# Default to regional if no argument provided
CLUSTER_TYPE=${1:-regional}

# Validate cluster type
case $CLUSTER_TYPE in
  regional|management)
    CONFIG_DIR="terraform/config/${CLUSTER_TYPE}-cluster"
    TASK_FILE="bastion_task_${CLUSTER_TYPE}.json"
    ;;
  *)
    echo "Error: Invalid cluster type '$CLUSTER_TYPE'"
    echo ""
    usage
    ;;
esac

CURRENT_DIR=$(pwd)

# Verify terraform config directory exists
if [ ! -d "$CONFIG_DIR" ]; then
  echo "Error: Terraform config directory '$CONFIG_DIR' not found"
  exit 1
fi

echo "==> Starting/verifying bastion task for $CLUSTER_TYPE cluster..."

# Get terraform outputs
cd $CONFIG_DIR

# Start the bastion task (idempotent - will reuse existing task if already running)
eval "$(terraform output -raw bastion_run_task_command)"

# Get the task ID from the output, or list running tasks:
CLUSTER=$(terraform output -raw bastion_ecs_cluster_name)
TASK_ID=$(aws ecs list-tasks --cluster $CLUSTER --query 'taskArns[0]' --output text | awk -F'/' '{print $NF}')

# Wait for task to be running (tool installation takes ~60 seconds)
echo "==> Waiting for task to be running..."
aws ecs wait tasks-running --cluster $CLUSTER --tasks $TASK_ID

# Get the runtimeId for port forwarding (save for later)
RUNTIME_ID=$(aws ecs describe-tasks \
  --cluster $CLUSTER \
  --tasks $TASK_ID \
  --query 'tasks[0].containers[?name==`bastion`].runtimeId | [0]' \
  --output text)

if [[ -z "$RUNTIME_ID" || "$RUNTIME_ID" == "None" ]]; then
  echo "Error: runtime_id not found for task '$TASK_ID' in cluster '$CLUSTER'"
  exit 1
fi

# Save task info for later use
echo "{\"cluster_type\":\"$CLUSTER_TYPE\",\"cluster\":\"$CLUSTER\",\"task_id\":\"$TASK_ID\",\"runtime_id\":\"$RUNTIME_ID\"}" > $CURRENT_DIR/$TASK_FILE

cd $CURRENT_DIR

# Wait for tools to install in the container
echo ""
echo "==> Waiting for container tools to install (60 seconds)..."
WAIT_SECONDS=60
for i in $(seq $WAIT_SECONDS -1 1); do
  printf "\r    [%-60s] %2ds remaining" $(printf '#%.0s' $(seq 1 $((60 - i + 1)))) $i
  sleep 1
done
printf "\r    [%-60s] Complete!   \n" $(printf '#%.0s' $(seq 1 60))

echo ""
echo "==> Bastion task ready for $CLUSTER_TYPE cluster"
echo "    Cluster: $CLUSTER"
echo "    Task ID: $TASK_ID"
echo "    Runtime ID: $RUNTIME_ID"
echo ""
echo "==> Connecting to bastion..."
echo ""

# Connect via ECS Exec
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_ID \
  --container bastion \
  --interactive \
  --command '/bin/bash'
