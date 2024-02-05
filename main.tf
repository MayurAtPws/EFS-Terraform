provider "aws" {
  region = "us-east-1"
}

variable "ami" {
  description = "AMI ID for EC2 instances. AMZN Linux on Nrth Vrgna"
  type        = string
  default     = "ami-0277155c3f0ab2930"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true    
  enable_dns_hostnames = true  

  tags = {
    Name = "may-efs-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "may-efs-igw"
  }
}

# Route Table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# Associate Subnet with Route Table
resource "aws_route_table_association" "route_assoc" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.route_table.id
}

#public-subnet
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "public-subnet-1"
  }
}

# SG for SSH access
resource "aws_security_group" "efs_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH traffic from any IP
  }

  ingress {
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow TCP traffic from any IP on ports 1024-65535
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"             # All protocols
    cidr_blocks = ["0.0.0.0/0"]    # Allow outbound traffic to all IPs
  }
}


# The EFS Resource
resource "aws_efs_file_system" "efs" {
  creation_token = "my-efs"
  performance_mode = "generalPurpose"
  throughput_mode = "elastic"
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name = "my-efs"
  }
}

resource "aws_efs_mount_target" "mount_target_1" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id = aws_subnet.subnet1.id
  security_groups = [aws_security_group.efs_sg.id]
}

# Instance 1
resource "aws_instance" "ec2_instance_1" {
  ami           = var.ami
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet1.id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.efs_sg.id]  
  user_data = <<-EOF
              #!/bin/bash
              sudoyum install -y nfs-utils
              sudo mkdir /mnt/efs
              sudo mount -t nfs4 ${aws_efs_mount_target.mount_target_1.dns_name}:/ /mnt/efs
              EOF
}

# Instance 2
resource "aws_instance" "ec2_instance_2" {
  ami           = var.ami
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet1.id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.efs_sg.id]  
  user_data = <<-EOF
              #!/bin/bash
              sudoyum install -y nfs-utils
              sudo mkdir /mnt/efs
              sudo mount -t nfs4 ${aws_efs_mount_target.mount_target_1.dns_name}:/ /mnt/efs
              EOF
}
