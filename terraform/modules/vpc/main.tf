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
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ---------------------------------------------------------------------------
# Public Subnets — all-public design (no NAT Gateway, no private subnets).
# Security groups are the perimeter. See ADR-0001.
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                         = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway + single public route table
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Baseline Security Groups (PETPLAT-8)
# These are the primary access control boundary in this all-public design —
# as restrictive as a traditional private-subnet setup. See ADR-0001.
# ---------------------------------------------------------------------------

# --- EKS cluster (control plane) security group ---

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_security_group_rule" "eks_cluster_ingress_from_nodes" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_cluster.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  description              = "API server access from EKS nodes"
}

# Terraform's aws_security_group resource strips the AWS-provisioned default
# "allow all outbound" rule on creation (documented provider behavior — this
# only happens automatically for SGs created directly via the AWS API/console).
# The control plane's ENIs need outbound access, so it must be declared explicitly.
resource "aws_security_group_rule" "eks_cluster_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.eks_cluster.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}

# --- EKS node (worker) security group ---

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name                                         = "${local.name_prefix}-eks-node-sg"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
  })
}

resource "aws_security_group_rule" "eks_node_ingress_from_cluster" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node.id
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster.id
  description              = "All traffic from EKS control plane"
}

resource "aws_security_group_rule" "eks_node_ingress_self" {
  type              = "ingress"
  security_group_id = aws_security_group.eks_node.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  description       = "Inter-node communication"
}

resource "aws_security_group_rule" "eks_node_ingress_kubelet_from_cluster" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node.id
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  description              = "Kubelet API from EKS control plane"
}

resource "aws_security_group_rule" "eks_node_ingress_nodeport_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node.id
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "NodePort services from ALB"
}

# Terraform's aws_security_group resource strips the AWS-provisioned default
# "allow all outbound" rule on creation (documented provider behavior — this
# only happens automatically for SGs created directly via the AWS API/console).
# Nodes need outbound access to bootstrap (EC2/EKS/ECR APIs, DNS) and to reach
# RDS, so it must be declared explicitly.
resource "aws_security_group_rule" "eks_node_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.eks_node.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}

# --- RDS security group ---
# Critical: MySQL (3306) is reachable ONLY from EKS nodes. Never 0.0.0.0/0.
# Defined with inline ingress/egress blocks (rather than aws_security_group_rule)
# so Terraform takes full ownership of the rule set and removes AWS's default
# allow-all egress rule — the DB engine has no legitimate need to initiate
# outbound connections, so egress is intentionally left empty.

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL security group - access restricted to EKS nodes only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_node.id]
    description     = "MySQL from EKS nodes only"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

# --- ALB security group ---

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group - public-facing HTTP/HTTPS"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP from internet"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS from internet"
}

resource "aws_security_group_rule" "alb_egress_to_nodes_nodeport" {
  type                     = "egress"
  security_group_id        = aws_security_group.alb.id
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  description              = "To EKS nodes (target group NodePort range)"
}

resource "aws_security_group_rule" "alb_egress_healthcheck_to_nodes" {
  type                     = "egress"
  security_group_id        = aws_security_group.alb.id
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  description              = "Health checks to EKS nodes"
}

# ---------------------------------------------------------------------------
# Lock down the VPC's auto-created default security group.
# Since SGs are the sole perimeter in this all-public design, any resource
# accidentally launched without an explicit SG would otherwise fall back to
# this default (which AWS creates pre-populated with an allow-all self-referencing
# rule), silently bypassing every rule above.
# ---------------------------------------------------------------------------

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-default-sg-locked"
  })
}

# ---------------------------------------------------------------------------
# VPC Flow Logs — traffic-level visibility, since security groups (not NACLs
# or private subnets) are the only access-control boundary in this design.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/petclinic/${var.environment}/vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = local.common_tags
}

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name_prefix}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${local.name_prefix}-vpc-flow-logs-policy"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-log"
  })
}
