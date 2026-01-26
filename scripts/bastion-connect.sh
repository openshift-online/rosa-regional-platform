# Load task info
CLUSTER=$(jq -r '.cluster' bastion_task.json)
TASK_ID=$(jq -r '.task_id' bastion_task.json)

# Connect via ECS Exec
aws ecs execute-command \
  --cluster $CLUSTER \
  --task $TASK_ID \
  --container bastion \
  --interactive \
  --command '/bin/bash'
