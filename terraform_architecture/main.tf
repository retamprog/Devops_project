# -------------------------
# Provider Configuration
# -------------------------

provider "aws" {
  region = "ap-south-1"
}

locals {
  key_name = "default_key"
}

# -------------------------
# Networking
# -------------------------
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = { Name = "Terraform_vpc" }
}

resource "aws_subnet" "public_sub" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "ap-south-1a"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "Public" }
}

resource "aws_subnet" "private_sub" {
  vpc_id            = aws_vpc.vpc.id
  availability_zone = "ap-south-1b"
  cidr_block        = "10.0.2.0/24"
  tags = { Name = "Private" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "public_igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Public_rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_sub.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "eip" {
  domain = "vpc"
  tags   = { Name = "personal_eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public_sub.id
  tags          = { Name = "nat_gw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "Private_rt" }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_sub.id
  route_table_id = aws_route_table.private_rt.id
}

# -------------------------
# Security Groups
# -------------------------
resource "aws_security_group" "frontend_sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "frontend-sg"

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from anywhere (bastion)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "frontend-sg" }
}

resource "aws_security_group" "backend_sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "backend-sg"

  ingress {
    description     = "Allow HTTP backend port from frontend subnet"
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    cidr_blocks     = ["10.0.1.0/24"]
  }

  ingress {
    description     = "Allow SSH from frontend SG"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "backend-sg" }
}

# -------------------------
# EC2 Instances
# -------------------------
resource "aws_instance" "backend" {
  ami                    = "ami-0f918f7e67a3323f0" # Ubuntu 22.04 LTS
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_sub.id
  vpc_security_group_ids = [aws_security_group.backend_sg.id]
  key_name               = local.key_name

  user_data = <<-EOF
              #!/bin/bash
              sleep 30
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              docker pull retam/my-backend:latest
              docker run -d --name backend -p 3001:3001 retam/my-backend:latest
              EOF

  tags = { Name = "Backend" }
}

resource "aws_instance" "frontend" {
  ami                         = "ami-0f918f7e67a3323f0" # Ubuntu 22.04 LTS
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_sub.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.frontend_sg.id]
  key_name                    = local.key_name
  depends_on=[aws_instance.backend]

  user_data = <<-EOF
              #!/bin/bash
              sleep 30
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              BACKEND_IP=${aws_instance.backend.private_ip}
              docker pull retam/my-frontend:latest
              docker run -d --name frontend -p 80:80 -e BACKEND_URL=http://$BACKEND_IP:3001 retam/my-frontend:latest
              EOF


  tags = { Name = "Frontend" }
}

# -------------------------
# Outputs
# -------------------------
output "frontend_public_ip" {
  value = aws_instance.frontend.public_ip
}

output "backend_private_ip" {
  value = aws_instance.backend.private_ip
}
