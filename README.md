# GitHub Organization Jenkins Pipeline Factory

This project provides an automated repository-to-container-image workflow using a local Docker Compose stack.

The stack includes:

- a Jenkins controller;
- a dedicated Jenkins build agent;
- a local Docker Registry.

Given a GitHub organization, the workflow automatically:

1. discovers repositories;
2. detects root-level `Dockerfile` and optional `test.sh` files;
3. creates or updates one Jenkins pipeline per qualifying repository;
4. runs `test.sh` when present;
5. blocks builds when tests fail;
6. builds eligible Docker images;
7. pushes successful images to the local registry.

GitHub remains the external source-control and repository-discovery service. Jenkins, the build agent, and the registry run locally through Docker Compose.

The Jenkins controller has zero executors. Discovery, repository checkout, tests, Docker builds, and registry pushes run on a dedicated Jenkins agent labeled `docker`.

For detailed diagrams and component boundaries, see [Architecture](docs/architecture.md).

## Automation Scope

The repeated repository build workflow is automated.

After the documented one-time Jenkins bootstrap, the system automatically:

- enumerates repositories in the selected GitHub organization;
- filters archived repositories;
- detects root-level `Dockerfile` and `test.sh` files;
- creates or updates Jenkins jobs through Job DSL;
- checks out each repository's default branch;
- runs the optional test gate;
- builds eligible images;
- applies traceable tags;
- pushes successful images to the local registry;
- verifies expected results.

A completely new Jenkins data volume requires these one-time steps:

- registering the inbound Jenkins agent;
- copying the Jenkins-generated agent secret into `.env`;
- creating the read-only GitHub credential;
- approving the initial Job DSL script when Jenkins requests it.

These are environment and security initialization steps, not per-repository workflow steps.

## Demonstrated Results

The controlled demonstration uses:

```text
meghana-devops-test
```

| Repository | Root Dockerfile | Root `test.sh` | Result |
|---|---:|---:|---|
| `catalog-service` | Yes | Passes | Image built and pushed |
| `notification-service` | Yes | Missing | Image built and pushed |
| `payment-service` | Yes | Fails | Build and push blocked |
| `platform-documentation` | No | N/A | No Jenkins job created |

Final result:

- repositories discovered: 4;
- generated Jenkins jobs: 3;
- successful images published: 2;
- expected failed pipelines: 1.

## Components

| Component | Purpose |
|---|---|
| Jenkins controller | Stores configuration and credentials, creates jobs, schedules builds, and retains build history |
| Jenkins agent | Runs discovery, checkout, tests, Docker builds, and registry pushes |
| Discovery script | Enumerates repositories and inspects root-level files |
| Repository inventory | Transfers normalized discovery results to Job DSL |
| Job DSL | Creates or updates repository-specific Jenkins jobs |
| Repository pipeline | Applies checkout, validation, test, build, and push logic |
| Host Docker daemon | Builds and tags images requested by the Jenkins agent |
| Local registry | Stores successfully published images |
| `bootstrap.sh` | Starts and validates the environment |
| `run-demo.sh` | Runs the controlled end-to-end demonstration |
| `verify.sh` | Checks Compose, Jenkins, the build agent, and registry |

# Quick Start

From a clean checkout:

```bash
git clone https://github.com/meghanareddy08/Txstate-DevOps-Assignment.git
cd Txstate-DevOps-Assignment
cp .env.example .env
nano .env
./scripts/bootstrap.sh
```

On a completely fresh Jenkins installation, complete the documented one-time Jenkins bootstrap.

Then run:

```bash
./scripts/run-demo.sh
```

After the initial bootstrap, repeated execution requires only:

```bash
./scripts/bootstrap.sh
./scripts/run-demo.sh
```

# Prerequisites

The host must have:

- Linux;
- Git;
- Docker Engine;
- Docker Compose v2;
- `curl`;
- `jq`;
- internet access to GitHub and Docker Hub;
- a GitHub token with read access to the target repositories.

Verify:

```bash
git --version
docker --version
docker compose version
curl --version
jq --version
```

Recommended minimum resources:

- CPU: 2 vCPUs;
- memory: 4 GB;
- disk: 20 GB.

A machine with 2 vCPUs and 8 GB memory is recommended for smoother Docker builds.

Check available disk space:

```bash
df -h /
```

Several GB of free space should remain before running the complete demonstration.

# Clean Checkout Setup

## 1. Clone the Repository

