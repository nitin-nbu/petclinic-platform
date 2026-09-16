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

output "ecr_repository_urls" {
  description = "Map of service_name to ECR repository URL"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service_name to ECR repository ARN"
  value       = module.ecr.repository_arns
}

output "rds_endpoint" {
  description = "RDS endpoint hostname"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "RDS instance ID"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Secrets Manager secret ARN for RDS credentials"
  value       = module.rds.secret_arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller service account (used by scripts/install-lb_controller.sh)"
  value       = module.eks.lb_controller_role_arn
}

output "dns_zone_id" {
  description = "Route 53 hosted zone ID (null when domain_name is unset)"
  value       = one(module.dns[*].zone_id)
}

output "dns_name_servers" {
  description = "Hosted zone name servers to delegate at the domain registrar (null when domain_name is unset)"
  value       = one(module.dns[*].name_servers)
}

output "certificate_arn" {
  description = "ACM certificate ARN for the Ingress certificate-arn annotation (null when domain_name is unset)"
  value       = one(module.dns[*].certificate_arn)
}

output "app_fqdn" {
  description = "Fully qualified domain name the app is served on (null when domain_name is unset)"
  value       = one(module.dns[*].app_fqdn)
}

output "app_url" {
  description = "HTTPS URL the app is served on (null when domain_name is unset)"
  value       = one(module.dns[*].app_url)
}

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key"
  value       = module.secrets.openai_secret_arn
}

output "eso_role_arn" {
  description = "IRSA role ARN for the External Secrets Operator service account (used by scripts/install-external-secrets.sh)"
  value       = module.eks.eso_role_arn
}
