##############################################################################
# Prod environment — eu-west-1 (Ireland)
# HA NAT: one NAT Gateway per AZ. Three NATs cost ~$100/month each — budget for it.
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
    key            = "eu-west-1/prod/vpc/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"                # replace with your lock table
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Environment = "prod"
      Owner       = "platform-team"
      CostCenter  = "cc-1234"
      Project     = "my-project"
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  environment = "prod"
  project     = "my-project"
  owner       = "platform-team"
  cost_center = "cc-1234"

  # Use a different /16 for prod to avoid peering conflicts with dev
  vpc_cidr = "10.20.0.0/16"

  azs = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnet_cidrs       = ["10.20.0.0/19", "10.20.32.0/19", "10.20.64.0/19"]
  private_app_subnet_cidrs  = ["10.20.96.0/19", "10.20.128.0/19", "10.20.160.0/19"]
  private_data_subnet_cidrs = ["10.20.192.0/19", "10.20.224.0/19", "10.20.240.0/19"]

  enable_nat_gateway = true
  single_nat_gateway = false  # HA: one NAT per AZ for prod

  enable_vpc_flow_logs    = true
  flow_log_retention_days = 90  # longer retention for compliance in prod

  enable_s3_endpoint   = true
  enable_ecr_endpoints = true   # worth it for prod with regular image pulls
}
