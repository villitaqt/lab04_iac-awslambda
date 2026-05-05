terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = var.aws_region
  profile = "admin" # mi perfil de aws-cli con permisos para crear recursos

  default_tags {
    tags = {
      Environment = terraform.workspace
      Project     = "ImageProcessor"
      ManagedBy   = "Terraform"
    }
  }
}