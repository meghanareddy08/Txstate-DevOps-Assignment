#!/usr/bin/env bash
set -euo pipefail

echo "Starting Jenkins, build agent, and local registry..."
docker compose up -d --build

echo "Waiting for Jenkins..."
until curl --silent --output /dev/null http://localhost:8080/login >/dev/null; do
    sleep 5
done

echo "Waiting for registry..."
until curl --fail --silent http://localhost:5000/v2/ >/dev/null; do
    sleep 2
done

echo
echo "Stack is ready."
echo "Jenkins:  http://localhost:8080"
echo "Registry: http://localhost:5000"
echo
docker compose ps
