################################################################################
# General
################################################################################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Also used as a prefix for related resources and as the Karpenter discovery tag value."
  type        = string
  default     = "eks-karpenter-poc"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,37}$", var.cluster_name))
    error_message = "cluster_name must start with a letter, contain only letters, digits and hyphens, and be at most 38 characters (it is used in IAM role names)."
  }
}

variable "tags" {
  description = "Additional tags applied to all AWS resources."
  type        = map(string)
  default     = {}
}

################################################################################
# Network
################################################################################

variable "vpc_cidr" {
  description = "CIDR block of the dedicated VPC. A /16 leaves room for many pods, because the VPC CNI gives every pod a VPC IP."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "vpc_cidr must be a valid IPv4 CIDR of size /16 or larger (the subnet layout assumes a /16)."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets (and therefore nodes) across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT Gateway (cheaper, fine for a POC) instead of one per AZ (highly available, recommended for production)."
  type        = bool
  default     = true
}

################################################################################
# EKS
################################################################################

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Keep in sync with the Karpenter compatibility matrix."
  type        = string
  default     = "1.37"
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint publicly (restricted by endpoint_public_access_cidrs). Needed when running Terraform/kubectl from outside the VPC."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public Kubernetes API endpoint. Restrict this to your office/VPN IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_admin_principal_arns" {
  description = "Additional IAM role/user ARNs (e.g. SSO roles of the platform team) that get cluster-admin access. The identity running Terraform always gets admin access."
  type        = list(string)
  default     = []
}

variable "system_node_instance_types" {
  description = "Instance types for the small managed node group that runs Karpenter and cluster-critical add-ons (Graviton by default)."
  type        = list(string)
  default     = ["m7g.large", "m6g.large"]
}

################################################################################
# Karpenter
################################################################################

variable "karpenter_version" {
  description = "Karpenter Helm chart version (also used for the karpenter-crd chart)."
  type        = string
  default     = "1.15.3"
}

variable "karpenter_ami_alias" {
  description = "AMI alias for Karpenter nodes. `al2023@latest` tracks the newest EKS-optimised AL2023 AMI; pin a version (e.g. al2023@v20261120) in production so AMI rollouts are deliberate."
  type        = string
  default     = "al2023@latest"
}

variable "karpenter_architectures" {
  description = "CPU architectures the default NodePool may launch."
  type        = list(string)
  default     = ["arm64", "amd64"]

  validation {
    condition     = length(var.karpenter_architectures) > 0 && alltrue([for a in var.karpenter_architectures : contains(["arm64", "amd64"], a)])
    error_message = "karpenter_architectures may only contain \"arm64\" and \"amd64\"."
  }
}

variable "karpenter_capacity_types" {
  description = "Capacity types the default NodePool may launch. With both, Karpenter prefers Spot and falls back to On-Demand."
  type        = list(string)
  default     = ["spot", "on-demand"]

  validation {
    condition     = length(var.karpenter_capacity_types) > 0 && alltrue([for c in var.karpenter_capacity_types : contains(["spot", "on-demand"], c)])
    error_message = "karpenter_capacity_types may only contain \"spot\" and \"on-demand\"."
  }
}

variable "karpenter_cpu_limit" {
  description = "Maximum total vCPUs the default NodePool may provision. Protects against runaway scaling and cost."
  type        = number
  default     = 100
}

variable "karpenter_memory_limit" {
  description = "Maximum total memory the default NodePool may provision (Kubernetes quantity)."
  type        = string
  default     = "400Gi"
}

variable "create_spot_service_linked_role" {
  description = "Create the account-wide AWSServiceRoleForEC2Spot role, required to launch Spot instances. It exists already in any account that has used Spot before; set to true only for a fresh account (see README)."
  type        = bool
  default     = false
}
