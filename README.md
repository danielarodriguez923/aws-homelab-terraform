# AWS Homelab — Infrastructure as Code (Phase 2)

A fully Terraform-managed AWS environment built to develop Cloud Operations 
and SRE skills. This repo contains the complete infrastructure as code for 
the homelab environment documented in Phase 1.

## Architecture

- Multi-tier VPC with public and private subnets
- Internet Gateway for public subnet outbound traffic
- NAT Gateway for private subnet outbound-only access
- Bastion host in public subnet for secure jump access
- Windows Server in private subnet running Active Directory
- Security groups enforcing least-privilege access
- IAM roles and instance profiles for CloudWatch agent
- S3 log bucket with public access blocked and 30-day lifecycle policy

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- AWS key pair named `homelab-key` created in your account

## Usage

**Clone the repo:**
```bash
git clone https://github.com/danielarodriguez923/aws-homelab-terraform.git
cd aws-homelab-terraform
```

**Update your IP in terraform.tfvars:**
```hcl
my_ip = "YOUR_HOME_IP/32"
```

**Initialize and deploy:**
```bash
terraform init
terraform plan
terraform apply
```

**Outputs after apply:**
```
bastion_public_ip    = "x.x.x.x"
windows_private_ip   = "10.0.2.x"
s3_bucket_name       = "homelab-logs-ACCOUNT_ID"
vpc_id               = "vpc-xxxxxxxxx"
```

**Tear down when done:**
```bash
terraform destroy
```

## Resources Managed

| Resource | Description |
|---|---|
| `aws_vpc` | Main VPC — 10.0.0.0/16 |
| `aws_subnet` (x2) | Public (10.0.1.0/24) and private (10.0.2.0/24) |
| `aws_internet_gateway` | IGW for public subnet |
| `aws_eip` + `aws_nat_gateway` | NAT Gateway for private subnet outbound |
| `aws_route_table` (x2) | Separate routing for public and private subnets |
| `aws_security_group` (x2) | Bastion and Windows Server security groups |
| `aws_instance` (x2) | Amazon Linux 2 bastion, Windows Server 2022 |
| `aws_iam_role` | CloudWatch agent role with least-privilege policy |
| `aws_s3_bucket` | Log storage with lifecycle and public access block |

## Key Learnings

- Terraform state management and importing existing resources
- Automatic AMI lookups via data sources — no hardcoded IDs
- Infrastructure lifecycle — apply, destroy, rebuild from code
- Separating sensitive values into tfvars excluded from version control
- Least-privilege IAM design for EC2 instance profiles

## Homelab Phases

- [x] Phase 1 — Core AWS Infrastructure
- [x] Phase 2 — Terraform (this repo)
- [ ] Phase 3 — Prometheus and Grafana
- [ ] Phase 4 — Containers and Kubernetes
- [ ] Phase 5 — Automation and Scripting
