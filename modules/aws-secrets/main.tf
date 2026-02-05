# ==============================================================================
# Data Sources
# ==============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ==============================================================================
# AWS Secrets Manager Secret
# ==============================================================================

resource "aws_secretsmanager_secret" "this" {
  # Use name_prefix for uniqueness or exact name
  name_prefix = var.use_name_prefix ? "${var.secret_name}-" : null
  name        = var.use_name_prefix ? null : var.secret_name

  description = var.description

  # KMS encryption: use custom key if provided, created key if create_kms_key=true, or AWS-managed default
  kms_key_id = var.kms_key_id != null ? var.kms_key_id : (var.create_kms_key ? aws_kms_key.this[0].id : null)

  # Recovery window: 30 days by default (maximum safety)
  # Set to 0 for immediate deletion (only for non-production testing)
  recovery_window_in_days = var.recovery_window_days

  # Force overwrite for replica secrets
  force_overwrite_replica_secret = var.force_overwrite_replica_secret

  # Multi-region replication using dynamic block
  dynamic "replica" {
    for_each = toset(var.replica_regions)
    content {
      region = replica.value
    }
  }

  # Merge user tags with module metadata
  tags = merge(
    var.tags,
    {
      ManagedBy = "terraform"
      Module    = "terraform-aws-secrets"
    }
  )

  # Prevent accidental deletion via Terraform
  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

# ==============================================================================
# Secret Version (Initial Value)
# ==============================================================================

# Store initial secret value if provided
# If not provided, users must set value manually via AWS Console or CLI
resource "aws_secretsmanager_secret_version" "this" {
  # Always create a version - the caller decides whether to pass secret_value
  # This avoids "count cannot be determined until apply" errors when
  # secret_value contains dynamic content like random_password.result
  count = 1

  secret_id = aws_secretsmanager_secret.this.id

  # Support both text and binary secrets
  secret_string = var.secret_value
  secret_binary = var.secret_binary != null ? base64decode(var.secret_binary) : null

  lifecycle {
    # Ignore changes to secret value after initial creation
    # This prevents Terraform from overwriting rotated secrets
    ignore_changes = [secret_string, secret_binary]
  }
}

# ==============================================================================
# Secret Rotation Configuration
# ==============================================================================

# Determine which Lambda ARN to use for rotation
locals {
  rotation_lambda_arn = var.enable_rotation ? (
    var.create_rotation_lambda ? aws_lambda_function.rotation[0].arn : var.rotation_lambda_arn
  ) : null
}

# Enable automatic rotation if configured
resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.enable_rotation ? 1 : 0

  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = local.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  # Ensure secret version and Lambda exist before enabling rotation
  depends_on = [
    aws_secretsmanager_secret_version.this,
    aws_lambda_function.rotation,
    aws_lambda_permission.secrets_manager
  ]
}

# Grant external Lambda permission to rotate this secret (only if using external Lambda)
resource "aws_lambda_permission" "allow_secretsmanager" {
  count = var.enable_rotation && !var.create_rotation_lambda && var.rotation_lambda_arn != null ? 1 : 0

  statement_id  = "AllowSecretsManagerInvoke-${replace(var.secret_name, "/", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = var.rotation_lambda_arn
  principal     = "secretsmanager.amazonaws.com"

  # Only allow invocations for this specific secret
  source_arn = aws_secretsmanager_secret.this.arn
}

# Note: Multi-region replication is now handled via the dynamic "replica" block
# in the aws_secretsmanager_secret resource above (lines 22-27)

# ==============================================================================
# NOTES & TODOs
# ==============================================================================

# TODO: Add aws_secretsmanager_secret_policy for cross-account access
# Example use case: Allow another AWS account to read this secret
#
# resource "aws_secretsmanager_secret_policy" "cross_account" {
#   secret_arn = aws_secretsmanager_secret.this.arn
#   policy = jsonencode({
#     Statement = [{
#       Effect = "Allow"
#       Principal = { AWS = "arn:aws:iam::999999999:root" }
#       Action = ["secretsmanager:GetSecretValue"]
#       Resource = "*"
#       Condition = {
#         StringEquals = {
#           "secretsmanager:VersionStage" = "AWSCURRENT"
#         }
#       }
#     }]
#   })
# }

# TODO: Add CloudWatch monitoring for rotation failures
# resource "aws_cloudwatch_metric_alarm" "rotation_failed" {
#   alarm_name = "secret-rotation-failed-${var.secret_name}"
#   metric_name = "RotationFailed"
#   namespace = "AWS/SecretsManager"
# }
