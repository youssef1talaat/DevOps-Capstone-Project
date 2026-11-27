# DevOps Capstone: Node.js Task API on AWS EKS

An end-to-end DevOps project that containerizes a Node.js REST API,
provisions AWS infrastructure with Terraform, and deploys the
application to Amazon EKS through GitHub Actions.

The delivery pipeline uses GitHub OpenID Connect (OIDC) for short-lived
AWS credentials, Amazon ECR for container images, and Kubernetes rolling
updates for application releases.

## Project overview

The project demonstrates an automated path from source control to a
running application:

1.  A developer pushes application or Kubernetes changes to `main`.
2.  GitHub Actions runs unit tests and Dockerfile linting.
3.  The pipeline builds a container image, performs security checks, and
    pushes it to Amazon ECR.
4.  The deployment job updates the Kubernetes Deployment in Amazon EKS.
5.  Kubernetes performs a rolling update and the workflow runs a
    load-balancer smoke test.

Infrastructure is managed separately through a Terraform workflow. Pull
requests trigger formatting, validation, and a Terraform plan; changes
merged to `main` can proceed to the apply stage through the
`infrastructure` GitHub Environment.

## Architecture

``` mermaid
flowchart TB
    Dev[Developer] -->|push / pull request| GitHub[GitHub repository]

    subgraph Actions[GitHub Actions]
      TF[Terraform workflow<br/>fmt · validate · plan · apply]
      CI[Application workflow<br/>test · lint · build · scan · push · deploy]
    end

    GitHub --> TF
    GitHub --> CI

    TF -->|GitHub OIDC| TerraformRole[AWS Terraform IAM role]
    CI -->|GitHub OIDC| DeployRole[AWS deployment IAM role]

    subgraph AWS[AWS account · us-east-1]
      S3[(S3 Terraform state<br/>versioning · encryption)]
      ECR[(Amazon ECR<br/>immutable image tags)]

      subgraph VPC[VPC · 10.0.0.0/16 · two Availability Zones]
        Public[Public subnets<br/>internet-facing load balancer]
        Private[Private subnets<br/>EKS worker nodes]
        NAT[NAT Gateway]
        subgraph EKS[Amazon EKS · capstone-dev]
          P1[task-api pod]
          P2[task-api pod]
        end
      end
    end

    TerraformRole --> S3
    TerraformRole --> VPC
    DeployRole --> ECR
    DeployRole --> EKS
    CI -->|push image| ECR
    ECR -->|pull image| P1
    ECR -->|pull image| P2
    Users[API clients] -->|HTTP| Public
    Public --> P1
    Public --> P2
    Private --> NAT
```

### Main components

  -----------------------------------------------------------------------
  Layer                   Technology              Purpose
  ----------------------- ----------------------- -----------------------
  Application             Node.js 24, Express 5   REST API and task CRUD
                                                  endpoints

  Tests                   Node.js `node:test`     Automated application
                                                  tests

  Container               Docker,                 Multi-stage production
                          `node:24-alpine`        image

  Image quality           Hadolint, Trivy         Dockerfile linting and
                                                  vulnerability scanning

  Infrastructure as Code  Terraform               Repeatable AWS
                                                  provisioning

  Cloud                   AWS VPC, IAM, S3, ECR,  Networking, identity,
                          EKS                     state, registry,
                                                  Kubernetes

  Orchestration           Kubernetes              Deployment, Service,
                                                  ConfigMap, probes,
                                                  rolling updates

  CI/CD                   GitHub Actions          Automated validation,
                                                  image publishing, and
                                                  deployment

  Observability endpoints `/healthz`, `/readyz`,  Health, readiness, and
                          `/metrics`              Prometheus metrics
  -----------------------------------------------------------------------

## Repository structure

``` text
.
├── app/
│   ├── src/
│   │   ├── app.js
│   │   └── server.js
│   ├── test/
│   │   └── app.test.js
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── package.json
│   └── package-lock.json
├── terraform/
│   ├── bootstrap/          # S3 state bucket, GitHub OIDC, IAM roles
│   └── infra/              # VPC, ECR, EKS, access entries
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-deployment.yaml
│   ├── 03-service.yaml
│   └── optional/
│       └── hpa.yaml
└── .github/
    └── workflows/
        ├── terraform.yml
        └── app-cicd.yml
```

