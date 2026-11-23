#!/usr/bin/env bash
# Genera ~/.ssh/ministore_config con los hosts del Bastion y del Legacy (ProxyJump)
# usando los outputs de Terraform. No modifica tu ~/.ssh/config.
#
# Uso:  ./scripts/bastion-ssh.sh [ruta/a/labsuser.pem]
#       (por defecto ~/.ssh/labsuser.pem)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/infra-terraform"
KEY="${1:-$HOME/.ssh/labsuser.pem}"
CONF="$HOME/.ssh/ministore_config"

[ -f "$KEY" ] || { echo "No encuentro la llave $KEY. Descargala del Learner Lab (AWS Details -> Download PEM)."; exit 1; }
chmod 400 "$KEY"
# En Windows usa C:/Users/... para que funcione tanto en Git Bash como en PowerShell
if command -v cygpath >/dev/null 2>&1; then
  KEY="$(cygpath -m "$KEY")"
fi

BASTION_IP="$(terraform -chdir="$TF_DIR" output -raw bastion_public_ip)"
LEGACY_IP="$(terraform -chdir="$TF_DIR" output -raw legacy_private_ip)"
RDS="$(terraform -chdir="$TF_DIR" output -raw rds_endpoint)"

cat > "$CONF" <<EOF
# Generado por scripts/bastion-ssh.sh - MiniStore Express
Host ministore-bastion
  HostName $BASTION_IP
  User ec2-user
  IdentityFile $KEY
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new

# Salta por el Bastion (VPC-Hub) hacia la EC2 privada (VPC-Spoke-Legacy)
Host ministore-legacy
  HostName $LEGACY_IP
  User ec2-user
  IdentityFile $KEY
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ProxyJump ministore-bastion

# Tunel: localhost:3307 -> RDS (VPC-Spoke-App) a traves del Bastion
Host ministore-rds-tunnel
  HostName $BASTION_IP
  User ec2-user
  IdentityFile $KEY
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  LocalForward 3307 $RDS:3306
EOF

echo "Config escrita en $CONF"
echo
echo "  ssh -F $CONF ministore-bastion        # entrar al Bastion"
echo "  ssh -F $CONF ministore-legacy         # saltar a la EC2 legacy ($LEGACY_IP)"
echo "  ssh -F $CONF -N ministore-rds-tunnel  # tunel MySQL en localhost:3307"
