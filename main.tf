# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

locals {
  cluster_name = "eks"
}

data "aws_eks_cluster" "cluster" {
  name =  module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
  state = "available"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "explore-california"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 1, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true
  enable_dns_support = true
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/cluster/eks": "owned",
    "kubernetes.io/role/elb": "1"
  }
  public_subnet_tags = {
    "kubernetes.io/cluster/eks": "owned",
    "kubernetes.io/role/elb": "1"
  }
}

resource "aws_security_group" "enable_ssh" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/16"
    ]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.5.1"

  cluster_name    = local.cluster_name
  cluster_version = "1.24"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.medium"]

      asg_max_size  = 5
      spot_price = "0.02"
      additional_security_group_ids = [ aws_security_group.enable_ssh.id ]
      kubelet_extra_args = "--node-labels=node.kubernetes.io/lifecycle=spot"
      suspended_processes = ["AZRebalance"]
    }

    two = {
      name = "node-group-2"

      instance_types = ["t3.large"]

      asg_max_size  = 5
      spot_price = "0.03"
      additional_security_group_ids = [ aws_security_group.enable_ssh.id ]
      kubelet_extra_args = "--node-labels=node.kubernetes.io/lifecycle=spot"
      suspended_processes = ["AZRebalance"]
    }
  }
}

resource "aws_ecr_repository" "explore-california" {
  name = "explore-california"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

