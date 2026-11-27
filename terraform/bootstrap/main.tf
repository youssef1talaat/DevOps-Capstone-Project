# =============================================================================
# BOOTSTRAP — run ONCE, locally, with your own AWS credentials.
#
# Creates the things the pipelines need before they can run themselves:
#   1. S3 bucket for Terraform remote state (with native S3 locking)
#   2. GitHub OIDC identity provider (no long-lived AWS keys in GitHub!)
#   3. IAM role for the Terraform pipeline  (provisions infrastructure)
#   4. IAM role for the app pipeline        (pushes images, deploys to EKS)
#
# This stack keeps its own state locally (terraform.tfstate in this folder).
# =============================================================================

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  repo = "${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repository_id}"
}

# -----------------------------------------------------------------------------
# 1. Remote state bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tf_state" {
  bucket        = "${var.project}-tfstate-${local.account_id}"
  force_destroy = true # course convenience: allows clean teardown
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# 2. GitHub OIDC provider
# -----------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer validates these for GitHub, but the argument is still accepted.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# Trust policy builder: only THIS repo, and only the listed "sub" claims.
data "aws_iam_policy_document" "github_trust" {
  for_each = {
    terraform = [
      "repo:${local.repo}:ref:refs/heads/main",
      "repo:${local.repo}:pull_request",
      "repo:${local.repo}:environment:infrastructure",
    ]
    deploy = [
      "repo:${local.repo}:ref:refs/heads/main",
      "repo:${local.repo}:environment:production",
    ]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# -----------------------------------------------------------------------------
# 3. Terraform pipeline role
#    NOTE: AdministratorAccess is a teaching shortcut. Stretch goal for students:
#    replace it with a least-privilege policy and a separate read-only plan role.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "github_terraform" {
  name               = "${var.project}-github-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_trust["terraform"].json
}

resource "aws_iam_role_policy_attachment" "github_terraform_admin" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# 4. App deploy role (least privilege: ECR push + describe EKS cluster).
#    Kubernetes permissions are granted separately via an EKS access entry.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "github_deploy" {
  name               = "${var.project}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust["deploy"].json
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${var.project}-*"]
  }
  statement {
    sid       = "EksDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${var.aws_region}:${local.account_id}:cluster/${var.project}-*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "ecr-push-eks-describe"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