## AWS infrastructure

The Terraform infrastructure stack provisions the following resources in
`us-east-1`.

  -----------------------------------------------------------------------
  Resource                            Configuration
  ----------------------------------- -----------------------------------
  VPC                                 `10.0.0.0/16`

  Availability Zones                  2

  Public subnets                      2, tagged for internet-facing
                                      Kubernetes load balancers

  Private subnets                     2, tagged for internal Kubernetes
                                      load balancers

  NAT Gateway                         1 shared NAT Gateway for outbound
                                      connectivity

  EKS cluster                         `capstone-dev`

  Kubernetes version                  `1.36`

  Managed node group                  2 desired On-Demand `t3.small`
                                      instances

  Node group scaling bounds           Minimum 1, desired 2, maximum 3

  ECR repository                      `capstone-dev-task-api`

  ECR tag mutability                  Immutable

  ECR image scanning                  Scan on push enabled

  ECR lifecycle                       Retain the latest 15 images
  -----------------------------------------------------------------------

The EKS control plane uses private subnets for its worker nodes. The
public subnets are tagged with `kubernetes.io/role/elb` and the private
subnets with `kubernetes.io/role/internal-elb`, allowing Kubernetes/AWS
load-balancer integrations to identify suitable subnets.

A single NAT Gateway is used as a cost-saving choice for this learning
project. It is not as resilient as deploying a NAT Gateway in each
Availability Zone.

### EKS access

The cluster uses the EKS API access-entry mechanism with
`API_AND_CONFIG_MAP` authentication mode. The GitHub deployment role and
configured administrator IAM principals receive EKS access policies
through Terraform-managed access entries.

To configure local `kubectl` access for an authorized IAM principal:

``` bash
aws eks update-kubeconfig --region us-east-1 --name capstone-dev
kubectl get nodes
```

## Terraform bootstrap and GitHub OIDC

The bootstrap stack is run once using an AWS identity with the
permissions required to create the initial resources. It creates:

-   An S3 bucket for the infrastructure Terraform state.
-   S3 versioning, server-side encryption, and public-access blocking.
-   The GitHub Actions OIDC identity provider.
-   A Terraform IAM role.
-   An application deployment IAM role.

The infrastructure stack uses the S3 backend with native S3 state
locking. The bootstrap stack maintains its own local state file in
`terraform/bootstrap/terraform.tfstate`; protect this file because it is
needed to manage or remove the bootstrap resources.

### IAM role separation

  -----------------------------------------------------------------------------
  Role                          Responsibility          Permissions
  ----------------------------- ----------------------- -----------------------
  `capstone-github-terraform`   Infrastructure pipeline Currently attached to
                                                        AWS
                                                        `AdministratorAccess`

  `capstone-github-deploy`      Application pipeline    ECR image push
                                                        permissions and EKS
                                                        cluster description;
                                                        Kubernetes permissions
                                                        are granted separately
                                                        through an EKS access
                                                        entry
  -----------------------------------------------------------------------------

GitHub Actions requests an OIDC token and exchanges it with AWS STS for
temporary credentials. The trust policies validate the token audience
and restrict the subject claim to the configured GitHub repository
identity and approved execution contexts. The repository identity
includes immutable GitHub owner and repository IDs.

No long-lived AWS access keys are required in GitHub repository secrets.

**Security note:** The Terraform role currently uses
`AdministratorAccess` as a course/project simplification. A production
implementation should replace it with narrowly scoped permissions and
consider a separate read-only planning role. The EKS API endpoint is
publicly reachable; production should restrict the allowed source CIDRs
where practical.

### GitHub Actions repository variables

