###############################################################################
# Data sources
###############################################################################

# Get the latest Amazon Linux 2023 AMI in the chosen region.
# Using a data source avoids hardcoding an AMI ID that may not exist in every region.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# First available AZ in the region. Single-AZ deployment is fine for a Minecraft server.
data "aws_availability_zones" "available" {
  state = "available"
}

###############################################################################
# SSH key pair
# Generated locally so the deployment is fully automated. Private key is written
# to ../minecraft-key.pem at the repo root for Ansible to use.
###############################################################################

resource "tls_private_key" "minecraft" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "minecraft" {
  key_name   = var.key_name
  public_key = tls_private_key.minecraft.public_key_openssh

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.minecraft.private_key_pem
  filename        = "${path.module}/../minecraft-key.pem"
  file_permission = "0400"
}

###############################################################################
# VPC and networking
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# Security group
# Two ingress rules: SSH (for Ansible) and Minecraft (for players).
# All egress allowed so the instance can pull Docker images and updates.
###############################################################################

resource "aws_security_group" "minecraft" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH for Ansible and Minecraft traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH for Ansible configuration"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Minecraft Java Edition"
    from_port   = var.minecraft_port
    to_port     = var.minecraft_port
    protocol    = "tcp"
    cidr_blocks = [var.minecraft_allowed_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

###############################################################################
# EC2 instance
# No user_data per assignment requirements; configuration happens via Ansible.
###############################################################################

resource "aws_instance" "minecraft" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.minecraft.id]
  key_name               = aws_key_pair.minecraft.key_name

  root_block_device {
    volume_size           = 16
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-server"
    Project = var.project_name
  }
}
