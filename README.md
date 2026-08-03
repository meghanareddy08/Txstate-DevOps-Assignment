# GitHub Organization Jenkins Pipeline Factory

This project runs Jenkins and a local Docker Registry using Docker Compose.

Given a GitHub organization, it:

- discovers all repositories
- checks each repository for a root-level `Dockerfile`
- creates or updates one Jenkins pipeline per qualifying repository
- runs a root-level `test.sh` when present
- stops the pipeline when a test fails
- builds and pushes successful images to the local registry

The Jenkins controller has zero executors. Discovery, testing, Docker builds, and registry pushes run on a dedicated Jenkins agent labeled `docker`.

## Demonstrated Results

The workflow was tested against:

```text
meghana-devops-test
```

| Repository | Dockerfile | test.sh | Result |
|---|---|---|---|
| `catalog-service` | Yes | Passes | Image built and pushed |
| `notification-service` | Yes | Missing | Image built and pushed |
| `payment-service` | Yes | Fails | Build and push blocked |
| `platform-documentation` | No | N/A | No Jenkins job created |

Final result:

- Repositories discovered: 4
- Generated Jenkins jobs: 3
- Successful images published: 2
- Expected failed pipelines: 1

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
Jenkins Job DSL
        |
        v
Generated Repository Pipelines
        |
        v
Optional test.sh
        |
        v
Docker Build
        |
        v
Local Docker Registry
```

## Components

| Component | Purpose |
|---|---|
| Jenkins controller | Orchestrates the seed and generated jobs |
| Jenkins agent | Runs discovery, tests, Docker builds, and registry pushes |
| Discovery script | Enumerates repositories and checks repository files |
| Job DSL | Creates repository-specific Jenkins jobs |
| Repository pipeline | Applies test, build, and push logic |
| Local registry | Stores successful Docker images |
| `bootstrap.sh` | Starts and validates the environment |
| `run-demo.sh` | Runs the complete demonstration |
| `verify.sh` | Checks Jenkins, Compose, agent, and registry status |

# Reviewer Setup

These instructions work on either:

- a local Linux machine
- a remote Linux host such as an Ubuntu EC2 instance

## 1. Prerequisites

The host must have:

- Linux
- Git
- Docker Engine
- Docker Compose v2
- `curl`
- `jq`
- internet access to GitHub and Docker Hub
- a GitHub token with read access to the target repositories

Verify:

```bash
git --version
docker --version
docker compose version
curl --version
jq --version
```

Recommended minimum resources:

- CPU: 2 vCPUs
- Memory: 4 GB
- Disk: 20 GB

A machine with 2 vCPUs and 8 GB memory is recommended for smoother Docker builds.

Jenkins images, plugins, workspaces, and Docker build layers may exceed the default disk size of a small virtual machine.

Check available disk space:

```bash
df -h /
```

Several GB of free space should remain before running the complete demonstration.

## 2. Clone the Repository

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

## 3. Create the Environment File

Copy the example file:

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
JENKINS_AGENT_SECRET=replace-with-the-generated-agent-secret

JENKINS_URL=http://jenkins-controller:8080
```

Important:

- `JENKINS_ADMIN_PASSWORD` is the password used to sign in to Jenkins.
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

- `git check-ignore .env` prints `.env`
- `git ls-files .env` prints nothing

## 4. Start Jenkins and the Registry

Run:

```bash
./scripts/bootstrap.sh
```

On the first run, the script:

- validates prerequisites
- builds and starts the Jenkins controller
- starts the local Docker registry
- waits for Jenkins readiness
- creates the seed job through Jenkins Configuration as Code
- prints the remaining one-time setup steps

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

On a fresh installation, the Jenkins agent cannot connect until the Jenkins node has been created and its generated secret has been added to `.env`.

The agent may be stopped safely until registration is complete:

```bash
docker compose stop jenkins-agent 2>/dev/null || true
```

Direct startup of only Jenkins and the registry is also available:

```bash
docker compose up -d --build jenkins-controller registry
```

## 5. Open Jenkins

### Local Linux Host

Open:

```text
http://localhost:8080
```

### Remote Host or EC2

From the reviewer's local computer, create an SSH tunnel:

```bash
ssh -i /path/to/key.pem \
  -L 8080:localhost:8080 \
  ubuntu@HOST_PUBLIC_IP
```

Keep the SSH session open.

Then open:

