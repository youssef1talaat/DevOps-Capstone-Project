variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short project name used as a prefix for every resource (lowercase, no spaces)"
  type        = string
  default     = "capstone"
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repo (e.g. 'jane-doe')"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (e.g. 'devops-capstone')"
  type        = string
}

variable "github_owner_id" {
  description = "Immutable GitHub owner ID"
  type        = string
}

variable "github_repository_id" {
  description = "Immutable GitHub repository ID"
  type        = string
}
