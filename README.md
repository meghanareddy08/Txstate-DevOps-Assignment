# GitHub Organization Jenkins Pipeline Factory

A Docker Compose-based Jenkins automation stack that discovers repositories in a GitHub organization, creates one Jenkins pipeline for each qualifying repository, runs an optional test gate, builds Docker images, and publishes successful images to a local Docker Registry v2 instance.

A repository qualifies when it:

- is not archived
- contains a root-level `Dockerfile`

If a root-level `test.sh` exists, the generated Jenkins pipeline runs it before building the image. A nonzero test exit code stops the pipeline and prevents both the Docker build and registry push.

---

## Demonstrated Result

The implementation was validated against the controlled GitHub organization:

```text
meghana-devops-test
```

Demonstrated repositories:

| Repository | Root `Dockerfile` | Root `test.sh` | Expected result |
|---|---:|---:|---|
| `catalog-service` | Yes | Passing | Test, build, and push succeed |
| `notification-service` | Yes | Missing | Build and push succeed |
| `payment-service` | Yes | Failing | Build and push are blocked |
| `platform-documentation` | No | Not applicable | No Jenkins job is created |

Final demonstrated result:

```text
GitHub repositories discovered:       4
Generated Jenkins pipelines:          3
Successful images published:          2
Expected failed test pipelines:       1
Repositories filtered without image:  1
```

The complete automated demonstration produced:

```text
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
```

The `payment-service` Jenkins build is intentionally expected to finish with `FAILURE`. The overall demonstration succeeds because the script verifies that the failed test prevented both the Docker build and registry push.

---

## What the System Does

The workflow performs the following:

1. Enumerates repositories in a GitHub organization.
2. Detects root-level `Dockerfile` and `test.sh` files.
3. Records repository metadata in a JSON inventory.
4. Uses Jenkins Job DSL to create or update one pipeline per qualifying repository.
5. Checks out each qualifying repository.
6. Runs `test.sh` when present.
7. Stops the pipeline when the test exits with a nonzero status.
8. Builds successful Docker images.
9. Tags images with the Git commit SHA and Jenkins build number.
10. Pushes successful images to a local Docker Registry v2 instance.
11. Verifies that expected images exist and failed images were not published.

---

## Architecture

```text
GitHub Organization
        |
        v
Jenkins Seed Pipeline
        |
        v
Repository Discovery
        |
        v
discovery/repositories.json
        |
        v
Jenkins Job DSL
        |
        v
Generated Repository Pipelines
        |
        v
Optional Test Gate
        |
        +---- test fails ----> Pipeline stops
        |
        v
Docker Build
        |
        v
Local Docker Registry
```

The Jenkins controller has zero executors. Repository discovery, tests, Docker builds, and registry pushes run only on the dedicated Jenkins agent labeled:

```text
docker
```

---

## Components

| Component | Responsibility |
|---|---|
| Jenkins controller | Orchestrates seed and generated repository jobs |
| Jenkins build agent | Runs Git, discovery, tests, Docker builds, and registry pushes |
| Discovery script | Enumerates and classifies GitHub repositories |
| Seed pipeline | Runs discovery and invokes Jenkins Job DSL |
| Job DSL | Creates or updates repository-specific Jenkins pipelines |
| Repository pipeline | Applies the reusable test, build, and push workflow |
| Local registry | Stores successfully published Docker images |
| Docker Compose | Runs the Jenkins controller, agent, and registry |
| Bootstrap script | Starts services and validates initial configuration |
| Demo script | Runs and verifies the complete workflow |
| Verification script | Checks Jenkins, Docker Compose, and registry availability |

---

## Repository Structure

```text
.
├── .env.example
├── .gitignore
├── README.md
├── docker-compose.yml
├── discovery/
│   ├── discover_repositories.py
│   └── requirements.txt
├── docs/
│   ├── architecture.md
│   └── images/
│       ├── catalog-service-success.png
│       ├── generated-repository-jobs.png
│       ├── payment-service-test-gate.png
│       └── seed-pipeline-success.png
├── jenkins-agent/
│   └── Dockerfile
├── jenkins-controller/
│   ├── Dockerfile
│   ├── casc.yaml
│   └── plugins.txt
├── jobs/
│   └── seed_job.groovy
├── pipelines/
│   ├── repository-build.Jenkinsfile
│   └── seed.Jenkinsfile
└── scripts/
    ├── bootstrap.sh
    ├── run-demo.sh
    └── verify.sh
```

