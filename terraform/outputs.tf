output "region" {
  description = "AWS region of the cluster."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the cluster."
  value       = module.eks.cluster_version
}

output "configure_kubectl" {
  description = "Command to add the cluster to your kubeconfig."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets where nodes run."
  value       = module.vpc.private_subnets
}

output "karpenter_node_iam_role_name" {
  description = "IAM role assumed by Karpenter-launched nodes (referenced by the EC2NodeClass)."
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_interruption_queue" {
  description = "SQS queue Karpenter uses for Spot interruption and instance health events."
  value       = module.karpenter.queue_name
}