```text
http://localhost:8080
```

Log in using:

```text
Username: value of JENKINS_ADMIN_USER
Password: value of JENKINS_ADMIN_PASSWORD
```

# One-Time Jenkins Configuration

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

In Jenkins, open:

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

Jenkins displays an agent launch command containing:

```text
-secret <generated-secret>
```

Copy only the long value shown after `-secret`.

Update `.env` on the host:

```bash
nano .env
```

Replace:

```env
JENKINS_AGENT_SECRET=replace-with-the-generated-agent-secret
```

with:

```env
JENKINS_AGENT_SECRET=the-generated-secret
```

The node name is case-sensitive and must match exactly:

```env
JENKINS_AGENT_NAME=Docker-agent
```

Recreate the agent container so it receives the new environment values:

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

Confirm the agent is online:

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

In Jenkins, open:

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

The token is stored only in Jenkins Credentials.

Do not add the token to:

- `.env`
- Git
- screenshots
- shell history
- README files

## 4. Run the Initial Seed Build

Before running the complete demonstration, trigger the seed job once.

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

On a completely new Jenkins installation, the first seed build may fail with:

```text
ERROR: script not yet approved for use
```

This is expected on the first clean installation.

Open:

```text
Manage Jenkins
-> In-process Script Approval
```

Approve the pending Job DSL script.

Then return to:

```text
github-organization-seed
-> Build with Parameters
```

Set:

```text
GITHUB_ORG=meghana-devops-test
```

Run the seed job again.

Expected result:

```text
Finished: SUCCESS
```

The following three jobs should be created under the `repository-builds` folder:

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

After all of the following are complete:

- Jenkins is running
- `Docker-agent` is connected
- the `github-read-token` credential exists
- the Job DSL script has been approved

run:

```bash
./scripts/run-demo.sh
```

The script:

- triggers the organization seed pipeline
- supplies `meghana-devops-test` as the organization
- waits for repository jobs to be generated
- runs the catalog, notification, and payment pipelines
- checks expected success and failure results
- validates registry contents

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

This confirms that a failed test prevents both the Docker build and the registry push.

# Verification

Run:

```bash
./scripts/verify.sh
```

Check registry contents:

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

The `payment-service` image must be absent because its test failed.

Confirm that the repository remains clean:

```bash
git status
```

Expected:

```text
nothing to commit, working tree clean
```

# Run Against Another GitHub Organization

Open:

```text
github-organization-seed
-> Build with Parameters
```

Set:

```text
GITHUB_ORG=<organization-name>
```

The token stored as `github-read-token` must have read access to the selected organization and its repositories.

The seed pipeline will:

- enumerate repositories
- detect root-level `Dockerfile` and `test.sh` files
- create or update Jenkins jobs for qualifying repositories

A repository qualifies when:

- a root-level `Dockerfile` exists
- the repository is not archived

The root-level `test.sh` file is optional.

| Dockerfile | test.sh | Pipeline behavior |
|---|---|---|
| Present | Passes | Build and push |
| Present | Fails | Stop before build |
| Present | Missing | Build and push |
| Missing | Any | No Jenkins job |
| Present | Any | No job when archived |

# Image Naming

Successful images are pushed to:

```text
localhost:5000/<organization>/<repository>:<tag>
```

Each successful build creates:

- a Git commit SHA tag
- a Jenkins build-number tag

Example:

```text
localhost:5000/meghana-devops-test/catalog-service:b82dd8257769
localhost:5000/meghana-devops-test/catalog-service:build-3
```

A mutable `latest` tag is intentionally not used.

# Troubleshooting

## Required Command Not Found: Docker

The host does not have Docker installed or the current user cannot access it.

Verify:

```bash
docker --version
docker compose version
docker info
```

Docker installation is a host prerequisite and is not performed by this repository.

## `Unknown client name: Docker-agent`

The Jenkins node has not been created, or the node name does not match:

```env
JENKINS_AGENT_NAME=Docker-agent
```

Create the Jenkins node using the instructions above and verify the exact capitalization.

## `Authorization failure` or `incorrect secret`

The secret in `.env` does not match the secret generated for the Jenkins node.

Copy the current secret from:

```text
Manage Jenkins
-> Nodes
-> Docker-agent
-> Status
```

Update `.env`, then recreate the agent container:

```bash
docker compose up -d --force-recreate jenkins-agent
```

A normal container restart may continue using the previous environment value.

