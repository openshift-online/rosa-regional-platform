#!/bin/bash

CURRENT_DIR=$(pwd)

# Get terraform outputs
cd terraform/config/regional-cluster  # or management-cluster

# Start the bastion task
eval "$(terraform output -raw bastion_run_task_command)"

# Get the task ID from the output, or list running tasks:
CLUSTER=$(terraform output -raw bastion_ecs_cluster_name)
TASK_ID=$(aws ecs list-tasks --cluster $CLUSTER --query 'taskArns[0]' --output text | awk -F'/' '{print $NF}')

# Wait for task to be running (tool installation takes ~60 seconds)
aws ecs wait tasks-running --cluster $CLUSTER --tasks $TASK_ID

# Get the runtimeId for port forwarding (save for later)
RUNTIME_ID=$(aws ecs describe-tasks \
  --cluster $CLUSTER \
  --tasks $TASK_ID \
  --query 'tasks[0].containers[?name==`bastion`].runtimeId | [0]' \
  --output text)

# Save task info for later use
echo "{\"cluster\":\"$CLUSTER\",\"task_id\":\"$TASK_ID\",\"runtime_id\":\"$RUNTIME_ID\"}" > $CURRENT_DIR/bastion_task.json

cd $CURRENT_DIR