```bash
git clone https://github.com/meghanareddy08/Txstate-DevOps-Assignment.git
cd Txstate-DevOps-Assignment
```

Confirm the checkout is clean:

```bash
git status
```

Expected:

```text
nothing to commit, working tree clean
```

## 2. Create the Environment File

Copy the example:

```bash
cp .env.example .env
```

Edit it:

```bash
nano .env
```

Configure:

```env
JENKINS_ADMIN_USER=admin
JENKINS_ADMIN_PASSWORD=replace-with-a-secure-password

JENKINS_AGENT_NAME=Docker-agent
JENKINS_AGENT_SECRET=replace-with-generated-agent-secret

JENKINS_URL=http://jenkins-controller:8080
```

Important:

- `JENKINS_ADMIN_PASSWORD` is used to sign in to Jenkins.
- The Jenkins administrator password is not the GitHub token.
- Do not replace `JENKINS_AGENT_SECRET` yet.
- Jenkins generates the agent secret after the node is created.
- Do not add the GitHub token to `.env`.
- Do not commit `.env`.

Verify that `.env` is ignored:

```bash
git check-ignore .env
git ls-files .env
```

Expected:

- `git check-ignore .env` prints `.env`;
- `git ls-files .env` prints nothing.

## 3. Start the Stack

Run:

```bash
./scripts/bootstrap.sh
```

The script:

- validates prerequisites;
- builds and starts the Jenkins controller;
- starts the local registry;
- waits for Jenkins readiness;
- creates the seed job through Jenkins Configuration as Code;
- prints the remaining one-time setup steps.

Check services:

```bash
docker compose ps
```

Monitor Jenkins:

```bash
docker compose logs -f jenkins-controller
```

Continue when the logs show:

```text
Jenkins is fully up and running
```

Press `Ctrl+C` to stop following the logs.

On a fresh installation, the agent cannot connect until the Jenkins node is created and its generated secret is added to `.env`.

The agent may be stopped until registration is complete:

```bash
docker compose stop jenkins-agent 2>/dev/null || true
```

To start only Jenkins and the registry:

```bash
docker compose up -d --build jenkins-controller registry
```

## 4. Open Jenkins

### Local Linux Host

Open:

```text
http://localhost:8080
```

### Remote Host or EC2

From the reviewer's local computer:

```bash
ssh -i /path/to/key.pem \
  -L 8080:localhost:8080 \
  ubuntu@HOST_PUBLIC_IP
```

Keep the SSH session open, then browse to:

```text
http://localhost:8080
```

Log in using:

```text
Username: value of JENKINS_ADMIN_USER
Password: value of JENKINS_ADMIN_PASSWORD
```

# One-Time Jenkins Bootstrap

Complete this section only when using a new Jenkins data volume.

Jenkins jobs, credentials, build history, and registry data persist across normal restarts.

## 1. Confirm the Seed Job

Jenkins Configuration as Code automatically creates:

```text
github-organization-seed
```

The job uses:

```text
Repository:
https://github.com/meghanareddy08/Txstate-DevOps-Assignment.git

Branch:
*/main

Script path:
pipelines/seed.Jenkinsfile
```

The seed job does not need to be created manually.

## 2. Create the Build Agent

In Jenkins:

```text
Manage Jenkins
-> Nodes
-> New Node
```

Configure:

```text
Node name: Docker-agent
Type: Permanent Agent
Executors: 1
Remote root directory: /home/jenkins/agent
Label: docker
Usage: Only build jobs with label expressions matching this node
Launch method: Launch agent by connecting it to the controller
```

Save the node.

Then open:

```text
Manage Jenkins
-> Nodes
-> Docker-agent
-> Status
```

Jenkins displays a launch command containing:

```text
-secret <generated-secret>
```

Copy only the value after `-secret`.

The secret is generated by Jenkins and is intentionally not stored in source control.

Update `.env`:

```bash
nano .env
```

Replace:

```env
JENKINS_AGENT_SECRET=replace-with-generated-agent-secret
```

with:

```env
JENKINS_AGENT_SECRET=the-generated-secret
```

The node name is case-sensitive:

```env
JENKINS_AGENT_NAME=Docker-agent
```

Recreate the agent container:

```bash
docker compose up -d --build --force-recreate jenkins-agent
```

Verify:

```bash
docker compose logs --tail=50 -f jenkins-agent
```

Expected output includes:

```text
Connected
```

Press `Ctrl+C` after the connection succeeds.

Confirm the node is online:

