#!/usr/bin/env bash
# Despliegue completo en AWS Academy Learner Lab (ejecutar en Git Bash / Linux / macOS).
#
# Requisitos: aws cli v2, terraform >= 1.6, docker en ejecucion,
#             credenciales del Learner Lab (AWS Details -> AWS CLI) en ~/.aws/credentials
#             e infra-terraform/terraform.tfvars creado a partir de terraform.tfvars.example.
#
# Fases:
#   1) Terraform crea solo los repositorios ECR
#   2) Docker construye y sube las imagenes ministore-java y ministore-react-nginx
#   3) Terraform crea el resto (VPCs, Bastion, EC2 legacy, RDS, Lambda, ALB, API GW, ECS)
#   4) Se fuerza un nuevo despliegue de ECS para que tome las imagenes recien subidas
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/infra-terraform"
REGION="${AWS_REGION:-us-east-1}"
TAG="${IMAGE_TAG:-latest}"

aws sts get-caller-identity >/dev/null || { echo "Credenciales AWS invalidas o expiradas (reinicia el Learner Lab)"; exit 1; }
[ -f "$TF_DIR/terraform.tfvars" ] || { echo "Falta $TF_DIR/terraform.tfvars (copia terraform.tfvars.example)"; exit 1; }

echo "==> [1/4] Terraform: repositorios ECR"
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false -auto-approve \
  -target=aws_ecr_repository.java -target=aws_ecr_repository.frontend

JAVA_REPO="$(terraform -chdir="$TF_DIR" output -raw ecr_java_url)"
FRONT_REPO="$(terraform -chdir="$TF_DIR" output -raw ecr_frontend_url)"
REGISTRY="${JAVA_REPO%%/*}"

# docker push a ECR puede fallar con "net/http: timeout awaiting response headers" cuando
# la conexion es lenta o inestable. ECR conserva las capas ya subidas, asi que cada
# reintento solo sube lo que falto.
push_with_retry() {
  local image="$1" attempt
  for attempt in 1 2 3 4 5; do
    if docker push "$image"; then
      return 0
    fi
    echo "!! push de $image fallo (intento $attempt/5). Reintentando en $((attempt * 10)) s..."
    sleep $((attempt * 10))
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
  done
  echo "No se pudo subir $image tras 5 intentos. Revisa tu conexion (ver README: max-concurrent-uploads)."
  return 1
}

echo "==> [2/4] Docker: build & push a $REGISTRY"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker build --platform linux/amd64 -t "$JAVA_REPO:$TAG" "$ROOT/backend-java"
push_with_retry "$JAVA_REPO:$TAG"
docker build --platform linux/amd64 -t "$FRONT_REPO:$TAG" "$ROOT/frontend-react"
push_with_retry "$FRONT_REPO:$TAG"

echo "==> [3/4] Terraform: infraestructura completa (RDS tarda ~5-10 min)"
terraform -chdir="$TF_DIR" apply -input=false -auto-approve \
  -var="java_image_tag=$TAG" -var="frontend_image_tag=$TAG"

echo "==> [4/4] ECS: nuevo despliegue con las imagenes actuales"
CLUSTER="$(terraform -chdir="$TF_DIR" output -raw ecs_cluster)"
for SVC in "$(terraform -chdir="$TF_DIR" output -raw ecs_java_service)" "$(terraform -chdir="$TF_DIR" output -raw ecs_frontend_service)"; do
  aws ecs update-service --region "$REGION" --cluster "$CLUSTER" --service "$SVC" --force-new-deployment >/dev/null
done
echo "Esperando a que los servicios ECS esten estables..."
aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" \
  --services "$(terraform -chdir="$TF_DIR" output -raw ecs_java_service)" "$(terraform -chdir="$TF_DIR" output -raw ecs_frontend_service)"

echo
terraform -chdir="$TF_DIR" output
echo
"$ROOT/scripts/frontend-url.sh"
