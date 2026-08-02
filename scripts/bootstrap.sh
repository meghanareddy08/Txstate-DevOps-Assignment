#!/usr/bin/env bash
set -euo pipefail

JENKINS_URL_LOCAL="http://localhost:8080"
REGISTRY_URL="http://localhost:5000"
JENKINS_TIMEOUT=180
REGISTRY_TIMEOUT=60

info() {
    printf '\n[INFO] %s\n' "$1"
}

error() {
    printf '\n[ERROR] %s\n' "$1" >&2
    exit 1
}

wait_for_url() {
    local name="$1"
    local url="$2"
    local timeout="$3"
    local elapsed=0

    printf "Waiting for %s" "$name"

    until curl --fail --silent --output /dev/null "$url"; do
        sleep 3
        elapsed=$((elapsed + 3))
        printf "."

        if (( elapsed >= timeout )); then
            printf '\n'
            error "$name did not become ready within ${timeout} seconds."
        fi
    done

    printf " ready\n"
}

info "Checking prerequisites"

for command in docker curl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        error "Required command not found: $command"
    fi
done

if ! docker compose version >/dev/null 2>&1; then
    error "Docker Compose v2 is required."
fi

if [[ ! -f ".env" ]]; then
    error "Missing .env file. Run: cp .env.example .env"
fi

info "Validating required environment variables"

set -a
# shellcheck disable=SC1091
source .env
set +a

required_variables=(
    JENKINS_ADMIN_USER
    JENKINS_ADMIN_PASSWORD
    JENKINS_AGENT_NAME
    JENKINS_AGENT_SECRET
    JENKINS_URL
)

for variable in "${required_variables[@]}"; do
    if [[ -z "${!variable:-}" ]]; then
        error "$variable is missing or empty in .env"
    fi
done

info "Building and starting Jenkins controller and registry"

docker compose up -d --build jenkins-controller registry

wait_for_url \
    "Jenkins" \
    "${JENKINS_URL_LOCAL}/login" \
    "$JENKINS_TIMEOUT"

wait_for_url \
    "Docker registry" \
    "${REGISTRY_URL}/v2/" \
    "$REGISTRY_TIMEOUT"

if [[ "$JENKINS_AGENT_SECRET" == "temporary-value" ]] ||
   [[ "$JENKINS_AGENT_SECRET" == "replace-with-the-generated-agent-secret" ]]; then

    info "Jenkins controller and registry are ready"

    cat <<'INSTRUCTIONS'

The Jenkins agent has not been started because .env still contains a
placeholder JENKINS_AGENT_SECRET.

Complete these steps:

1. Open Jenkins:
   http://localhost:8080

2. Create the agent:
   Manage Jenkins
   -> Nodes
   -> New Node

3. Configure:
   Node name: Docker-agent
   Type: Permanent Agent
   Executors: 1
   Remote root directory: /home/jenkins/agent
   Label: docker
   Usage: Only build jobs matching this label
   Launch method: Launch agent by connecting it to the controller

4. Copy the generated secret into .env:

   JENKINS_AGENT_SECRET=<generated-secret>

5. Run this script again:

   ./scripts/bootstrap.sh

INSTRUCTIONS

    docker compose ps
    exit 0
fi

info "Starting Jenkins build agent"

docker compose up -d --build jenkins-agent

sleep 5

if docker compose ps --status running jenkins-agent \
    | grep -q "jenkins-agent"; then
    info "Jenkins agent container is running"
else
    docker compose logs --tail=50 jenkins-agent
    error "Jenkins agent container is not running."
fi

info "Checking agent connection logs"

if docker compose logs --tail=100 jenkins-agent 2>&1 \
    | grep -qiE "connected|handshaking"; then
    echo "Jenkins agent connection detected."
else
    echo "The agent container is running, but a connection was not confirmed."
    echo "Review:"
    echo "  docker compose logs --tail=100 jenkins-agent"
fi

info "Stack status"

docker compose ps

cat <<'SUMMARY'

Bootstrap completed.

Jenkins:
  http://localhost:8080

Registry:
  http://localhost:5000

Remaining reviewer steps:

1. Add a GitHub token to Jenkins Credentials:
   Kind: Secret text
   ID: github-read-token

2. Open the automatically created job:
   github-organization-seed

3. Run Build with Parameters:
   GITHUB_ORG=meghana-devops-test

4. Approve the Job DSL script only if Jenkins requests approval.

5. Run the generated repository jobs.

6. Verify:
   ./scripts/verify.sh

SUMMARY
