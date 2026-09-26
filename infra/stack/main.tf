terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    bucket       = "terraform-lucky9"
    key          = "azalea-nezu/hackathon/terraform.tfstate"
    region       = "us-west-2"
    profile      = "azalea-nezu-source"
    encrypt      = true
    use_lockfile = true
    assume_role  = { role_arn = "arn:aws:iam::964028866059:role/azalea-nezu-terraform-deployer" }
  }
}

provider "aws" {
  region  = "us-west-2"
  profile = "azalea-nezu-source"
  assume_role { role_arn = "arn:aws:iam::964028866059:role/azalea-nezu-terraform-deployer" }
  default_tags {
    tags = { project = "azalea-nezu", environment = "hackathon", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "core" {
  filter {
    name   = "tag:Name"
    values = ["core-vpc"]
  }
}

data "aws_subnet" "private" {
  vpc_id = data.aws_vpc.core.id
  filter {
    name   = "tag:Name"
    values = ["core-private-subnet-us-west-2a"]
  }
}

locals {
  prefix        = "azalea-nezu"
  bucket_suffix = "${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
  catalog       = jsondecode(file("${path.module}/../../schemas/catalog.json"))
  tables        = merge({ for name, cols in local.catalog.tables.silver : "silver_${name}" => { tier = "silver", name = name, columns = cols } }, { for name, cols in local.catalog.tables.gold : "gold_${name}" => { tier = "gold", name = name, columns = cols } })
}

variable "enable_notebook" {
  type        = bool
  description = "Keep the private notebook enabled after the bootstrap Tailscale secret has a value. Set false only for a catalog-only deployment."
  default     = true
}
