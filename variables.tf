variable "aws_region" {
  description = "La región de AWS"
  type        = string
}

variable "vpc_cidr_blocks" {
  description = "Mapa de IPs para la VPC según el entorno"
  type        = map(string)
}