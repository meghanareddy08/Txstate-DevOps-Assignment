# Architecture

This document describes the technical flow and component boundaries of the GitHub Organization Jenkins Pipeline Factory.

For installation, configuration, and reviewer instructions, see the main [README](../README.md).

## System Architecture

```mermaid
flowchart TD
    USER[Reviewer or Platform Engineer]

    GH[GitHub Organization]

    SEED[Jenkins Seed Pipeline<br/>pipelines/seed.Jenkinsfile]

    DISCOVERY[Repository Discovery<br/>discover_repositories.py]

    INVENTORY[(Repository Inventory<br/>repositories.json)]

    DSL[Jenkins Job DSL<br/>jobs/seed_job.groovy]

    JOBS[Generated Repository Pipelines]

    AGENT[Dedicated Jenkins Agent<br/>Label: docker]

    DOCKER[Host Docker Daemon<br/>/var/run/docker.sock]

    REGISTRY[(Local Registry<br/>localhost:5000)]

    USER -->|Supplies GITHUB_ORG| SEED
    SEED -->|GitHub REST API| GH
    GH --> DISCOVERY
    DISCOVERY --> INVENTORY
    INVENTORY --> DSL
    DSL --> JOBS
    JOBS --> AGENT
    AGENT --> DOCKER
    DOCKER -->|Successful images| REGISTRY

    classDef github fill:#24292f,color:#ffffff,stroke:#57606a,stroke-width:2px;
    classDef jenkins fill:#d33833,color:#ffffff,stroke:#8b1e1a,stroke-width:2px;
    classDef discovery fill:#0969da,color:#ffffff,stroke:#0550ae,stroke-width:2px;
    classDef inventory fill:#8250df,color:#ffffff,stroke:#6639ba,stroke-width:2px;
    classDef runtime fill:#1f6feb,color:#ffffff,stroke:#0a3069,stroke-width:2px;

    class GH github;
    class SEED,DSL,JOBS jenkins;
    class DISCOVERY discovery;
    class INVENTORY inventory;
    class AGENT,DOCKER,REGISTRY runtime;
```

## Component Interaction

The Jenkins controller orchestrates the workflow and has zero executors.

The dedicated Jenkins agent performs:

```text
Repository checkout
Test execution
Docker image build
Registry push
```

The controller does not mount the Docker socket.

Only the build agent receives:

```text
/var/run/docker.sock
```

## Discovery and Job Generation

```mermaid
flowchart LR
    A[GitHub Organization] --> B[Enumerate Repositories]
    B --> C[Inspect Root Files]
    C --> D{Dockerfile Present?}
    D -->|Yes| E[Mark Buildable]
    D -->|No| F[Filter Repository]
    E --> G[Write repositories.json]
    G --> H[Run Job DSL]
    H --> I[Create or Update Pipeline Job]

    classDef success fill:#2da44e,color:#ffffff,stroke:#1a7f37,stroke-width:2px;
    classDef filtered fill:#6e7781,color:#ffffff,stroke:#424a53,stroke-width:2px;
    classDef process fill:#0969da,color:#ffffff,stroke:#0550ae,stroke-width:2px;

    class A,B,C,G,H,I process;
    class E success;
    class F filtered;
```

A repository is buildable when:

```text
Root-level Dockerfile exists
AND
Repository is not archived
```

The discovery inventory records:

```text
Repository name
Full repository name
Clone URL
Default branch
Archived state
Dockerfile presence
test.sh presence
Buildable state
```

The inventory is written atomically so a failed discovery run does not replace the last valid result with partial data.

## Repository Pipeline

Each generated job loads:

```text
pipelines/repository-build.Jenkinsfile
```

The execution flow is:

```mermaid
flowchart LR
    A[Checkout] --> B[Validate Dockerfile]
    B --> C{test.sh Present?}
    C -->|Yes| D[Run test.sh]
    C -->|No| E[Continue]
    D --> F{Exit Code 0?}
    F -->|Yes| E
    F -->|No| G[Stop Pipeline]
    E --> H[Prepare Image Tags]
    H --> I[Docker Build]
    I --> J[Push to Local Registry]

    classDef success fill:#2da44e,color:#ffffff,stroke:#1a7f37,stroke-width:2px;
    classDef failure fill:#cf222e,color:#ffffff,stroke:#a40e26,stroke-width:2px;
    classDef process fill:#0969da,color:#ffffff,stroke:#0550ae,stroke-width:2px;

    class A,B,C,D,F,H,I process;
    class E,J success;
    class G failure;
```