```text
Manage Jenkins
-> Nodes
-> Docker-agent
```

## 3. Add the GitHub Credential

Create a fine-grained GitHub token with read-only access to the target repositories.

Recommended permissions:

```text
Contents: Read-only
Metadata: Read-only
```

In Jenkins:

```text
Manage Jenkins
-> Credentials
-> System
-> Global credentials
-> Add Credentials
```

Configure:

```text
Kind: Secret text
Secret: <GitHub read token>
ID: github-read-token
Description: Read-only GitHub discovery token
```

The credential ID must be exactly:

```text
github-read-token
```

The token is stored only in Jenkins Credentials and is not committed to the repository.

Do not add the token to:

- `.env`;
- Git;
- screenshots;
- shell history;
- documentation.

## 4. Run the Initial Seed Build

Open:

```text
github-organization-seed
-> Build with Parameters
```

Set:

```text
GITHUB_ORG=meghana-devops-test
```

Run the build.

Expected discovery output:

```text
Repositories discovered: 4
Buildable repositories: 3
```

### First-Run Job DSL Approval

On a new Jenkins installation, the first seed build may fail with:

```text
ERROR: script not yet approved for use
```

Open:

```text
Manage Jenkins
-> In-process Script Approval
```

Approve the pending script.

Run the seed job again with:

```text
GITHUB_ORG=meghana-devops-test
```

Expected result:

```text
Finished: SUCCESS
```

After approval, subsequent runs do not require this step unless Jenkins identifies a new script requiring approval.

The following jobs should exist under `repository-builds`:

```text
meghana-devops-test-catalog-service
meghana-devops-test-notification-service
meghana-devops-test-payment-service
```

No job should be created for:

```text
platform-documentation
```

# Run the Workflow End to End

After Jenkins, the agent, credential, and Job DSL approval are ready, run:

```bash
./scripts/run-demo.sh
```

The script:

- triggers the organization seed pipeline;
- supplies `meghana-devops-test`;
- waits for generated repository jobs;
- runs the catalog, notification, and payment pipelines;
- checks expected success and failure states;
- validates registry contents.

Expected final output:

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

The `payment-service` Jenkins job is intentionally expected to finish with `FAILURE`.

This confirms that a failed test prevents both Docker build and registry publication.

# Verification

Run:

```bash
./scripts/verify.sh
```

Check the registry:

```bash
curl -s http://localhost:5000/v2/_catalog | jq
```

Expected:

```json
{
  "repositories": [
    "meghana-devops-test/catalog-service",
    "meghana-devops-test/notification-service"
  ]
}
```

The `payment-service` image must be absent.

Confirm the repository remains clean:

```bash
git status
```

Expected:

```text
nothing to commit, working tree clean
```

# Run Against Another Organization

Open:

```text
github-organization-seed
-> Build with Parameters
```

Set:

```text
GITHUB_ORG=<organization-name>
```

The `github-read-token` credential must have read access to that organization.

The seed pipeline will:

- enumerate repositories;
- filter archived repositories;
- detect root-level `Dockerfile` and `test.sh` files;
- create or update jobs for qualifying repositories.

| Dockerfile | `test.sh` | Behavior |
|---|---|---|
| Present | Passes | Build and push |
| Present | Fails | Stop before build |
| Present | Missing | Build and push |
| Missing | Any | No Jenkins job |
| Present | Any | No job when archived |

Repositories in other organizations may have project-specific Docker build requirements. The `meghana-devops-test` organization is the validated end-to-end demonstration environment.

# Image Naming

Successful images are pushed to:

```text
localhost:5000/<organization>/<repository>:<tag>
```

Each successful build creates:

- a Git commit SHA tag;
- a Jenkins build-number tag.

Example:

```text
localhost:5000/meghana-devops-test/catalog-service:b82dd8257769
localhost:5000/meghana-devops-test/catalog-service:build-3
```

A mutable `latest` tag is intentionally not used.

# Troubleshooting

## Docker Is Unavailable

Verify:

```bash
docker --version
docker compose version
docker info
```

Docker installation is a host prerequisite and is not performed by this repository.

## `Unknown client name: Docker-agent`

The Jenkins node does not exist or its name does not match:

```env
JENKINS_AGENT_NAME=Docker-agent
```

Create the node using the documented settings and verify exact capitalization.

## Authorization Failure or Incorrect Agent Secret

Copy the current secret from:

```text
Manage Jenkins
-> Nodes
-> Docker-agent
-> Status
```

Update `.env`, then recreate the agent:

