locals {
  name = var.name

  tags = merge(
    {
      Project     = "kerberos-hub"
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "deployment/modules/amazon-eks-documentdb"
    },
    var.tags,
  )

  azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

###############################################################################
# VPC
#
# DocumentDB has no public endpoint: it only listens inside the VPC. Both the
# EKS worker nodes and the DocumentDB instances therefore live in the private
# subnets, and the workers reach the internet (image pulls) through NAT.
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for index in range(var.availability_zone_count) : cidrsubnet(var.vpc_cidr, 4, index)]
  public_subnets  = [for index in range(var.availability_zone_count) : cidrsubnet(var.vpc_cidr, 4, index + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.tags
}
