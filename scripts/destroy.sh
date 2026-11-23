#!/usr/bin/env bash
# Elimina toda la infraestructura (hazlo al terminar la demo para no gastar creditos).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
terraform -chdir="$ROOT/infra-terraform" destroy -input=false -auto-approve
