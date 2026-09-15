output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "zone_name" {
  description = "Route 53 hosted zone domain name"
  value       = aws_route53_zone.main.name
}

output "name_servers" {
  description = "Name servers for the hosted zone — delegate these at the domain registrar"
  value       = aws_route53_zone.main.name_servers
}

output "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener (use in the Ingress alb.ingress.kubernetes.io/certificate-arn annotation)"
  value       = var.wait_for_certificate_validation ? one(aws_acm_certificate_validation.main[*].certificate_arn) : aws_acm_certificate.main.arn
}

output "certificate_domain_names" {
  description = "Domain names covered by the ACM certificate"
  value       = concat([aws_acm_certificate.main.domain_name], tolist(aws_acm_certificate.main.subject_alternative_names))
}

output "app_fqdn" {
  description = "Fully qualified domain name the app is served on"
  value       = local.fqdn
}

output "app_url" {
  description = "HTTPS URL the app is served on"
  value       = "https://${local.fqdn}"
}

output "alb_alias_record_created" {
  description = "Whether the ALB alias record exists yet (false until the Ingress has provisioned an ALB and its DNS name/zone is passed in or discovered)"
  value       = local.create_alias_record
}
