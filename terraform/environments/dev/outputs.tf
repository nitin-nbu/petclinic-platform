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
