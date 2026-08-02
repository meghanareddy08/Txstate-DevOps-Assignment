#!/usr/bin/env bash
set -euo pipefail

JENKINS_BASE_URL="${JENKINS_BASE_URL:-http://localhost:8080}"
DEMO_ORG="${GITHUB_ORG:-meghana-devops-test}"
REGISTRY_URL="${REGISTRY_URL:-http://localhost:5000}"
POLL_INTERVAL=3
BUILD_TIMEOUT=600

COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

info() {
    printf '\n[INFO] %s\n' "$1"
}

fail() {
    printf '\n[ERROR] %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "Required command not found: $1"
}

jenkins_get() {
    curl --fail --silent --show-error \
        --user "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
        --cookie "$COOKIE_JAR" \
        --cookie-jar "$COOKIE_JAR" \
        "$1"
}

load_crumb() {
    local response

    if response="$(jenkins_get "${JENKINS_BASE_URL}/crumbIssuer/api/json" 2>/dev/null)"; then
        CRUMB_FIELD="$(jq -r '.crumbRequestField' <<<"$response")"
        CRUMB_VALUE="$(jq -r '.crumb' <<<"$response")"
    else
        CRUMB_FIELD=""
        CRUMB_VALUE=""
    fi
}

jenkins_post() {
    local url="$1"
    shift

    local args=(
        --fail
        --silent
        --show-error
        --dump-header -
        --output /dev/null
        --user "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}"
        --cookie "$COOKIE_JAR"
        --cookie-jar "$COOKIE_JAR"
        --request POST
    )

    if [[ -n "${CRUMB_FIELD}" && -n "${CRUMB_VALUE}" ]]; then
        args+=(--header "${CRUMB_FIELD}: ${CRUMB_VALUE}")
    fi

    curl "${args[@]}" "$@" "$url"
}

trigger_build() {
    local job_path="$1"
    shift

    local endpoint="${JENKINS_BASE_URL}/${job_path}/buildWithParameters"
    local headers
    local location

    headers="$(jenkins_post "$endpoint" "$@")"

    location="$(
        awk '
            BEGIN { IGNORECASE=1 }
            /^Location:/ {
                sub(/\r$/, "", $2)
                print $2
            }
        ' <<<"$headers"
    )"

    [[ -n "$location" ]] ||
        fail "Jenkins did not return a queue location for ${job_path}"

    printf '%s\n' "$location"
}

wait_for_queue() {
    local queue_url="$1"
    local elapsed=0
    local response
    local build_url

    while (( elapsed < BUILD_TIMEOUT )); do
        response="$(jenkins_get "${queue_url}api/json")"

        if [[ "$(jq -r '.cancelled // false' <<<"$response")" == "true" ]]; then
            fail "Jenkins cancelled the queued build."
        fi

        build_url="$(jq -r '.executable.url // empty' <<<"$response")"

        if [[ -n "$build_url" ]]; then
            printf '%s\n' "$build_url"
            return 0
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    fail "Timed out waiting for Jenkins to start the queued build."
}

wait_for_build() {
    local build_url="$1"
    local elapsed=0
    local response
    local building
    local result

    while (( elapsed < BUILD_TIMEOUT )); do
        response="$(jenkins_get "${build_url}api/json")"
        building="$(jq -r '.building' <<<"$response")"

        if [[ "$building" == "false" ]]; then
            result="$(jq -r '.result' <<<"$response")"
            printf '%s\n' "$result"
            return 0
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    fail "Timed out waiting for build ${build_url}"
}

run_job() {
    local display_name="$1"
    local expected_result="$2"
    local job_path="$3"
    shift 3

    local queue_url
    local build_url
    local result

    info "Triggering ${display_name}"

    queue_url="$(trigger_build "$job_path" "$@")"
    build_url="$(wait_for_queue "$queue_url")"

    echo "Build URL: ${build_url}"

    result="$(wait_for_build "$build_url")"

    echo "Result: ${result}"

    if [[ "$result" != "$expected_result" ]]; then
        fail "${display_name} returned ${result}; expected ${expected_result}"
    fi
}

require_command curl
require_command jq
require_command docker

[[ -f .env ]] ||
    fail "Missing .env. Run: cp .env.example .env"

set -a
# shellcheck disable=SC1091
source .env
set +a

[[ -n "${JENKINS_ADMIN_USER:-}" ]] ||
    fail "JENKINS_ADMIN_USER is missing from .env"

[[ -n "${JENKINS_ADMIN_PASSWORD:-}" ]] ||
    fail "JENKINS_ADMIN_PASSWORD is missing from .env"

info "Checking Jenkins"

curl --fail --silent --show-error \
    --user "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    "${JENKINS_BASE_URL}/api/json" \
    >/dev/null

load_crumb

run_job \
    "GitHub organization seed job" \
    "SUCCESS" \
    "job/github-organization-seed" \
    --data-urlencode "GITHUB_ORG=${DEMO_ORG}"

run_job \
    "catalog-service" \
    "SUCCESS" \
    "job/repository-builds/job/meghana-devops-test-catalog-service" \
    --data-urlencode "REPO_NAME=catalog-service" \
    --data-urlencode "REPO_FULL_NAME=meghana-devops-test/catalog-service" \
    --data-urlencode \
        "REPO_URL=https://github.com/meghana-devops-test/catalog-service.git" \
    --data-urlencode "REPO_BRANCH=main"

run_job \
    "notification-service" \
    "SUCCESS" \
    "job/repository-builds/job/meghana-devops-test-notification-service" \
    --data-urlencode "REPO_NAME=notification-service" \
    --data-urlencode \
        "REPO_FULL_NAME=meghana-devops-test/notification-service" \
    --data-urlencode \
        "REPO_URL=https://github.com/meghana-devops-test/notification-service.git" \
    --data-urlencode "REPO_BRANCH=main"

run_job \
    "payment-service expected test-gate failure" \
    "FAILURE" \
    "job/repository-builds/job/meghana-devops-test-payment-service" \
    --data-urlencode "REPO_NAME=payment-service" \
    --data-urlencode "REPO_FULL_NAME=meghana-devops-test/payment-service" \
    --data-urlencode \
        "REPO_URL=https://github.com/meghana-devops-test/payment-service.git" \
    --data-urlencode "REPO_BRANCH=main"

info "Checking registry catalog"

catalog="$(
    curl --fail --silent --show-error \
        "${REGISTRY_URL}/v2/_catalog"
)"

echo "$catalog" | jq .

jq -e '
    (.repositories | index("meghana-devops-test/catalog-service")) != null
' <<<"$catalog" >/dev/null ||
    fail "catalog-service was not found in the registry."

jq -e '
    (.repositories | index("meghana-devops-test/notification-service")) != null
' <<<"$catalog" >/dev/null ||
    fail "notification-service was not found in the registry."

if jq -e '
    (.repositories | index("meghana-devops-test/payment-service")) != null
' <<<"$catalog" >/dev/null; then
    fail "payment-service unexpectedly exists in the registry."
fi

cat <<'SUMMARY'

============================================================
DEMO COMPLETED SUCCESSFULLY
============================================================

Seed job:
  SUCCESS

catalog-service:
  Test passed
  Image built and pushed
  SUCCESS

notification-service:
  No test.sh
  Image built and pushed
  SUCCESS

payment-service:
  Test failed
  Build and push blocked
  EXPECTED FAILURE

Registry validation:
  catalog-service present
  notification-service present
  payment-service absent
============================================================
SUMMARY