The workflows use repository variables for non-secret configuration. The
bootstrap outputs provide the following values:

  -----------------------------------------------------------------------
  Variable                            Purpose
  ----------------------------------- -----------------------------------
  `AWS_REGION`                        AWS deployment region

  `TF_STATE_BUCKET`                   S3 bucket used by the Terraform
                                      backend

  `AWS_TERRAFORM_ROLE_ARN`            OIDC role assumed by the Terraform
                                      workflow

  `AWS_DEPLOY_ROLE_ARN`               OIDC role assumed by the
                                      application workflow

  `EKS_CLUSTER_NAME`                  Target EKS cluster

  `ECR_REPOSITORY`                    Target ECR repository

  `ADMIN_PRINCIPAL_ARNS`              JSON list of additional IAM
                                      principals granted cluster
                                      administrator access
  -----------------------------------------------------------------------

The Terraform apply job uses the `infrastructure` GitHub Environment.
The application deployment job uses the `production` environment.
Configure environment protection rules and required reviewers in GitHub
repository settings if approval gates are required.

## Container image

The application image is built from `app/Dockerfile` using a multi-stage
build:

-   Both stages use the official `node:24-alpine` base image.
-   The dependency stage copies package manifests first and runs
    `npm ci --omit=dev`.
-   The production stage copies only the installed production
    dependencies and application source.
-   The container runs as UID/GID `1000:1000`, not as root.
-   The image exposes port `3000`.
-   The container uses exec-form `CMD` to launch Node directly and
    support graceful signal handling.
-   A Docker `HEALTHCHECK` probes `/healthz`.

The `.dockerignore` excludes dependencies, tests, Git metadata,
environment files, and other unnecessary build-context content.

The Kubernetes Deployment further enforces a non-root user, a read-only
root filesystem, disabled privilege escalation, dropped Linux
capabilities, and the RuntimeDefault seccomp profile.

## CI/CD workflows

### Terraform workflow --- `.github/workflows/terraform.yml`

The infrastructure workflow is triggered by relevant pull requests and
pushes to `main`, and supports manual workflow dispatch.

The plan stage: 1. Configures Terraform. 2. Authenticates to AWS using
GitHub OIDC. 3. Runs recursive formatting checks and Terraform
validation. 4. Initializes the S3 backend. 5. Creates a Terraform plan
and publishes it in the GitHub Actions job summary.

The apply stage runs for eligible pushes to `main` or an explicitly
selected manual apply action. It uses the saved plan artifact and the
`infrastructure` GitHub Environment.

A workflow concurrency group prevents overlapping Terraform workflow
runs.

### Application workflow --- `.github/workflows/app-cicd.yml`

For pull requests affecting the application, Kubernetes manifests, or
the workflow, the pipeline runs tests and Dockerfile linting. Pushes to
`main` and manual dispatch can run the deployment stages.

  -----------------------------------------------------------------------
  Job                                 Main actions
  ----------------------------------- -----------------------------------
  `test`                              Install dependencies with `npm ci`
                                      and run `npm test`

  `lint-docker`                       Run Hadolint against the Dockerfile

  `build-push`                        Build the image, run a container
                                      smoke test, verify the configured
                                      non-root user, scan with Trivy, and
                                      push to ECR

  `deploy`                            Authenticate to AWS, update
                                      kubeconfig, apply Kubernetes
                                      manifests, wait for rollout, and
                                      check the service through its load
                                      balancer
  -----------------------------------------------------------------------

Images are tagged with the full Git commit SHA. The ECR repository uses
immutable tags, so a commit tag cannot silently be overwritten by
another image.

The deployment job substitutes the image and application version
placeholders in the Kubernetes Deployment manifest. It waits for the
rollout and attempts `kubectl rollout undo` if the rollout fails. The
job summary reports the service URL and deployment details.

## Kubernetes deployment

The application is deployed into the `task-api` namespace.

  Resource                   Configuration
  -------------------------- -----------------------------------------------------------
  Namespace                  `task-api`
  ConfigMap                  `task-api-config`
  Deployment                 `task-api`, 2 replicas
  Service                    `LoadBalancer`, port 80 forwarding to container port 3000
  Update strategy            RollingUpdate, `maxSurge: 1`, `maxUnavailable: 0`
  Revision history           5 revisions
  Termination grace period   30 seconds

The Deployment defines CPU and memory requests, a memory limit, and HTTP
liveness/readiness probes. The readiness probe checks `/readyz`; the
liveness probe checks `/healthz`.

Useful operational commands:

