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
}

# ---------------------------------------------------------------------------
# ECR repositories (PETPLAT-18) — one per service, under petclinic-{env}/.
# Private by default (aws_ecr_repository has no public option); scan-on-push
# and AES256 encryption are declared explicitly rather than relying on defaults.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(var.service_names)

  name                 = "${local.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability

  # This is a learning project with a documented destroy/redeploy workflow
  # (see docs/technical-spec.md's cost note) — force_delete lets `terraform
  # destroy` remove a repo even if images were pushed into it, rather than
  # requiring manual image cleanup first every time.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}/${each.value}"
  })
}

# ---------------------------------------------------------------------------
# Lifecycle policy (PETPLAT-19) — keep the last N tagged images (any tag
# scheme: semver, commit SHA), expire untagged images after the configured
# retention window.
# ---------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expire_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.tagged_image_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.tagged_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
