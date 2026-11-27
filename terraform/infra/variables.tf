variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  description = "Must match the 'project' value used in bootstrap"
  type        = string
  default     = "capstone"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Check the currently supported versions in the AWS EKS docs before applying."
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "admin_principal_arns" {
  description = "Extra IAM user/role ARNs (e.g. your own IAM user) that get cluster-admin via kubectl"
  type        = list(string)
  default     = []
}
