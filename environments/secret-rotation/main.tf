# ==============================================================================
# PRODUCTION ENVIRONMENT - KMS Encryption + Rotation
# ==============================================================================
# Demonstrates production-ready AWS Secrets Manager with:
# - S3 backend with state locking
# - Custom KMS encryption
# - Automatic secret rotation (Lambda created by module)

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
  
  # S3 backend for remote state storage
  # TODO: Add dynamodb_table for state locking in team environments
  backend "s3" {
    bucket  = "terraform-state-025215344334-ap-south-1"
    key     = "secrets/production/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
    # dynamodb_table = "terraform-state-lock"  # Enable for team use
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

# ==============================================================================
# Generate Secure Password
# ==============================================================================

resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ==============================================================================
# Production Database Credentials with KMS + Rotation
# ==============================================================================

module "database_secret" {
  source = "../../modules/aws-secrets"
  
  secret_name = "prod/database/credentials"
  description = "Production database credentials with KMS encryption and rotation"
  
  # KMS encryption enabled
  create_kms_key = true
  
  # Database credentials
  secret_value = jsonencode({
    username = var.db_master_username
    password = random_password.db_master.result
    host     = var.db_host
    port     = 5432
    dbname   = "production"
    engine   = "postgres"
  })
  
  # Enable rotation with auto-created Lambda
  enable_rotation        = true
  create_rotation_lambda = true
  rotation_days          = 30
  
  # 7 days recovery window (shorter for testing)
  recovery_window_days = 7
  
  tags = {
    Name        = "database-credentials"
    Criticality = "high"
  }
}

# ==============================================================================
# Outputs
# ==============================================================================

output "secret_arn" {
  description = "ARN of the database secret"
  value       = module.database_secret.secret_arn
}

output "kms_key_arn" {
  description = "KMS key ARN"
  value       = module.database_secret.kms_key_arn
}