```bash
docker compose up -d --force-recreate jenkins-agent
```

A normal restart may continue using the previous environment value.

## Agent Is Offline

Check disk space:

```bash
df -h /
docker compose exec jenkins-agent df -h /tmp
```

Then check:

```text
Manage Jenkins
-> Nodes
-> Docker-agent
```

Bring the node online or wait for Jenkins to repeat its disk-space check.

## Jenkins Reports Low Disk Space

Check:

```bash
df -h /
```

Free space or increase the host disk size.

After increasing the filesystem:

```bash
docker compose restart jenkins-agent
docker compose exec jenkins-agent df -h /tmp
```

## First Seed Build Requires Script Approval

Open:

```text
Manage Jenkins
-> In-process Script Approval
```

Approve the pending script and rerun the seed job.

## GitHub API Returns `403 Forbidden`

Verify:

- the token has not expired;
- the token has not been revoked;
- the token has read access to the organization;
- the credential ID is exactly `github-read-token`;
- fine-grained access was approved by the organization when required.

Update the credential under:

```text
Manage Jenkins
-> Credentials
-> System
-> Global credentials
```

## Git Tool Warning

Jenkins may display:

```text
Selected Git installation does not exist. Using Default
The recommended git tool is: NONE
```

This warning is harmless when checkout continues successfully.

# Failure Handling

- Discovery failure prevents Job DSL execution.
- Existing generated jobs remain available after discovery failure.
- Incomplete inventory data is not promoted.
- Failed tests prevent both build and push.
- Registry push failure marks the repository pipeline failed.
- Builds remain queued while the `docker` agent is offline.

# Security Decisions

- The Jenkins controller has zero executors.
- Repository workloads run only on the dedicated agent.
- The controller does not mount the Docker socket.
- Only the agent mounts `/var/run/docker.sock`.
- The GitHub token is read-only and stored in Jenkins Credentials.
- The token is injected only during discovery.
- Jenkins masks the token in console logs.
- `.env` is ignored by Git.
- The local registry is intended only for controlled local evaluation.

The Docker socket gives the agent substantial control over the host Docker daemon. This is an explicit trade-off for a simple local evaluation environment.

# Assumptions

- repositories use a root-level `Dockerfile`;
- optional tests use a root-level `test.sh`;
- `test.sh` is compatible with `/bin/sh`;
- exit code `0` means success;
- any nonzero exit code means failure;
- each repository's default branch is built;
- repositories are cloned through HTTPS;
- Docker is available through the host socket;
- the registry is reachable at `localhost:5000`;
- the environment is local or controlled.

# Trade-Offs

## Host Docker Socket

Chosen for simple setup, fast builds, and host cache reuse.

Trade-off: the Jenkins agent receives host-level Docker privileges.

Production alternatives include:

- rootless BuildKit;
- Kaniko;
- ephemeral Kubernetes agents;
- isolated virtual machines.

## Permanent Jenkins Agent

Chosen for simple local operation and troubleshooting.

Trade-off: less isolation than short-lived build workers.

## Local Registry

Chosen for reproducibility and easy inspection.

A production registry should provide:

- TLS;
- authentication;
- retention policies;
- vulnerability scanning;
- image signing.

## Jenkins Job DSL

Chosen for readable, repeatable, and idempotent job generation.

Trade-off: the first execution may require administrator approval.

# Improvements With More Time

- automate inbound-agent registration;
- securely transfer the Jenkins-generated agent secret;
- automate GitHub credential provisioning from an external secret source;
- make Job DSL fully sandbox-compatible;
- use GitHub App authentication;
- add webhook triggers;
- use ephemeral build agents;
- add registry TLS and authentication;
- add image vulnerability scanning;
- generate software bills of materials;
- add image signing and provenance;
- remove obsolete generated jobs automatically;
- support configurable Dockerfile and test paths.

# Restarting

After restarting the same host:

```bash
cd Txstate-DevOps-Assignment
./scripts/bootstrap.sh
./scripts/verify.sh
```

Jenkins jobs, credentials, build history, and registry images persist through Docker volumes.

# Stopping

Stop containers while preserving data:

```bash
docker compose down
```

Remove containers and all persistent project data:

```bash
docker compose down -v
```

Warning: `docker compose down -v` permanently removes Jenkins jobs, credentials, build history, and registry images.

# AI-Assisted Development

AI tools assisted with drafting, troubleshooting, and documentation review. All implementation choices were reviewed and validated against the running environment.
