#!/usr/bin/env bash
# Imprime la URL publica del portal React (IP publica de la tarea Fargate del frontend).
# La IP cambia cada vez que la tarea se reinicia: vuelve a ejecutar este script.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/infra-terraform"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="$(terraform -chdir="$TF_DIR" output -raw ecs_cluster)"
SERVICE="$(terraform -chdir="$TF_DIR" output -raw ecs_frontend_service)"

TASK="$(aws ecs list-tasks --region "$REGION" --cluster "$CLUSTER" --service-name "$SERVICE" \
  --desired-status RUNNING --query 'taskArns[0]' --output text)"
[ "$TASK" != "None" ] || { echo "No hay tareas RUNNING del frontend todavia"; exit 1; }

ENI="$(aws ecs describe-tasks --region "$REGION" --cluster "$CLUSTER" --tasks "$TASK" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)"
IP="$(aws ec2 describe-network-interfaces --region "$REGION" --network-interface-ids "$ENI" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)"

echo "Portal MiniStore Express: http://$IP"
