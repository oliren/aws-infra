provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  name   = "eks-cluster"
  region = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    ManagedBy  = "terraform"
  }
}

terraform {
  backend "s3" {
    bucket = "akn-playground.lockirin.pp.ua"
    key    = "terraform.tfstate"
    region = "eu-west-1"
  }
}
