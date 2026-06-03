##############################################################################
# VPC
##############################################################################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-${var.project}-vpc"
  }
}

##############################################################################
# Internet Gateway
##############################################################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.environment}-${var.project}-igw"
  }
}

##############################################################################
# Public Subnets
##############################################################################
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-${var.project}-public-${var.azs[count.index]}"
    Tier = "public"
    # Required by EKS if you plan to launch public ALBs via the AWS LB Controller
    "kubernetes.io/role/elb" = "1"
  }
}

##############################################################################
# Private App Subnets
##############################################################################
resource "aws_subnet" "private_app" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.environment}-${var.project}-private-app-${var.azs[count.index]}"
    Tier = "private-app"
    # Required by EKS if you plan to launch internal ALBs via the AWS LB Controller
    "kubernetes.io/role/internal-elb" = "1"
  }
}

##############################################################################
# Private Data Subnets
##############################################################################
resource "aws_subnet" "private_data" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.environment}-${var.project}-private-data-${var.azs[count.index]}"
    Tier = "private-data"
  }
}

##############################################################################
# Elastic IPs for NAT Gateways
##############################################################################
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0
  domain = "vpc"

  tags = {
    Name = "${var.environment}-${var.project}-nat-eip-${count.index}"
  }

  depends_on = [aws_internet_gateway.this]
}

##############################################################################
# NAT Gateways
# HA (prod): one per AZ  →  single_nat_gateway = false
# Cost-optimised (dev/stage): one in first AZ  →  single_nat_gateway = true
##############################################################################
resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.environment}-${var.project}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.this]
}

##############################################################################
# Route Tables — Public
##############################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.environment}-${var.project}-rt-public"
  }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

##############################################################################
# Route Tables — Private App (one per AZ for HA NAT; one shared for single NAT)
##############################################################################
resource "aws_route_table" "private_app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.environment}-${var.project}-rt-private-app-${var.azs[count.index]}"
  }
}

resource "aws_route" "private_app_nat" {
  count = var.enable_nat_gateway ? length(var.azs) : 0

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = (
    var.single_nat_gateway
    ? aws_nat_gateway.this[0].id
    : aws_nat_gateway.this[count.index].id
  )
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

##############################################################################
# Route Tables — Private Data (shares app route tables; separated for clarity)
##############################################################################
resource "aws_route_table" "private_data" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.environment}-${var.project}-rt-private-data-${var.azs[count.index]}"
  }
}

resource "aws_route" "private_data_nat" {
  count = var.enable_nat_gateway ? length(var.azs) : 0

  route_table_id         = aws_route_table.private_data[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = (
    var.single_nat_gateway
    ? aws_nat_gateway.this[0].id
    : aws_nat_gateway.this[count.index].id
  )
}

resource "aws_route_table_association" "private_data" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data[count.index].id
}

##############################################################################
# VPC Flow Logs
##############################################################################
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/${var.environment}-${var.project}-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = {
    Name = "${var.environment}-${var.project}-flow-logs"
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${var.environment}-${var.project}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.environment}-${var.project}-vpc-flow-logs-role"
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${var.environment}-${var.project}-vpc-flow-logs-policy"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id

  tags = {
    Name = "${var.environment}-${var.project}-flow-log"
  }
}

##############################################################################
# VPC Gateway Endpoint — S3
# Eliminates NAT Gateway data-processing costs for S3 traffic
##############################################################################
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.eu-west-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private_app[*].id,
    aws_route_table.private_data[*].id
  )

  tags = {
    Name = "${var.environment}-${var.project}-endpoint-s3"
  }
}

##############################################################################
# Security Group — ECR Endpoints (needed only when enable_ecr_endpoints = true)
##############################################################################
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_ecr_endpoints ? 1 : 0
  name        = "${var.environment}-${var.project}-sg-vpc-endpoints"
  description = "Allow HTTPS from within the VPC to reach Interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC CIDR to VPC endpoints"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.environment}-${var.project}-sg-vpc-endpoints"
  }
}

##############################################################################
# VPC Interface Endpoints — ECR API + ECR DKR
# Cuts NAT Gateway costs for container image pulls from private subnets
##############################################################################
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.eu-west-1.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.environment}-${var.project}-endpoint-ecr-api"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.eu-west-1.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.environment}-${var.project}-endpoint-ecr-dkr"
  }
}
