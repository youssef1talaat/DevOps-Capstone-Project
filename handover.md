# DevOps Capstone Project — Handover

## 1. Project Overview

Node.js Task API deployed to AWS EKS using:
- Docker and a multi-stage Dockerfile
- Terraform for AWS infrastructure
- Amazon ECR for container images
- Amazon EKS for Kubernetes deployment
- GitHub Actions for CI/CD
- AWS IAM OIDC for GitHub Actions authentication

## 2. Current Deployment

- AWS Region: `us-east-1`
- EKS Cluster: `capstone-dev`
- ECR Repository: `capstone-dev-task-api`
- Kubernetes Namespace: `task-api`
- Application: 2 running replicas
- Kubernetes Worker Nodes: 2 Ready nodes
- Service: AWS LoadBalancer
- Application version: `258e936`

The application is currently deployed and responding through its LoadBalancer. The `/readyz` endpoint returns `{"status":"ready"}`.

## 3. Completed Work

- Terraform infrastructure provisioned successfully.
- EKS cluster and worker nodes running.
- ECR repository created.
- Docker image built and pushed through GitHub Actions.
- Application deployed to EKS through GitHub Actions.
- Application CI/CD pipeline completed successfully.
- Dockerfile quality checks passed.
- Application tests passed.
- Kubernetes resources and deployment verified.
- Application browser response and readiness verified.
- Evidence screenshots collected in the `evidence/` folder.

## 4. Remaining Work

The next contributor should review the original assignment requirements and complete or verify:

1. Exercise 1 — Verify the application change/deployment evidence.
2. Exercise 2 — Trigger a failed rollout and demonstrate automatic rollback.
3. Exercise 3 — Verify and document the Docker quality gate.
4. Exercise 4 — Scale application replicas and observe the effect.
5. Exercise 5 — Delete a pod and demonstrate Kubernetes self-healing.
6. Complete the project report and assignment answers.
7. Capture any missing evidence, including Terraform plan and exercise screenshots.
8. Perform the final Terraform teardown after all work is complete.

Do not mark an exercise complete until it has been tested and documented.

## 5. Repository Structure

- `app/` — Node.js application, tests and Dockerfile
- `k8s/` — Kubernetes manifests
- `terraform/` — AWS infrastructure and bootstrap configuration
- `.github/workflows/` — Terraform and application CI/CD workflows
- `evidence/` — Project screenshots
- `README.md` — Main project documentation

## 6. Important AWS Access Notice

The AWS infrastructure belongs to the original project owner's AWS account.

Cloning this repository does not grant AWS access.

Do not share AWS access keys, credentials, Terraform state files, or kubeconfig files. If cloud access is required, arrange a separate IAM identity and appropriate EKS permissions.

The AWS infrastructure may continue generating charges while running. Coordinate before modifying or destroying it.

## 7. Getting Started

1. Clone the repository.
2. Read `README.md`.
3. Review the Terraform and Kubernetes configuration.
4. Review the existing GitHub Actions workflows.
5. Check the `evidence/` folder.
6. Continue with the remaining exercises.

---

**Handover status:** Application deployed successfully. Initial infrastructure, deployment and runtime evidence collected. Remaining assignment exercises and final report still need completion.