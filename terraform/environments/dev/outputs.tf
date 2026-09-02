# Outputs added as modules are wired in (E-3 through E-7).

output "vpc_id" {
  description = "ID of the dev VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the dev public subnets"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "ID of the EKS cluster security group"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "ID of the EKS node security group"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = module.vpc.alb_sg_id
}

output "cluster_name" {
  description = "Name of the dev EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = module.eks.cluster_ca_certificate
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the IAM OIDC provider for IRSA"
  value       = module.eks.oidc_provider_url
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = module.eks.node_group_name
}

output "node_role_arn" {
  description = "ARN of the node group's IAM role"
  value       = module.eks.node_role_arn
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for this cluster"
  value       = module.eks.kubeconfig_command
}
