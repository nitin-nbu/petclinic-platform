output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# Kept for compatibility with modules/consumers expecting a generic subnet_ids output.
output "subnet_ids" {
  description = "IDs of the public subnets (alias of public_subnet_ids)"
  value       = aws_subnet.public[*].id
}

output "eks_cluster_sg_id" {
  description = "ID of the EKS cluster (control plane) security group"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "ID of the EKS node (worker) security group"
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}
