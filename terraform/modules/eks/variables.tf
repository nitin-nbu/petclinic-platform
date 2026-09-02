variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster. The technical spec's original target (1.29) has since aged out of AWS support for new clusters; 1.34 is the oldest version currently on Standard Support (no extra Extended Support fee), giving the longest runway before another forced bump."
  type        = string
  default     = "1.34"
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS cluster and node group (public subnets — see ADR-0001)"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS control plane"
  type        = string
}

variable "cluster_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint (CIDR-restricted where possible per PETPLAT-12)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_sg_id" {
  description = "Security group ID for EKS worker nodes"
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for the managed node group. AL2_ARM_64 (the technical spec's original target) is only supported for Kubernetes 1.32 and earlier; AL2023_ARM_64_STANDARD is its supported successor."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root EBS volume size (GB) for worker nodes"
  type        = number
  default     = 20
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}

# Add-on versions: leave null to pin to the most recent version compatible with
# cluster_version (resolved via the aws_eks_addon_version data source, never the
# literal "latest"). Set an explicit version string to pin deliberately and control
# upgrades — see the "Upgrading add-ons" comment in main.tf.
variable "coredns_addon_version" {
  description = "Pinned version for the coredns add-on (null = most recent compatible with cluster_version)"
  type        = string
  default     = null
}

variable "kube_proxy_addon_version" {
  description = "Pinned version for the kube-proxy add-on (null = most recent compatible with cluster_version)"
  type        = string
  default     = null
}

variable "vpc_cni_addon_version" {
  description = "Pinned version for the vpc-cni add-on (null = most recent compatible with cluster_version)"
  type        = string
  default     = null
}

variable "ebs_csi_addon_version" {
  description = "Pinned version for the aws-ebs-csi-driver add-on (null = most recent compatible with cluster_version)"
  type        = string
  default     = null
}
