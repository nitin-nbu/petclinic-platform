# Root module for the prod environment.
# Module calls (ecr, rds, dns, secrets, observability) are added
# as their respective epics land (E-4 through E-7).

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