---

## Prerequisites

The host must have:

- Linux
- Git
- Docker Engine
- Docker Compose v2
- `curl`
- `jq`
- internet access to GitHub and Docker Hub
- a GitHub token with read access to the organization being evaluated

Verify the required tools:

```bash
git --version
docker --version
docker compose version
curl --version
jq --version
```

Recommended minimum resources:

| Resource | Recommendation |
|---|---:|
| CPU | 2 cores |
| Memory | 4 GB |
| Disk | 10 GB |

---

# Clean Checkout Setup

## 1. Clone the repository

```bash
git clone https://github.com/meghanareddy08/Txstate-DevOps-Assignment.git
cd Txstate-DevOps-Assignment
```

## 2. Create the local environment file

```bash
cp .env.example .env
```

Populate `.env`:

```env
JENKINS_ADMIN_USER=admin
JENKINS_ADMIN_PASSWORD=replace-with-a-secure-password

JENKINS_AGENT_NAME=Docker-agent
JENKINS_AGENT_SECRET=replace-with-the-generated-agent-secret

JENKINS_URL=http://jenkins-controller:8080
```

The `.env` file is excluded from Git and must never be committed.

Verify that it is ignored:

```bash
git check-ignore .env
```

Expected output:

```text
.env
```

Verify that it is not tracked:

```bash
git ls-files .env
```

Expected output:

```text
no output
```

---

## 3. Start Jenkins and the registry

Run:

```bash
./scripts/bootstrap.sh
```

On the first run, the agent secret will still contain the placeholder value. The bootstrap script will:

- validate required commands
- validate required environment variables
- build the Jenkins controller and registry
- start the Jenkins controller
- start the local Docker registry
- wait for Jenkins to become available
- display the required agent-registration instructions

The script will not start the inbound Jenkins agent until a valid Jenkins agent secret is added to `.env`.

Alternative manual startup:

```bash
docker compose up -d --build jenkins-controller registry
```

Check service status:

```bash
docker compose ps
```

Monitor Jenkins startup:

```bash
docker compose logs -f jenkins-controller
```

Continue when the logs show:

```text
Jenkins is fully up and running
```

---

## 4. Open Jenkins

For a local environment, open:

```text
http://localhost:8080
```

For a remote host such as EC2, create an SSH tunnel from the local computer:

```bash
ssh -i /path/to/key.pem \
  -L 8080:localhost:8080 \
  ubuntu@REMOTE_HOST
```

Then open:

```text
http://localhost:8080
```

Log in using the values from `.env`:

```text
Username: JENKINS_ADMIN_USER
Password: JENKINS_ADMIN_PASSWORD
```

---

# One-Time Jenkins Configuration

These steps are required once for a clean Jenkins installation.

## 1. Confirm the automatically created seed job

The Jenkins controller uses Jenkins Configuration as Code to create the seed pipeline automatically.

After Jenkins starts, the dashboard should contain:

```text
github-organization-seed
```

The job is configured with:

```text
Repository:
https://github.com/meghanareddy08/Txstate-DevOps-Assignment.git

Branch:
*/main

Script path:
pipelines/seed.Jenkinsfile
```

The target organization is supplied at runtime using the parameter:

```text
GITHUB_ORG
```

The seed job does not need to be created manually.

---

## 2. Create the Jenkins build agent

Navigate to:

```text
Manage Jenkins
-> Nodes
-> New Node
```

Configure:

```text
Node name:
Docker-agent

Type:
Permanent Agent

Number of executors:
1

Remote root directory:
/home/jenkins/agent

Label:
docker

Usage:
Only build jobs with label expressions matching this node

Launch method:
Launch agent by connecting it to the controller
```

Save the node.

Jenkins will display the generated inbound-agent secret. Copy that secret and update `.env`:

```env
JENKINS_AGENT_SECRET=generated-agent-secret
```

Run the bootstrap script again:

```bash
./scripts/bootstrap.sh
```

The second run will start the Jenkins agent.

Verify the agent connection:

