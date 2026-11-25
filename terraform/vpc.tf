################################################################################
# Dedicated VPC
#
# Subnet layout for the default 10.0.0.0/16 and 3 AZs:
#   private (nodes + pods)  /19 per AZ  10.0.0.0/19, 10.0.32.0/19, 10.0.64.0/19
#   public  (NAT, LBs)      /24 per AZ  10.0.96.0/24 - 10.0.98.0/24
#   intra   (EKS control-plane ENIs, no internet route)
#                           /24 per AZ  10.0.100.0/24 - 10.0.102.0/24
#
# Private subnets are large on purpose: the VPC CNI assigns a VPC IP to every pod.
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.8.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 3, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 96)]
  intra_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags used by the AWS Load Balancer Controller (if installed later) to place load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter launches nodes only into subnets carrying this tag.
    "karpenter.sh/discovery" = local.name
  }
}
