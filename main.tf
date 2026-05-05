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





# ==========================================
# 9. AMAZON S3 (Almacenamiento)
# ==========================================
# Obtenemos el ID de cuenta automáticamente para el nombre del bucket
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "images" {
  bucket = "image-processor-${terraform.workspace}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Permite borrar el bucket aunque tenga archivos al hacer destroy
}

# Bloque de configuración para carpetas (uploads/ y processed/) se maneja vía código Lambda,
# pero habilitamos versiones y cifrado como pide el diagrama.
resource "aws_s3_bucket_versioning" "images_versioning" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images_crypto" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# ==========================================
# 10. AMAZON SQS (Mensajería)
# ==========================================
resource "aws_sqs_queue" "image_dlq" {
  name                      = "image-processor-${terraform.workspace}-dlq"
  message_retention_seconds = 1209600 # 14 días
}

resource "aws_sqs_queue" "image_queue" {
  name                      = "image-processor-${terraform.workspace}-queue"
  visibility_timeout_seconds = 360 # 6x el timeout de la Lambda (60s)
  message_retention_seconds  = 86400 # 1 día
  receive_wait_time_seconds  = 20    # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount     = 3
  })
}

# ==========================================
# 11. VPC ENDPOINTS (Tráfico Privado)
# ==========================================
# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id
  ]
  tags = { Name = "vpce-s3-${terraform.workspace}" }
}

# SQS Interface Endpoint (Requiere Security Group)
resource "aws_security_group" "vpce_sqs" {
  # Cambiamos "sg-vpce-sqs" por "sec-group-sqs" o simplemente "vpce-sqs"
  name        = "vpce-sqs-sg-${terraform.workspace}" 
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = { Name = "sg-vpce-sqs-${terraform.workspace}" }
}

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpce_sqs.id]
  tags                = { Name = "vpce-sqs-${terraform.workspace}" }
}


# ==========================================
# 12. VARIABLES ADICIONALES (Mapas de potencia)
# ==========================================
variable "crop_lambda_memory" {
  type    = map(number)
  default = {
    dev  = 128
    qa   = 256
    prod = 512 # Lo que pide tu diagrama
  }
}

# ==========================================
# 13. IAM ROLES (Permisos)
# ==========================================
# Rol para la Lambda de Carga (Upload)
resource "aws_iam_role" "upload_role" {
  name = "upload-lambda-role-${terraform.workspace}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Permiso para escribir en S3 y Logs (Esencial)
resource "aws_iam_role_policy_attachment" "upload_vpc" {
  role       = aws_iam_role.upload_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ==========================================
# 14. LAMBDA FUNCTIONS (Cómputo)
# ==========================================
# Lambda 1: Upload
resource "aws_lambda_function" "upload_lambda" {
  function_name = "upload-lambda-${terraform.workspace}"
  role          = aws_iam_role.upload_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  filename      = "upload.zip" # Crearemos este archivo pronto

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.vpce_sqs.id] # Reutilizamos el SG de la red
  }

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.images.id
    }
  }
}

# ==========================================
# 15. API GATEWAY (La Puerta de Entrada)
# ==========================================
resource "aws_apigatewayv2_api" "http_api" {
  name          = "image-api-${terraform.workspace}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# Integración de la Lambda con el API
resource "aws_apigatewayv2_integration" "lambda_inst" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.upload_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "upload_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_inst.id}"
}

# Permiso para que el API Gateway pueda llamar a la Lambda
resource "aws_lambda_permission" "api_gw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}