```bash
docker compose logs --tail=50 jenkins-agent
```

Expected output includes:

```text
Connected
```

The Jenkins Nodes page should show `Docker-agent` as online.

---

## 3. Create a read-only GitHub token

Create a GitHub personal access token that can read the target organization and repositories.

A fine-grained token is recommended.

Suggested configuration:

```text
Repository access:
Selected repositories or all repositories in the target organization

Repository permissions:
Contents: Read-only
Metadata: Read-only
```

The token does not require repository write access.

For public repositories, unauthenticated discovery may work, but Jenkins uses an authenticated token to provide more reliable GitHub API access and a higher rate limit.

---

## 4. Add the GitHub token to Jenkins

Navigate to:

```text
Manage Jenkins
-> Credentials
-> System
-> Global credentials
-> Add Credentials
```

Configure:

```text
Kind:
Secret text

Secret:
<GitHub read token>

ID:
github-read-token

Description:
Read-only GitHub organization discovery token
```

The credential ID must be exactly:

```text
github-read-token
```

The seed pipeline injects the token only during repository discovery.

Jenkins masks the token in console logs. The token is not stored in the repository or `.env`.

---

## 5. Approve Job DSL if Jenkins requests it

On the first seed-pipeline run, Jenkins may report:

```text
script not yet approved for use
```

Navigate to:

```text
Manage Jenkins
-> In-process Script Approval
```

Approve the pending Job DSL script.

This step depends on Jenkins script-security behavior and may not be required in every environment.

---

# Run the Workflow End to End

## Preferred automated demonstration

After:

- Jenkins is running
- the Docker agent is connected
- the `github-read-token` credential exists
- Job DSL approval has been completed if requested

run:

```bash
./scripts/run-demo.sh
```

The script automatically:

1. checks Jenkins availability
2. triggers `github-organization-seed`
3. supplies the GitHub organization parameter
4. waits for the seed job to finish
5. confirms repository jobs were generated
6. triggers the catalog pipeline
7. triggers the notification pipeline
8. triggers the payment pipeline
9. verifies the expected success and failure outcomes
10. verifies the local registry contents
11. confirms no payment image was published

Expected output:

```text
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
```

---

## Manual workflow and inspection

### 1. Run organization discovery

Open:

```text
github-organization-seed
-> Build with Parameters
```

Set:

```text
GITHUB_ORG=meghana-devops-test
```

Run the job.

The seed pipeline executes:

```text
Checkout Assignment
-> Discover Repositories
-> Validate Inventory
-> Generate Repository Jobs
```

Expected result:

```text
Organization: meghana-devops-test
Repositories discovered: 4
Buildable repositories: 3
Inventory written to: discovery/repositories.json
Finished: SUCCESS
```

---

### 2. Review generated pipelines

The seed job creates the folder:

```text
repository-builds
```

Expected generated jobs:

```text
repository-builds/
├── meghana-devops-test-catalog-service
├── meghana-devops-test-notification-service
└── meghana-devops-test-payment-service
```

The seed job is idempotent. Re-running it updates managed jobs rather than creating duplicates.

The repository without a root-level `Dockerfile` does not receive a generated job.

---

### 3. Run the generated jobs

Run:

```text
repository-builds/meghana-devops-test-catalog-service
repository-builds/meghana-devops-test-notification-service
repository-builds/meghana-devops-test-payment-service
```

Expected behavior:

| Repository | Test behavior | Build behavior | Final result |
|---|---|---|---|
| `catalog-service` | Passes | Image built and pushed | `SUCCESS` |
| `notification-service` | No test found | Image built and pushed | `SUCCESS` |
| `payment-service` | Fails | Build and push skipped | `FAILURE` |

The `payment-service` failure is intentional and demonstrates enforcement of the test gate.

---

# Repository Qualification Rules

A repository receives a generated pipeline when:

```text
A root-level Dockerfile exists
AND
The repository is not archived
```

The root-level `test.sh` file is optional.

| `Dockerfile` | `test.sh` | Test result | Pipeline behavior |
|---|---|---|---|
| Present | Present | Exit code `0` | Build and push |
| Present | Present | Nonzero exit code | Stop before build |
| Present | Missing | Not applicable | Build and push |
| Missing | Any | Not applicable | No pipeline created |
| Present | Any | Archived repository | No pipeline created |

