#!/usr/bin/env bash
#
# deploy.sh — Provision AWS infrastructure with Terraform, then configure
# the Minecraft server with Ansible. Run from the repo root.
#
# Usage: ./deploy.sh
#
# Prerequisites (see README.md for full details):
#   - AWS credentials exported or in ~/.aws/credentials (including session
#     token if using Learner Lab)
#   - Terraform >= 1.5
#   - Ansible >= 2.14
#   - nmap (for the final verification step)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "==> Stage 1: Terraform init"
terraform -chdir=terraform init -upgrade

echo "==> Stage 2: Terraform apply"
terraform -chdir=terraform apply -auto-approve

PUBLIC_IP="$(terraform -chdir=terraform output -raw instance_public_ip)"
echo "==> EC2 instance is up at ${PUBLIC_IP}"

echo "==> Stage 3: Waiting for SSH to come up on ${PUBLIC_IP}:22"
# Poll port 22 instead of guessing with sleep. EC2 instances typically take
# 30-60 seconds before SSH is reachable.
for i in {1..60}; do
  if nc -z -w 5 "$PUBLIC_IP" 22 2>/dev/null; then
    echo "    SSH is reachable."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "    ERROR: SSH never came up after 5 minutes." >&2
    exit 1
  fi
  sleep 5
done

# Give sshd a few extra seconds to fully initialize once the port is open.
sleep 10

echo "==> Stage 4: Installing Ansible collections"
ansible-galaxy collection install community.docker --upgrade

echo "==> Stage 5: Running Ansible playbook"
cd ansible
ansible-playbook -i inventory.ini playbook.yml
cd "$REPO_ROOT"

echo ""
echo "============================================================"
echo "  Deploy complete."
echo ""
echo "  Public IP:    ${PUBLIC_IP}"
echo "  Verify with:  nmap -sV -Pn -p T:25565 ${PUBLIC_IP}"
echo "  Connect with: Minecraft Java client -> Multiplayer -> ${PUBLIC_IP}"
echo "============================================================"
