terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.0"
}

# VPC
resource "aws_vpc" "homelab" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "homelab-vpc" }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.homelab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags = { Name = "homelab-public" }
}

# Private subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.homelab.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
  tags = { Name = "homelab-private" }
}

# Internet Gateway
resource "aws_internet_gateway" "homelab" {
  vpc_id = aws_vpc.homelab.id
  tags = { Name = "homelab-igw" }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "homelab" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = { Name = "homelab-nat" }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.homelab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.homelab.id
  }
  tags = { Name = "homelab-public-rt" }
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.homelab.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.homelab.id
  }
  tags = { Name = "homelab-private-rt" }
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
  description = "Bastion host - SSH access"
  vpc_id      = aws_vpc.homelab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip, "52.94.76.0/22", "18.206.107.24/29"]
    description = "SSH from home IP, CloudShell, and EC2 Instance Connect"
  }

  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
    description     = "Node Exporter scraping from monitoring instance"
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
    description     = "RDP from bastion only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "homelab-windows-sg" }
}

# Monitoring security group
resource "aws_security_group" "monitoring" {
  name        = "homelab-monitoring-sg"
  description = "Prometheus and Grafana monitoring server"
  vpc_id      = aws_vpc.homelab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip, "52.94.76.0/22", "18.206.107.24/29"]
    description = "SSH from home IP, CloudShell, and EC2 Instance Connect"
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Grafana dashboard access"
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Prometheus UI access"
  }

  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Node Exporter metrics within VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "homelab-monitoring-sg" }
}

# Get latest Amazon Linux 2 AMI
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

# Get latest Windows Server 2022 AMI
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

# Reference existing key pair
data "aws_key_pair" "homelab" {
  key_name = "homelab-key"
}

# Account ID for S3 bucket naming
data "aws_caller_identity" "current" {}

# Bastion EC2
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = data.aws_key_pair.homelab.key_name

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    tar xvf node_exporter-1.7.0.linux-amd64.tar.gz
    mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

    cat > /etc/systemd/system/node_exporter.service << 'SVCEOF'
    [Unit]
    Description=Node Exporter
    After=network.target

    [Service]
    Type=simple
    User=ec2-user
    ExecStart=/usr/local/bin/node_exporter
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    systemctl daemon-reload
    systemctl start node_exporter
    systemctl enable node_exporter
  EOF

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

# Monitoring EC2
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  key_name               = data.aws_key_pair.homelab.key_name

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y wget tar

    # Install Prometheus
    wget https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-amd64.tar.gz
    tar xvf prometheus-2.51.0.linux-amd64.tar.gz
    mv prometheus-2.51.0.linux-amd64 /usr/local/prometheus

    # Configure Prometheus
    cat > /usr/local/prometheus/prometheus.yml << 'PROMEOF'
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - "alert_rules.yml"

    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
          - targets: ['localhost:9090']

      - job_name: 'bastion'
        static_configs:
          - targets: ['${aws_instance.bastion.private_ip}:9100']
        relabel_configs:
          - source_labels: [__address__]
            target_label: instance
            replacement: 'homelab-bastion'
    PROMEOF

    # Alert rules
    cat > /usr/local/prometheus/alert_rules.yml << 'ALERTEOF'
    groups:
      - name: homelab_alerts
        rules:
          - alert: HighCPUUsage
            expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) > 80
            for: 2m
            labels:
              severity: warning
            annotations:
              summary: "High CPU on {{ $labels.instance }}"
          - alert: InstanceDown
            expr: up == 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "{{ $labels.instance }} is down"
    ALERTEOF

    # Prometheus systemd service
    cat > /etc/systemd/system/prometheus.service << 'SVCEOF'
    [Unit]
    Description=Prometheus
    After=network.target

    [Service]
    Type=simple
    User=ec2-user
    ExecStart=/usr/local/prometheus/prometheus \
      --config.file=/usr/local/prometheus/prometheus.yml \
      --storage.tsdb.path=/usr/local/prometheus/data
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    # Install Grafana
    cat > /etc/yum.repos.d/grafana.repo << 'GRAFREPO'
    [grafana]
    name=grafana
    baseurl=https://packages.grafana.com/oss/rpm
    repo_gpgcheck=1
    enabled=1
    gpgcheck=1
    gpgkey=https://packages.grafana.com/gpg.key
    sslverify=1
    sslcacert=/etc/pki/tls/certs/ca-bundle.crt
    GRAFREPO

    yum install -y grafana

    systemctl daemon-reload
    systemctl start prometheus
    systemctl enable prometheus
    systemctl start grafana-server
    systemctl enable grafana-server
  EOF

  tags = { Name = "homelab-monitoring" }
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

# Custom least-privilege policy
resource "aws_iam_policy" "ec2_logs" {
  name = "homelab-ec2-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
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

# Attach custom policy
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

# Block public access
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
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