# ==========================================
# 1. VPC PRINCIPAL
# ==========================================
resource "aws_vpc" "main" {
  # Extrae la IP del mapa en terraform.tfvars según el workspace (dev, qa, prod)
  cidr_block           = var.vpc_cidr_blocks[terraform.workspace]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-image-processor-${terraform.workspace}"
  }
}

# ==========================================
# 2. INTERNET GATEWAY
# ==========================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw-${terraform.workspace}"
  }
}

# ==========================================
# 3. SUBREDES PÚBLICAS (AZ-a y AZ-b)
# ==========================================
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 1) # Ej: 10.x.1.0/24
  availability_zone = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "pub-sub-a-${terraform.workspace}" }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 2) # Ej: 10.x.2.0/24
  availability_zone = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = { Name = "pub-sub-b-${terraform.workspace}" }
}

# ==========================================
# 4. SUBREDES PRIVADAS (AZ-a y AZ-b)
# ==========================================
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 11) # Ej: 10.x.11.0/24
  availability_zone = "${var.aws_region}a"

  tags = { Name = "priv-sub-a-${terraform.workspace}" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 12) # Ej: 10.x.12.0/24
  availability_zone = "${var.aws_region}b"

  tags = { Name = "priv-sub-b-${terraform.workspace}" }
}