##############################################################################
# Dev environment — eu-west-1 (Ireland)
# Single NAT Gateway to keep cost low. Flip single_nat_gateway = false for HA.
##############################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "myorg-tfstate-eu-west-1"        # replace with your state bucket
    key            = "eu-west-1/dev/vpc/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"                # replace with your lock table
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Environment = "dev"
      Owner       = "platform-team"    # replace with your team
      CostCenter  = "cc-1234"          # replace with your cost centre
      Project     = "my-project"       # replace with your project name
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  environment = "dev"
  project     = "my-project"   # replace
  owner       = "platform-team"
  cost_center = "cc-1234"

  vpc_cidr = "10.10.0.0/16"

  azs = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnet_cidrs       = ["10.10.0.0/19", "10.10.32.0/19", "10.10.64.0/19"]
  private_app_subnet_cidrs  = ["10.10.96.0/19", "10.10.128.0/19", "10.10.160.0/19"]
  private_data_subnet_cidrs = ["10.10.192.0/19", "10.10.224.0/19", "10.10.240.0/19"]

  enable_nat_gateway = true
  single_nat_gateway = true   # single NAT for dev — saves ~$100/month vs 3x NAT

  enable_vpc_flow_logs    = true
  flow_log_retention_days = 14

  enable_s3_endpoint   = true
  enable_ecr_endpoints = false  # enable if you pull lots of images from private subnets
}