``` bash
kubectl get all -n task-api
kubectl get pods -n task-api -o wide
kubectl get svc task-api -n task-api
kubectl rollout status deployment/task-api -n task-api
kubectl describe deployment task-api -n task-api
kubectl logs deployment/task-api -n task-api
```

## Application API

The Express application exposes the following endpoints:

  -----------------------------------------------------------------------
  Method                  Endpoint                Purpose
  ----------------------- ----------------------- -----------------------
  `GET`                   `/`                     Service name, version,
                                                  environment, hostname,
                                                  and welcome message

  `GET`                   `/healthz`              Liveness check

  `GET`                   `/readyz`               Readiness check

  `GET`                   `/metrics`              Prometheus metrics

  `GET`                   `/api/tasks`            List tasks

  `POST`                  `/api/tasks`            Create a task

  `GET`                   `/api/tasks/:id`        Retrieve a task

  `PATCH`                 `/api/tasks/:id`        Update a task

  `DELETE`                `/api/tasks/:id`        Delete a task
  -----------------------------------------------------------------------

The root endpoint includes the responding pod hostname. This is useful
for observing how requests are distributed across replicas.

Example requests:

``` bash
# Create a task
curl -X POST http://<LOAD_BALANCER_HOST>/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Verify EKS deployment"}'

# List tasks
curl http://<LOAD_BALANCER_HOST>/api/tasks

# Check application health
curl http://<LOAD_BALANCER_HOST>/healthz
```

Replace `<LOAD_BALANCER_HOST>` with the external hostname shown by
`kubectl get svc task-api -n task-api`.

## Validation and test results

The following checks have been run during project validation:

-   Application unit test suite: 5 tests passed.
-   Dockerfile Hadolint check: passed in CI.
-   Application CI/CD workflow: successful test, lint, build/scan/push,
    and EKS deployment jobs.
-   Terraform apply workflow: successful infrastructure apply.
-   EKS worker nodes: 2 nodes reported `Ready`.
-   Application Deployment: 2 of 2 replicas ready.
-   Application health and readiness endpoints: HTTP 200.
-   Live task API checks against a single pod: create, list, retrieve,
    update, delete, and invalid-input validation were exercised.

The application deployment was validated at the following load-balancer
endpoint at the time of testing:

`http://a5df68dfed15c405aa9cfe5ed514d89b-1112971762.us-east-1.elb.amazonaws.com`

This is an environment-specific AWS endpoint and may change if the
Service or infrastructure is recreated.

## Known limitation: in-memory task storage

Tasks are currently stored in an in-memory JavaScript `Map` within each
application process. Each pod therefore has its own independent task
store.

Because the Kubernetes Service distributes requests across replicas, a
task created through one pod may not be visible when a later request
reaches another pod. Pod restarts also erase that pod's in-memory data.

This is an intentional limitation of the sample application, not a
Kubernetes persistence mechanism. A production design should use shared
durable storage, such as a managed relational database or another
appropriate shared data store, rather than relying on process memory.

## Local development

Requirements:

-   Node.js 24
-   npm
-   Docker (for container build and run)
-   AWS CLI v2, Terraform, and `kubectl` (for cloud operations)

Run the application tests:

``` bash
cd app
npm ci
npm test
```

Start the application locally:

``` bash
npm start
```

Build and run the container:

``` bash
docker build -t task-api:local ./app
docker run --rm -p 3000:3000 --read-only task-api:local
```

In another terminal:

``` bash
curl http://localhost:3000/healthz
curl http://localhost:3000/readyz
```

Stop the container with `Ctrl+C` or `docker stop` when finished.

## Deployment and operations

For an existing provisioned environment, the normal application release
process is to merge the intended application or Kubernetes changes into
`main` and monitor the **App CI/CD** workflow in GitHub Actions.

To connect to the existing cluster locally:

``` bash
aws eks update-kubeconfig --region us-east-1 --name capstone-dev
kubectl get nodes
kubectl get all -n task-api
```

Infrastructure changes should be made through the Terraform workflow
rather than by making untracked manual changes in the AWS console.

## Teardown

AWS resources can continue to incur charges while they exist. Remove the
application-created load balancer before destroying the VPC and its
subnets.

