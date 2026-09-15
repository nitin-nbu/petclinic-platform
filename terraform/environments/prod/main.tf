# Root module for the prod environment.
# Module calls (rds, dns, secrets, observability) are added
# as their respective epics land (E-5 through E-7).

locals {
  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]
}

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = "10.1.0.0/16"
  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  availability_zones  = ["eu-central-1a", "eu-central-1b"]
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  node_instance_types = ["t4g.small"]
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  service_names        = local.service_names
  image_tag_mutability = "IMMUTABLE"
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class          = "db.t4g.micro"
  multi_az                = false
  skip_final_snapshot     = true
  backup_retention_period = 7
}

# ---------------------------------------------------------------------------
# DNS & Ingress (PETPLAT-32)
# Gated on var.domain_name: with no domain set, no hosted zone or certificate
# is created and the rest of the environment plans/applies unchanged. Set
# domain_name in terraform.tfvars to enable it.
# ---------------------------------------------------------------------------

module "dns" {
  count  = var.domain_name == "" ? 0 : 1
  source = "../../modules/dns"

  project     = var.project
  environment = var.environment

  domain_name = var.domain_name
  record_name = "petclinic"

  # Populated after the Ingress has provisioned an ALB — see variables.tf.
  alb_dns_name       = var.alb_dns_name
  alb_zone_id        = var.alb_zone_id
  alb_discovery_tags = var.alb_discovery_tags

  wait_for_certificate_validation = var.wait_for_certificate_validation
}
