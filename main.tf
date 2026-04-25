# VPC
resource "aws_vpc" "homelab" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "homelab-vpc"
  }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.homelab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "homelab-public"
  }
}

# Private subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.homelab.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "homelab-private"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "homelab" {
  vpc_id = aws_vpc.homelab.id

  tags = {
    Name = "homelab-igw"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "homelab" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "homelab-nat"
  }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.homelab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.homelab.id
  }

  tags = {
    Name = "homelab-public-rt"
  }
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.homelab.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.homelab.id
  }

  tags = {
    Name = "homelab-private-rt"
  }
}

# Route table associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Bastion security group
resource "aws_security_group" "bastion" {
  name        = "homelab-bastion-sg"
  description = "Bastion host - SSH from my IP only"
  vpc_id      = aws_vpc.homelab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["18.206.107.24/29"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "homelab-bastion-sg" }
}

# Windows Server security group
resource "aws_security_group" "windows" {
  name        = "homelab-windows-sg"
  description = "Windows Server - RDP from bastion only"
  vpc_id      = aws_vpc.homelab.id

  ingress {
    from_port       = 3389
    to_port         = 3389
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "homelab-windows-sg" }
}

# Reference existing key pair
data "aws_key_pair" "homelab" {
  key_name = "homelab-key"
}

# Get latest Amazon Linux 2 AMI automatically
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get latest Windows Server 2022 AMI automatically
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Bastion EC2
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = data.aws_key_pair.homelab.key_name

  tags = { Name = "homelab-bastion" }
}

# Windows Server EC2
resource "aws_instance" "windows" {
  ami                    = data.aws_ami.windows.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.windows.id]
  key_name               = data.aws_key_pair.homelab.key_name
  iam_instance_profile   = aws_iam_instance_profile.cloudwatch.name

  tags = { Name = "homelab-windows" }
}

# CloudWatch IAM role
resource "aws_iam_role" "cloudwatch" {
  name = "homelab-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "homelab-cloudwatch-role" }
}

# Attach CloudWatch agent policy
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom least-privilege policy for S3 log access
resource "aws_iam_policy" "ec2_logs" {
  name = "homelab-ec2-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = "arn:aws:s3:::${aws_s3_bucket.logs.bucket}/logs/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach custom policy to role
resource "aws_iam_role_policy_attachment" "ec2_logs" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = aws_iam_policy.ec2_logs.arn
}

# Instance profile
resource "aws_iam_instance_profile" "cloudwatch" {
  name = "homelab-cloudwatch-profile"
  role = aws_iam_role.cloudwatch.name
}



# S3 log bucket
resource "aws_s3_bucket" "logs" {
  bucket = "homelab-logs-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "homelab-logs" }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 30 day lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "ExpireLogs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = 30
    }
  }
}

# Data source for account ID
data "aws_caller_identity" "current" {}