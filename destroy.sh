#!/usr/bin/env bash
#
# destroy.sh — Tear down all AWS resources created by deploy.sh.
#
# Usage: ./destroy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "==> Destroying AWS resources"
terraform -chdir=terraform destroy -auto-approve

echo "==> Removing generated artifacts"
rm -f minecraft-key.pem
rm -f ansible/inventory.ini

echo "==> Done."