## Test-Gate Outcomes

### Passing Test

```mermaid
flowchart LR
    A[Dockerfile] --> B[test.sh]
    B --> C[Exit Code 0]
    C --> D[Build]
    D --> E[Push]
    E --> F[SUCCESS]

    classDef success fill:#2da44e,color:#ffffff,stroke:#1a7f37,stroke-width:2px;
    class A,B,C,D,E,F success;
```

### No Test Script

```mermaid
flowchart LR
    A[Dockerfile] --> B[No test.sh]
    B --> C[Build]
    C --> D[Push]
    D --> E[SUCCESS]

    classDef success fill:#2da44e,color:#ffffff,stroke:#1a7f37,stroke-width:2px;
    class A,B,C,D,E success;
```

### Failing Test

```mermaid
flowchart LR
    A[Dockerfile] --> B[test.sh]
    B --> C[Nonzero Exit]
    C --> D[Build Skipped]
    D --> E[Push Skipped]
    E --> F[EXPECTED FAILURE]

    classDef failure fill:#cf222e,color:#ffffff,stroke:#a40e26,stroke-width:2px;
    class A,B,C,D,E,F failure;
```

### Missing Dockerfile

```mermaid
flowchart LR
    A[Repository Discovered] --> B[No Root Dockerfile]
    B --> C[Not Buildable]
    C --> D[No Jenkins Job]

    classDef filtered fill:#6e7781,color:#ffffff,stroke:#424a53,stroke-width:2px;
    class A,B,C,D filtered;
```

## Image Publication Flow

Successful images are built by the host Docker daemon and pushed to:

```text
localhost:5000/<organization>/<repository>:<tag>
```

Each successful build produces:

```text
Git commit SHA tag
Jenkins build-number tag
```

Only pipelines that pass the test gate publish images.

## Security Boundaries

```mermaid
flowchart LR
    TOKEN[GitHub Read Token]

    CONTROLLER[Jenkins Controller<br/>Zero Executors]

    AGENT[Jenkins Agent<br/>Runs Repository Code]

    SOCKET[Host Docker Socket<br/>Privileged Boundary]

    REGISTRY[Local Registry]

    TOKEN -->|Injected during discovery| CONTROLLER
    CONTROLLER -->|Schedules work| AGENT
    AGENT --> SOCKET
    SOCKET --> REGISTRY

    classDef safe fill:#2da44e,color:#ffffff,stroke:#1a7f37,stroke-width:2px;
    classDef runtime fill:#0969da,color:#ffffff,stroke:#0550ae,stroke-width:2px;
    classDef sensitive fill:#cf222e,color:#ffffff,stroke:#a40e26,stroke-width:2px;

    class TOKEN,CONTROLLER safe;
    class AGENT,REGISTRY runtime;
    class SOCKET sensitive;
```

Security boundaries:

- The controller has zero executors.
- Repository code runs only on the dedicated agent.
- The GitHub token is read-only and stored in Jenkins Credentials.
- The token is injected only during repository discovery.
- The controller does not mount the Docker socket.
- The build agent has privileged access to the host Docker daemon.
- The registry is intended for local evaluation, not public exposure.

## Key Architecture Decisions

| Decision | Reason |
|---|---|
| Job DSL | Creates one visible, manageable pipeline per qualifying repository |
| Shared repository Jenkinsfile | Keeps generated jobs consistent and maintainable |
| Dedicated build agent | Separates repository execution from the controller |
| Host Docker socket | Simplifies local builds and reuses the host image cache |
| Local registry | Removes dependency on an external image registry |
| Atomic JSON inventory | Prevents failed discovery from replacing valid state |
| Git SHA and build-number tags | Provides source and Jenkins build traceability |

