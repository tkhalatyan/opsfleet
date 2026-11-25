################################################################################
# EKS cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.30.2"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  endpoint_private_access      = true

  # Access entries (API mode) instead of the legacy aws-auth ConfigMap.
  authentication_mode = "API"

  # The identity running Terraform becomes cluster admin so it can install Karpenter.
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    for i, arn in var.cluster_admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  addons = {
    # Networking and Pod Identity must be ready before any node joins.
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    coredns = {
      # CoreDNS must be able to run on the tainted system nodes (before Karpenter exists).
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "CriticalAddonsOnly"
            operator = "Exists"
          }
        ]
      })
    }
  }

  # Small, static, On-Demand Graviton node group for Karpenter itself and
  # cluster-critical add-ons. Karpenter must not run on nodes it manages.
  # The taint keeps application pods off these nodes; they go to Karpenter nodes.
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        "karpenter.sh/controller" = "true"
      }

      taints = {
        critical_addons_only = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Karpenter attaches this security group to the nodes it launches.
  # Only one security group per cluster should carry the discovery tag.
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.name
  }
}