The generated repository pipeline checks the files again after checkout. It does not rely only on the earlier discovery result.

---

# Discovery Inventory

The discovery script writes repository metadata to:

```text
discovery/repositories.json
```

Each repository entry includes information such as:

```json
{
  "name": "catalog-service",
  "full_name": "meghana-devops-test/catalog-service",
  "clone_url": "https://github.com/meghana-devops-test/catalog-service.git",
  "default_branch": "main",
  "archived": false,
  "has_dockerfile": true,
  "has_test_sh": true,
  "buildable": true
}
```

The inventory file is written atomically.

If discovery fails:

- the temporary inventory file is removed
- the pipeline exits nonzero
- Job DSL does not run
- previously generated jobs remain available
- an incomplete inventory does not replace the previous valid inventory

---

# GitHub API Reliability

The discovery client includes request timeouts and retry handling.

Temporary GitHub API failures are retried for status codes including:

```text
429
500
502
503
504
```

Retries use exponential backoff.

Connection failures are also retried before discovery is marked as failed.

Non-retryable failures such as invalid credentials return a clear error and stop the seed pipeline.

---

# Test Gate Behavior

When a root-level `test.sh` exists, the repository pipeline runs:

```bash
sh ./test.sh
```

Expected contract:

```text
Exit code 0:
Test passed

Any nonzero exit code:
Test failed
```

When testing fails:

- image metadata preparation is skipped
- Docker build is skipped
- registry push is skipped
- Jenkins reports `FAILURE`

This ensures an image cannot be published after a failed test.

---

# Image Naming and Tagging

Successful images are published using:

```text
localhost:5000/<organization>/<repository>:<tag>
```

Each successful build creates two tags:

1. Git commit SHA
2. Jenkins build number

Example:

```text
localhost:5000/meghana-devops-test/catalog-service:b82dd8257769
localhost:5000/meghana-devops-test/catalog-service:build-3
```

The Git SHA provides source-code traceability.

The Jenkins build-number tag connects the image to a specific pipeline execution.

A mutable `latest` tag is intentionally not used.

---

# Registry Verification

Run:

```bash
./scripts/verify.sh
```

The verification script checks:

- Docker Compose service status
- Jenkins availability
- local registry availability
- current registry catalog

List registry repositories manually:

```bash
curl -s http://localhost:5000/v2/_catalog | jq
```

Expected result after the demonstration:

```json
{
  "repositories": [
    "meghana-devops-test/catalog-service",
    "meghana-devops-test/notification-service"
  ]
}
```

Only two image repositories are expected because:

- `catalog-service` passed its test and was pushed
- `notification-service` had no test and was pushed
- `payment-service` failed its test and was not pushed
- `platform-documentation` had no `Dockerfile`

List catalog-service tags:

```bash
curl -s \
  http://localhost:5000/v2/meghana-devops-test/catalog-service/tags/list \
  | jq
```

List notification-service tags:

```bash
curl -s \
  http://localhost:5000/v2/meghana-devops-test/notification-service/tags/list \
  | jq
```

Confirm payment-service is absent:

```bash
curl -s \
  http://localhost:5000/v2/meghana-devops-test/payment-service/tags/list \
  | jq
```

The payment repository should not contain published tags.

---

# Failure Handling

## GitHub authentication failure

When the GitHub token is invalid, expired, or revoked:

```text
discovery exits nonzero
Job DSL does not run
generated jobs are not replaced
the seed pipeline reports failure
```

## Temporary GitHub API failure

Temporary failures such as `502 Bad Gateway` are retried with exponential backoff.

If all retry attempts fail:

```text
discovery exits nonzero
Job DSL does not run
the previous valid inventory is preserved
```

## Unknown organization

When the organization does not exist or cannot be accessed:

```text
discovery exits nonzero
no new jobs are created
the seed pipeline reports failure
```

## Missing Dockerfile after discovery

If a repository loses its `Dockerfile` between discovery and pipeline execution:

```text
repository validation fails
Docker build does not run
registry push does not run
```

## Failed test script

If `test.sh` exits nonzero:

```text
image metadata preparation is skipped
Docker build is skipped
registry push is skipped
Jenkins reports FAILURE
```

