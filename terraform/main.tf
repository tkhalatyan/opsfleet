data "aws_availability_zones" "available" {
  # Exclude Local Zones / Wavelength Zones; EKS and most instance types need standard AZs.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = var.cluster_name
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  tags = merge(
    {
      Project   = local.name
      ManagedBy = "terraform"
    },
    var.tags,
  )
}
