terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Descobre as zonas de disponibilidade da região
data "aws_availability_zones" "disponiveis" {
  state = "available"
}

locals {
  nome             = "portfolio"
  azs              = slice(data.aws_availability_zones.disponiveis.names, 0, 2)
  subnets_publicas = ["10.0.1.0/24", "10.0.2.0/24"]
  subnets_privadas = ["10.0.11.0/24", "10.0.12.0/24"]
}

# 1. A rede
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.nome}-vpc" }
}

# 2. A "portaria" para a internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.nome}-igw" }
}

# 3. Sub-redes públicas (uma por zona)
resource "aws_subnet" "publica" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.subnets_publicas[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.nome}-publica-${count.index + 1}" }
}

# 4. Sub-redes privadas (uma por zona)
resource "aws_subnet" "privada" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.subnets_privadas[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${local.nome}-privada-${count.index + 1}" }
}

# 5. Rota das sub-redes públicas: tudo que não é interno vai para a internet
resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.nome}-rotas-publicas" }
}

# 6. Rota das sub-redes privadas: só tráfego interno da VPC
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.nome}-rotas-privadas" }
}

# 7. Liga cada sub-rede à sua tabela de rotas
resource "aws_route_table_association" "publica" {
  count          = 2
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

resource "aws_route_table_association" "privada" {
  count          = 2
  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada.id
}

# 8. Firewall para um futuro servidor web
resource "aws_security_group" "web" {
  name        = "${local.nome}-web-sg"
  description = "Permite HTTP e HTTPS de entrada"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Saida liberada"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.nome}-web-sg" }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnets_publicas" {
  value = aws_subnet.publica[*].id
}

output "subnets_privadas" {
  value = aws_subnet.privada[*].id
}