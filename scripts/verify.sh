#!/usr/bin/env bash
set -euo pipefail

echo "Checking Docker Compose services..."
docker compose ps

echo
echo "Checking Jenkins..."
curl --silent --show-error \
  http://localhost:8080/login \
  >/dev/null
echo "Jenkins is reachable"

echo
echo "Checking local registry..."
curl --silent --show-error \
  http://localhost:5000/v2/ \
  >/dev/null
echo "Registry is reachable"

echo
echo "Checking registry catalog..."
curl --silent --show-error \
  http://localhost:5000/v2/_catalog | jq .

echo
echo "Verification completed successfully"
