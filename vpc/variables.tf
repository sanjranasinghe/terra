variable "environment" {
  description = "Deployment environment (dev, stage, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

variable "project" {
  description = "Project name — used in naming and tags"
  type        = string
}

variable "owner" {
  description = "Team or individual owning this infrastructure"
  type        = string
}

variable "cost_center" {
  description = "Cost centre for billing allocation"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Use a /16 per environment to avoid peering conflicts."
  type        = string
  default     = "10.10.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "azs" {
  description = "List of Availability Zones to deploy into. Minimum 3 for HA."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Houses NAT Gateways and ALBs."
  type        = list(string)
  default     = ["10.10.0.0/19", "10.10.32.0/19", "10.10.64.0/19"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private-app subnets (one per AZ). Houses workloads (EKS/ECS/EC2)."
  type        = list(string)
  default     = ["10.10.96.0/19", "10.10.128.0/19", "10.10.160.0/19"]
}

variable "private_data_subnet_cidrs" {
  description = "CIDR blocks for private-data subnets (one per AZ). Houses RDS, ElastiCache, etc."
  type        = list(string)
  default     = ["10.10.192.0/19", "10.10.224.0/19", "10.10.240.0/19"]
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT Gateway(s). Set false to save cost in fully private setups."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway instead of one per AZ. Recommended for non-prod to cut cost."
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch. Strongly recommended — critical for incident response."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch log retention in days for VPC flow logs."
  type        = number
  default     = 30
}

variable "enable_s3_endpoint" {
  description = "Create a Gateway VPC Endpoint for S3. Reduces NAT Gateway data costs significantly."
  type        = bool
  default     = true
}

variable "enable_ecr_endpoints" {
  description = "Create Interface VPC Endpoints for ECR (API + DKR). Cuts NAT costs for container pulls."
  type        = bool
  default     = false
}
