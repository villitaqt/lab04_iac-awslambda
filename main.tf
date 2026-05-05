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


# ==========================================
# 5. ELASTIC IPs PARA NAT GATEWAYS
# ==========================================
resource "aws_eip" "nat_a" { domain = "vpc" }
resource "aws_eip" "nat_b" { domain = "vpc" }

# ==========================================
# 6. NAT GATEWAYS (En subredes públicas)
# ==========================================
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "nat-a-${terraform.workspace}" }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  tags          = { Name = "nat-b-${terraform.workspace}" }
}

# ==========================================
# 7. TABLAS DE RUTEO
# ==========================================

# Tabla Pública (Va al Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "rt-public-${terraform.workspace}" }
}

# Tabla Privada A (Va al NAT A)
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
  tags = { Name = "rt-priv-a-${terraform.workspace}" }
}

# Tabla Privada B (Va al NAT B)
resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  tags = { Name = "rt-priv-b-${terraform.workspace}" }
}

# ==========================================
# 8. ASOCIACIONES (Conectar tablas con subredes)
# ==========================================
resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "priv_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "priv_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}