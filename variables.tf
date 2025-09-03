variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-karpenter-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.0.0"
}

# Version variables from GitVersion
variable "app_version" {
  description = "Application version from GitVersion"
  type        = string
  default     = "0.1.0"
}

variable "build_number" {
  description = "Build number from GitVersion (commits since version source)"
  type        = string
  default     = "0"
}

variable "git_commit" {
  description = "Git commit short SHA from GitVersion"
  type        = string
  default     = ""
}

variable "git_branch" {
  description = "Git branch name from GitVersion"
  type        = string
  default     = ""
}