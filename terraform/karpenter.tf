################################################################################
# Karpenter AWS resources
#   - Controller IAM role, bound to the Karpenter service account via EKS Pod Identity
#   - Node IAM role + EKS access entry so Karpenter-launched nodes can join the cluster
#   - SQS queue + EventBridge rules for Spot interruption / rebalance / health events
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.30.2"

  cluster_name = module.eks.cluster_name

  namespace                       = "kube-system"
  service_account                 = "karpenter"
  create_pod_identity_association = true

  iam_role_name            = "${local.name}-karpenter-controller"
  iam_role_use_name_prefix = false

  # Referenced by name from the EC2NodeClass, so it must be deterministic.
  node_iam_role_name            = "${local.name}-karpenter-node"
  node_iam_role_use_name_prefix = false
  node_iam_role_additional_policies = {
    # Shell access to nodes via SSM Session Manager instead of SSH keys.
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# Account-wide role that EC2 needs before it can launch Spot instances.
# Without it Karpenter still works but falls back to On-Demand.
resource "aws_iam_service_linked_role" "spot" {
  count = var.create_spot_service_linked_role ? 1 : 0

  aws_service_name = "spot.amazonaws.com"
}

################################################################################
# Karpenter Helm charts
################################################################################

# Karpenter's chart lives in public ECR, which requires a token from us-east-1.
data "aws_ecrpublic_authorization_token" "token" {
  region = "us-east-1"
}

# CRDs are installed from the dedicated chart so they are also upgraded on
# `helm upgrade` (Helm never upgrades CRDs placed in a chart's crds/ folder).
resource "helm_release" "karpenter_crd" {
  name                = "karpenter-crd"
  namespace           = "kube-system"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter-crd"
  version             = var.karpenter_version

  # Make sure the cluster, its nodes and add-ons exist before installing,
  # and are only destroyed after Karpenter has cleaned up its own nodes.
  depends_on = [module.eks]
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = "kube-system"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = var.karpenter_version
  skip_crds           = true
  wait                = true

  values = [
    yamlencode({
      # Run only on the static system node group (not on nodes Karpenter manages).
      nodeSelector = {
        "karpenter.sh/controller" = "true"
      }
      # Resolve DNS via the VPC resolver so Karpenter can start even if CoreDNS is not running yet.
      dnsPolicy = "Default"

      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }

      controller = {
        resources = {
          requests = { cpu = "500m", memory = "512Mi" }
          limits   = { memory = "512Mi" }
        }
      }
    })
  ]

  depends_on = [
    helm_release.karpenter_crd,
    module.karpenter,
  ]
}

################################################################################
# Karpenter NodePool + EC2NodeClass
#
# Shipped as a small local Helm chart (charts/karpenter-nodepools) instead of
# kubernetes_manifest, which fails at plan time on a fresh cluster because the
# Karpenter CRDs do not exist yet.
################################################################################

resource "helm_release" "karpenter_nodepools" {
  name      = "karpenter-nodepools"
  namespace = "kube-system"
  chart     = "${path.module}/charts/karpenter-nodepools"

  # On destroy, `wait` makes Helm block until the NodePool/EC2NodeClass are gone,
  # i.e. until Karpenter (still running) has terminated every node it launched.
  # This prevents orphaned EC2 instances that would block VPC deletion.
  wait    = true
  timeout = 900

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name

      nodeClass = {
        name     = "default"
        role     = module.karpenter.node_iam_role_name
        amiAlias = var.karpenter_ami_alias
        tags     = local.tags
      }

      nodePools = {
        # One general-purpose pool that can launch both x86 (amd64) and Graviton
        # (arm64), Spot and On-Demand. Karpenter picks the cheapest instance that
        # fits the pending pods, which is usually Graviton Spot. Workloads opt
        # into a specific architecture/capacity type with a nodeSelector
        # (see README and examples/).
        default = {
          architectures  = var.karpenter_architectures
          capacityTypes  = var.karpenter_capacity_types
          cpuLimit       = var.karpenter_cpu_limit
          memoryLimit    = var.karpenter_memory_limit
          instanceFamily = ["c", "m", "r"]
          # Generation > 5 = Graviton2/3/4 (c6g, m7g, r8g...) and modern x86 (c6i, m7a...).
          generationGreaterThan = 5
        }
      }
    })
  ]

  depends_on = [helm_release.karpenter]
}
