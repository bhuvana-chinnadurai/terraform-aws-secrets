# ==============================================================================
# TEST ENVIRONMENT - Basic Secret Example
# ==============================================================================
# Simple secret without advanced production features
# Use this to validate the module works

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  
  # Local backend for test - state on your machine
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = "ap-south-1"
  
  default_tags {
    tags = {
      Environment = "test"
      ManagedBy   = "terraform"
    }
  }
}

# ==============================================================================
# Basic Secret (No Rotation, No Cross-Account)
# ==============================================================================

module "test_secret" {
  source = "../../modules/aws-secrets"
  
  secret_name = "test/basic-secret"
  description = "Test secret for validation"
  
  # AWS default encryption (no custom KMS key)
  create_kms_key = false
  
  # Simple test value
  secret_value = jsonencode({
    username = "testuser"
    password = "test-password-123"
  })
  
  # No rotation
  enable_rotation = false
  
  # Immediate deletion for easy cleanup
  recovery_window_days = 0
  
  tags = {
    Purpose = "testing"
  }
}

# ==============================================================================
# Outputs
# ==============================================================================

output "secret_arn" {
  value = module.test_secret.secret_arn
}