For a full environment teardown:

1.  Remove the Kubernetes resources and wait for the external load
    balancer to be deleted:

    ``` bash
    kubectl delete -f k8s/
    kubectl get svc -n task-api
    ```

2.  Run the Terraform infrastructure workflow manually with the
    `destroy` action and complete any configured environment approval.

3.  Only when the environment is no longer needed, destroy the bootstrap
    resources from the bootstrap directory using the same AWS account
    and region:

    ``` bash
    cd terraform/bootstrap
    terraform destroy
    ```

Keep the bootstrap state file until the bootstrap destroy has completed
successfully. Verify that the EKS cluster, node group, NAT Gateway, load
balancer, and other billable resources have been removed.

## Project evidence and submission checklist

Capture evidence from the actual runs and environment before teardown:

-   [ ] Terraform plan on a pull request.
-   [ ] Successful Terraform apply and approval evidence, if environment
    protection is configured.
-   [ ] Successful App CI/CD run with the job summary and deployed URL.
-   [ ] `kubectl get all -n task-api`.
-   [ ] Application responding through the load-balancer endpoint.
-   [ ] Evidence for the required exercise demonstrating automatic
    rollback.
-   [ ] Report explaining the Dockerfile, final image size, end-to-end
    push-to-pod flow, and a production improvement.
-   [ ] Successful infrastructure destroy run and proof that resources
    were removed.

The five assignment exercises are useful validation scenarios: ship a
change, deliberately trigger a failed rollout and observe rollback,
verify the Dockerfile quality gate, scale replicas and observe the
effect of per-pod memory, and delete a pod to observe Kubernetes
self-healing. Record evidence for each exercise before marking it
complete.

## Production improvements

Before using this design for a production workload, consider:

1.  Replace in-memory task storage with a shared, durable database.
2.  Replace the Terraform role's broad `AdministratorAccess` policy with
    least-privilege permissions.
3.  Restrict public EKS API access to trusted CIDR ranges or use a
    private endpoint design.
4.  Deploy a NAT Gateway per Availability Zone for higher network
    availability.
5.  Add centralized logs, metrics, alerting, and dashboards.
6.  Pin GitHub Actions to immutable commit SHAs and add automated
    dependency updates.
7.  Add backup, recovery, and database migration procedures.

## Troubleshooting

  -----------------------------------------------------------------------------------------------
  Symptom                                                     Things to check
  ----------------------------------------------------------- -----------------------------------
  `Not authorized to perform sts:AssumeRoleWithWebIdentity`   Check the GitHub OIDC provider,
                                                              repository identity, trust-policy
                                                              subject, workflow permissions, and
                                                              GitHub Environment name.

  `kubectl` reports an authorization or credential error      Confirm the active AWS identity and
                                                              that it has an EKS access entry.
                                                              Refresh kubeconfig.

  `ImagePullBackOff`                                          Check that the image was pushed to
                                                              the expected ECR repository and
                                                              that the Deployment uses the
                                                              correct commit SHA tag.

  `CrashLoopBackOff`                                          Inspect `kubectl logs` and
                                                              `kubectl describe pod`; check
                                                              startup configuration and container
                                                              filesystem permissions.

  `CreateContainerConfigError` or non-root errors             Verify the image runs as UID 1000
                                                              and the pod security context
                                                              matches the image.

  Rollout does not complete                                   Inspect pod readiness, events,
                                                              image availability, and the
                                                              readiness/liveness endpoints.

  Load balancer is not available                              Check the Service, subnet tags, AWS
                                                              load-balancer provisioning events,
                                                              and target health.

  Terraform destroy is blocked by networking resources        Ensure the Kubernetes LoadBalancer
                                                              Service has been deleted and its
                                                              AWS load balancer has finished
                                                              deleting before destroying the VPC.
  -----------------------------------------------------------------------------------------------

------------------------------------------------------------------------

**Project:** DevOps Capstone --- Node.js Task API on Amazon EKS\
**AWS Region:** `us-east-1`\
**EKS Cluster:** `capstone-dev`\
**ECR Repository:** `capstone-dev-task-api`
