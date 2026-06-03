# VPC Networking — eu-west-1 (Ireland)

Full Terraform module for a production-grade VPC with 3-tier subnets across 3 AZs.

## Directory layout

```
vpc-eu-west-1/
├── modules/
│   └── vpc/
│       ├── main.tf          # All VPC resources
│       ├── variables.tf     # Inputs with validation
│       ├── outputs.tf       # Outputs for callers
│       └── versions.tf      # Provider pinning
└── environments/
    ├── dev/
    │   ├── main.tf          # Dev — single NAT, shorter log retention
    │   └── outputs.tf
    └── prod/
        ├── main.tf          # Prod — HA NAT (one per AZ), ECR endpoints
        └── outputs.tf
```

## What gets created

| Resource | Count (per env) | Notes |
|---|---|---|
| VPC | 1 | DNS hostnames + resolution enabled |
| Internet Gateway | 1 | Attached to VPC |
| Public subnets | 3 (one per AZ) | `/19` each — houses ALBs, NAT GWs |
| Private-app subnets | 3 (one per AZ) | `/19` each — houses workloads (EKS/ECS/EC2) |
| Private-data subnets | 3 (one per AZ) | `/19` each — houses RDS, ElastiCache |
| NAT Gateways | 1 (dev) / 3 (prod) | HA in prod, single for cost in dev |
| Elastic IPs | 1 (dev) / 3 (prod) | One per NAT Gateway |
| Route tables | 7 total | 1 public + 3 private-app + 3 private-data |
| VPC Flow Logs | 1 | CloudWatch, 14d (dev) / 90d (prod) |
| S3 Gateway Endpoint | 1 | Cuts NAT data costs for S3 traffic |
| ECR Interface Endpoints | 0 (dev) / 2 (prod) | ECR API + ECR DKR |

### CIDR allocation

```
Dev VPC:  10.10.0.0/16
Prod VPC: 10.20.0.0/16

Subnet layout per env (replace 10.XX with the VPC base):
  Public         eu-west-1a  10.XX.0.0/19
  Public         eu-west-1b  10.XX.32.0/19
  Public         eu-west-1c  10.XX.64.0/19
  Private-app    eu-west-1a  10.XX.96.0/19
  Private-app    eu-west-1b  10.XX.128.0/19
  Private-app    eu-west-1c  10.XX.160.0/19
  Private-data   eu-west-1a  10.XX.192.0/19
  Private-data   eu-west-1b  10.XX.224.0/19
  Private-data   eu-west-1c  10.XX.240.0/19
```

---

## Step-by-step deploy guide

### Prerequisites

- AWS CLI configured with credentials for the target account
- Terraform >= 1.6.0 installed
- An S3 bucket and DynamoDB table for remote state already exist

### Step 1 — Create the remote state bucket and lock table (one-off)

```bash
# State bucket
aws s3api create-bucket \
  --bucket myorg-tfstate-eu-west-1 \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

aws s3api put-bucket-versioning \
  --bucket myorg-tfstate-eu-west-1 \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket myorg-tfstate-eu-west-1 \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket myorg-tfstate-eu-west-1 \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# DynamoDB lock table
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-1
```

### Step 2 — Update placeholder values

In `environments/dev/main.tf` and `environments/prod/main.tf`, replace:

| Placeholder | Replace with |
|---|---|
| `myorg-tfstate-eu-west-1` | Your state bucket name |
| `terraform-locks` | Your DynamoDB table name |
| `my-project` | Your project name |
| `platform-team` | Your team name |
| `cc-1234` | Your cost centre code |

### Step 3 — Deploy Dev

```bash
cd environments/dev

terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Review the plan carefully before applying. Key things to check:
- NAT Gateway count (should be 1 for dev)
- CIDR ranges don't conflict with existing VPCs
- Tags look correct

### Step 4 — Deploy Prod

```bash
cd environments/prod

terraform init
terraform validate
terraform plan -out=tfplan

# Review carefully — prod has 3 NAT Gateways and ECR endpoints
terraform apply tfplan
```

> ⚠️ **Never run `terraform apply --auto-approve` in prod.** Always inspect the plan first.

### Step 5 — Verify

```bash
# Confirm VPC exists
aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=prod" \
  --region eu-west-1 \
  --query 'Vpcs[*].{ID:VpcId,CIDR:CidrBlock,State:State}'

# Confirm subnets
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<your-vpc-id>" \
  --region eu-west-1 \
  --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Tier:Tags[?Key==`Tier`].Value|[0]}'

# Confirm NAT Gateways
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=<your-vpc-id>" \
  --region eu-west-1 \
  --query 'NatGateways[*].{ID:NatGatewayId,State:State,PublicIP:NatGatewayAddresses[0].PublicIp}'
```

---

## Cost watch-outs

| Resource | Approx cost (eu-west-1) |
|---|---|
| NAT Gateway (idle) | ~$35/month each |
| NAT Gateway data processing | $0.048/GB |
| VPC Flow Logs (CloudWatch) | ~$0.50/GB ingested |
| ECR Interface Endpoints | ~$7/month each (2 = ~$14/month) |
| S3 Gateway Endpoint | **Free** |

**Dev**: 1x NAT ≈ $35/month  
**Prod**: 3x NAT + 2x ECR endpoints ≈ $119/month baseline + data charges

---

## Extending this module

To add resources that consume this VPC (EKS, ECS, RDS), call the module outputs:

```hcl
module "eks" {
  source = "../../modules/eks"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_app_subnet_ids
  ...
}
```
