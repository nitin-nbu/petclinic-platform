locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  # Wildcard certificate per spec (*.{domain}), with the apex as a SAN so the
  # bare domain is covered too. Both names validate through the same zone.
  certificate_domain = "*.${var.domain_name}"
  fqdn               = "${var.record_name}.${var.domain_name}"

  discover_alb = length(var.alb_discovery_tags) > 0 && var.alb_dns_name == null

  alb_dns_name = local.discover_alb ? data.aws_lb.ingress[0].dns_name : var.alb_dns_name
  alb_zone_id  = local.discover_alb ? data.aws_lb.ingress[0].zone_id : var.alb_zone_id

  create_alias_record = local.alb_dns_name != null && local.alb_zone_id != null
}

# ---------------------------------------------------------------------------
# Route 53 hosted zone (PETPLAT-28)
# Public zone for the apex domain. After the first apply, delegate the domain
# at the registrar using the name_servers output — ACM DNS validation and
# public resolution both depend on that delegation.
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Public hosted zone for ${local.name_prefix}"

  # Refuse to delete a zone that still holds records other than the default
  # NS/SOA pair — those would be live DNS entries for the running app.
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-zone"
  })
}

# ---------------------------------------------------------------------------
# ACM certificate (PETPLAT-28) — DNS validation, same region as the ALB
# (eu-central-1). create_before_destroy so a renewal/re-issue never leaves the
# ALB listener without a certificate.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "main" {
  domain_name               = local.certificate_domain
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ACM emits one validation option per requested name, but issues an identical
# CNAME token for a domain and its wildcard — so "*.example.com" and
# "example.com" resolve to the same validation record. Managing both options
# would put two Terraform resources on one real record: harmless on apply
# (both UPSERT the same value) but redundant state that breaks on destroy.
# Keep the non-wildcard options only; this module requests exactly
# "*.{domain}" plus the "{domain}" apex SAN, so that is always one record.
# Revisit the filter if SANs for additional base domains are ever added.
#
# Keyed on domain_name rather than resource_record_name because the record
# name is only known after apply, and for_each keys must be known at plan time.
resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.main.domain_validation_options :
    option.domain_name => option
    if !startswith(option.domain_name, "*.")
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60

  # Idempotent if a validation record for this name already exists in the zone
  # (e.g. a previous certificate request for the same domain).
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  count = var.wait_for_certificate_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

# ---------------------------------------------------------------------------
# ALB alias record (PETPLAT-31)
# A record aliased to the controller-created ALB. HTTP→HTTPS redirection is
# enforced on the ALB itself by the Ingress annotations (PETPLAT-30), not here.
# ---------------------------------------------------------------------------

# Reads at plan time: enable var.alb_discovery_tags only AFTER the Ingress has
# provisioned an ALB, otherwise every plan fails with "no matching LB found".
# Until then leave the tags empty and the alias record simply is not created.
data "aws_lb" "ingress" {
  count = local.discover_alb ? 1 : 0

  tags = var.alb_discovery_tags
}

resource "aws_route53_record" "alb" {
  count = local.create_alias_record ? 1 : 0

  zone_id = aws_route53_zone.main.zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name                   = local.alb_dns_name
    zone_id                = local.alb_zone_id
    evaluate_target_health = true
  }
}
