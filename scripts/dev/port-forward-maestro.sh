#!/bin/bash
set -euo pipefail

# Script to port-forward both maestro HTTP (8080) and gRPC (8090) ports via SSM

# Parse bastion_task.json
BASTION_TASK_FILE="bastion_task.json"

if [ ! -f "$BASTION_TASK_FILE" ]; then
  echo "Error: $BASTION_TASK_FILE not found"
  exit 1
fi

CLUSTER=$(jq -r '.cluster' "$BASTION_TASK_FILE")
TASK_ID=$(jq -r '.task_id' "$BASTION_TASK_FILE")
RUNTIME_ID=$(jq -r '.runtime_id' "$BASTION_TASK_FILE")

TARGET="ecs:${CLUSTER}_${TASK_ID}_${RUNTIME_ID}"

echo "Starting port forwarding to bastion task..."
echo "  Cluster:    $CLUSTER"
echo "  Task ID:    $TASK_ID"
echo "  Runtime ID: $RUNTIME_ID"
echo ""

# Start port forwarding for HTTP (8080) in background
echo "Starting port forward for HTTP API (8080)..."
aws ssm start-session \
  --target "$TARGET" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' &

HTTP_PID=$!

# Start port forwarding for gRPC (8090) in background
echo "Starting port forward for gRPC API (8090)..."
aws ssm start-session \
  --target "$TARGET" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8090"],"localPortNumber":["8090"]}' &

GRPC_PID=$!

echo ""
echo "Port forwarding started!"
echo "  HTTP API (8080): PID $HTTP_PID"
echo "  gRPC API (8090): PID $GRPC_PID"
echo ""
echo "Press Ctrl+C to stop both sessions..."

# Wait for both background processes
wait $HTTP_PID $GRPC_PID