## Agent Is Connected but Remains Offline

Check host and container disk space:

```bash
df -h /
docker compose exec jenkins-agent df -h /tmp
```

If disk space is healthy, open:

```text
Manage Jenkins
-> Nodes
-> Docker-agent
```

Bring the node back online or wait for Jenkins to repeat its disk-space check.

## Jenkins Reports Low Disk Space

Check:

```bash
df -h /
```

Free unused files or increase the host disk size.

A 20 GB disk is recommended for the complete demonstration.

After increasing the host filesystem, restart the agent:

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

Approve the pending script and run the seed job again.

## GitHub API Returns `403 Forbidden`

Verify:

- the token has not expired
- the token has not been revoked
- the token has read access to the target organization
- the credential ID is exactly `github-read-token`
- fine-grained token access has been approved by the organization if required

Update the credential under:

```text
Manage Jenkins
-> Credentials
-> System
-> Global credentials
```

## Selected Git Installation Does Not Exist

Jenkins may display:

```text
Selected Git installation does not exist. Using Default
The recommended git tool is: NONE
```

This warning is harmless when the checkout continues and Jenkins displays the installed Git version.

# Failure Handling

The implementation handles:

- invalid or expired GitHub credentials
- unknown or inaccessible organizations
- temporary GitHub API errors
- missing Dockerfiles after discovery
- failed test scripts
- unavailable registry
- offline Jenkins agents

Temporary GitHub API errors such as `429`, `500`, `502`, `503`, and `504` are retried with exponential backoff.

If discovery fails:

- Job DSL does not run
- existing generated jobs remain available
- incomplete inventory data is not saved

If `test.sh` fails:

- Docker build is skipped
- registry push is skipped
- Jenkins reports failure

# Security Decisions

- The Jenkins controller has zero executors.
- Repository workloads run only on the dedicated build agent.
- The GitHub token is read-only.
- The token is stored in Jenkins Credentials.
- The token is injected only during discovery.
- Jenkins masks the token in console logs.
- `.env` is ignored by Git.
- Only the Jenkins agent mounts `/var/run/docker.sock`.
- The registry is intended for local evaluation and should not be exposed publicly.

The Docker socket gives the build agent control over the host Docker daemon.

This is an explicit trade-off for a controlled local evaluation environment.

# Assumptions

- repositories use a root-level `Dockerfile`
- optional tests use a root-level `test.sh`
- `test.sh` is compatible with `/bin/sh`
- exit code `0` means success
- any nonzero exit code means failure
- the GitHub default branch is built
- repositories are cloned through HTTPS
- Docker is available through the host Docker socket
- the registry is reachable at `localhost:5000`
- the environment is local or otherwise controlled

# Trade-Offs

## Host Docker Socket

Chosen for simple setup and fast Docker builds.

Trade-off: the agent has host-level Docker privileges.

Production alternatives include:

- rootless BuildKit
- Kaniko
- ephemeral Kubernetes agents
- isolated virtual machines

## Permanent Jenkins Agent

Chosen for simple local operation and troubleshooting.

A production system should use short-lived, isolated agents.

## Local Registry

Chosen for reproducibility and easy inspection.

A production registry should include:

- TLS
- authentication
- retention policies
- vulnerability scanning
- image signing

## Jenkins Job DSL

Chosen for readable, repeatable, and idempotent job generation.

The first run may require script approval.

# Improvements With More Time

- automate inbound-agent registration
- use external secret management
- use GitHub App authentication
- add GitHub webhook triggers
- use ephemeral build agents
- add registry TLS and authentication
- add image vulnerability scanning
- generate software bills of materials
- add image signing and provenance
- remove obsolete generated jobs automatically
- support configurable Dockerfile and test paths

# Evidence

## Automated End-to-End Demo

![Automated demo](docs/images/automated-demo-success.png)

## Seed Pipeline Success

![Seed pipeline success](docs/images/seed-pipeline-success.png)

## Generated Repository Jobs

![Generated repository jobs](docs/images/generated-repository-jobs.png)

## Catalog Service Success

![Catalog service success](docs/images/catalog-service-success.png)

## Payment Service Test Gate

![Payment service test gate](docs/images/payment-service-test-gate.png)

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

Generative AI was used for architecture review, configuration drafting, troubleshooting, documentation organization, and security review.

All suggestions were reviewed, corrected where necessary, and tested against the running environment.