## Registry failure

If the registry is unavailable:

```text
Docker push fails
Jenkins reports FAILURE
the image is not reported as successfully published
```

## Jenkins agent unavailable

If the dedicated agent is offline:

```text
the job remains queued
no repository code runs on the controller
the controller retains zero executors
```

---

# Security Decisions

## Jenkins controller isolation

The Jenkins controller has:

```text
0 executors
```

Repository code and Docker builds run only on the dedicated build agent.

This reduces the amount of untrusted build activity executed directly on the controller.

## GitHub credential

The GitHub token is:

- read-only
- stored in Jenkins Credentials
- injected only during repository discovery
- masked in Jenkins console logs
- never committed to Git
- not stored in `.env`

## Least privilege

The GitHub token requires only repository metadata and content read access.

It does not require:

- repository write access
- package write access
- organization administration
- workflow administration

## Docker socket access

Only the Jenkins build agent mounts:

```text
/var/run/docker.sock
```

The Jenkins controller does not receive Docker socket access.

Mounting the host Docker socket gives the agent privileged control over the host Docker daemon. This is an explicit trade-off for a controlled local evaluation environment.

## Local registry

The registry is intended for local evaluation and does not currently use:

- TLS
- authentication
- repository authorization
- image retention policies
- image signing
- vulnerability scanning

It should not be exposed publicly.

## Secret handling

The following must never be committed:

```text
.env
GitHub tokens
Jenkins agent secrets
Jenkins passwords
SSH private keys
cloud credentials
```

The included `.gitignore` prevents `.env` from being tracked.

---

# Assumptions

The implementation assumes:

- repositories use a root-level file named exactly `Dockerfile`
- optional tests use a root-level file named exactly `test.sh`
- `test.sh` is compatible with `/bin/sh`
- exit code `0` means success
- any nonzero test exit code means failure
- the GitHub default branch is the branch to build
- repositories are accessible using HTTPS clone URLs
- the target organization is within normal GitHub API limits
- Docker is available through the host Docker socket
- the registry is reachable from the host Docker daemon at `localhost:5000`
- the environment is local or otherwise controlled
- generated Jenkins jobs are managed by the seed pipeline
- one dedicated Docker-capable Jenkins agent is sufficient for the evaluation workload

---

# Design Trade-offs

## Host Docker socket

Chosen because it provides:

- simple local setup
- fast Docker builds
- shared image layer caching
- fewer runtime components
- straightforward access to the local registry

Trade-offs:

- the build agent has host-level Docker privileges
- builds are not strongly isolated
- repository code can potentially affect the Docker host

Production alternatives include:

- ephemeral Kubernetes agents
- rootless BuildKit
- Kaniko
- isolated virtual machines
- dedicated remote Docker builders

## Permanent Jenkins agent

Chosen because it provides:

- simple local operation
- low resource usage
- predictable configuration
- straightforward troubleshooting

Trade-offs:

- state may persist between builds
- builds share a worker
- isolation is weaker than ephemeral workers

A production platform should use short-lived agents created for individual builds.

## Local registry

Chosen because it provides:

- simple reproducibility
- no dependency on an external registry account
- easy local inspection
- fast local image pushes

A production registry should include:

- TLS
- authentication
- authorization
- durable storage
- image retention
- vulnerability scanning
- image signing
- provenance information

## Jenkins Job DSL

Chosen because it provides:

- repeatable repository job generation
- readable job definitions
- idempotent updates
- centralized pipeline configuration

Trade-offs:

- initial script approval may be required
- Job DSL behavior depends on Jenkins plugin compatibility

## Central reusable pipeline

Generated jobs reference the same reusable repository pipeline definition.

Benefits:

- consistent behavior across repositories
- easier maintenance
- one place to update test, build, and push logic
- less duplicated Jenkins configuration

Trade-off:

- generated jobs depend on the assignment repository remaining available

---

# Manual Configuration Still Required

A clean Jenkins installation currently requires one-time setup for:

- Jenkins agent registration
- GitHub credential creation
- Job DSL script approval, if Jenkins requests it

The seed pipeline job itself is created automatically through Jenkins Configuration as Code.

The bootstrap script detects a placeholder agent secret and displays the remaining agent-registration steps.

