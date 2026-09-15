output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL of the IAM OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.url
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_role_arn" {
  description = "ARN of the node group's IAM role"
  value       = aws_iam_role.node.arn
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig for this cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${data.aws_region.current.name}"
}

output "lb_controller_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller service account"
  value       = aws_iam_role.lb_controller.arn
}

output "lb_controller_policy_arn" {
  description = "ARN of the IAM policy attached to the AWS Load Balancer Controller role"
  value       = aws_iam_policy.lb_controller.arn
}

output "lb_controller_service_account" {
  description = "Namespace/name of the Kubernetes service account the LB controller role trusts"
  value       = "${var.lb_controller_namespace}/${var.lb_controller_service_account}"
}
