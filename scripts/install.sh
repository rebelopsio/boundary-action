#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: install.sh <version>}"
INSTALLER_URL="https://github.com/rebelopsio/boundary/releases/download/v${VERSION}/boundary-installer.sh"

echo "Installing boundary v${VERSION}..."
curl --proto '=https' --tlsv1.2 -LsSf "${INSTALLER_URL}" | sh