---

# Improvements for a Production System

With additional time, the following improvements would be implemented:

- automated Jenkins inbound-agent registration
- secure external secret management
- GitHub App authentication
- GitHub webhook triggers
- ephemeral isolated build agents
- rate-limit-aware GitHub retry scheduling
- pagination and concurrency tuning for very large organizations
- registry TLS and authentication
- container vulnerability scanning
- software bill of materials generation
- image signing and provenance
- secret scanning
- policy enforcement
- structured JSON logging
- Prometheus metrics and dashboards
- image retention and garbage collection
- build concurrency controls
- automated integration tests
- automatic cleanup of obsolete generated jobs
- branch and pull-request build support
- configurable Dockerfile and test paths
- support for multiple build strategies

---

# Restarting the Environment

After restarting the same host:

```bash
cd Txstate-DevOps-Assignment
./scripts/bootstrap.sh
./scripts/verify.sh
```

Jenkins configuration, jobs, credentials, build history, and registry images persist through Docker volumes.

Do not run:

```bash
docker compose down -v
```

unless persistent Jenkins and registry data should be permanently deleted.

---

# Stopping the Environment

Stop containers while preserving persistent data:

```bash
docker compose down
```

Remove containers and persistent Jenkins and registry data:

```bash
docker compose down -v
```

> **Warning:** `docker compose down -v` permanently removes Jenkins jobs, credentials, build history, configuration state, and registry images.

---

# Useful Troubleshooting Commands

Check running services:

```bash
docker compose ps
```

Check Jenkins controller logs:

```bash
docker compose logs --tail=100 jenkins-controller
```

Check Jenkins agent logs:

```bash
docker compose logs --tail=100 jenkins-agent
```

Check registry logs:

```bash
docker compose logs --tail=100 registry
```

Check registry availability:

```bash
curl -s http://localhost:5000/v2/
```

Check Jenkins availability:

```bash
curl -I http://localhost:8080/login
```

Check whether the Jenkins agent is idle:

```bash
set -a
source .env
set +a

curl -sS \
  -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  http://localhost:8080/computer/api/json |
jq '.computer[] | {
  displayName,
  idle,
  temporarilyOffline
}'
```

Validate Docker Compose:

```bash
docker compose config
```

Validate shell scripts:

```bash
bash -n scripts/bootstrap.sh
bash -n scripts/run-demo.sh
bash -n scripts/verify.sh
```

Validate the discovery script:

```bash
python3 -m py_compile discovery/discover_repositories.py
```

Check repository formatting:

```bash
git diff --check
```

---

# AI-Assisted Development Disclosure

Generative AI was used to assist with:

- evaluating architecture options
- drafting initial configuration
- troubleshooting Jenkins and Docker errors
- improving documentation structure
- reviewing security trade-offs
- suggesting validation steps

All generated suggestions were reviewed, modified where necessary, and tested against the running environment.

Corrections made during implementation included:

- using `localhost:5000` for registry pushes through the host Docker daemon
- configuring the Jenkins controller with zero executors
- moving build activity to a dedicated Docker-capable agent
- creating the parent Jenkins folder before nested jobs
- correcting Job DSL compatibility issues
- fixing Jenkins readiness checks
- adding GitHub API request timeouts
- adding retry and exponential-backoff handling
- preserving the previous valid inventory during discovery failures
- validating passing, missing-test, and failing-test scenarios separately
- automating seed-job creation through Jenkins Configuration as Code
- adding an end-to-end demonstration script
- verifying registry contents after all builds

The final implementation reflects tested runtime behavior rather than unverified generated output.

---

# Final Validation Summary

```text
Seed pipeline:
SUCCESS

Repositories discovered:
4

Buildable repositories:
3

Generated Jenkins jobs:
3

catalog-service:
Test passed
Docker image built
Docker image pushed
SUCCESS

notification-service:
No test.sh
Docker image built
Docker image pushed
SUCCESS

payment-service:
Test failed
Docker build skipped
Registry push skipped
EXPECTED FAILURE

platform-documentation:
No Dockerfile
No generated pipeline

Registry:
catalog-service present
notification-service present
payment-service absent
```

## Automated Demo Evidence

![Automated end-to-end demo](docs/images/automated-demo-success.png)
