# ==============================================================================
# Optional KMS Key for Secret Encryption
# ==============================================================================

# Create a dedicated KMS key if requested
# Recommended for:
# - Compliance requirements (GDPR Article 32, SOC2)
# - Cross-account secret sharing
# - Audit trail of decrypt operations via CloudTrail
# - Granular access control

resource "aws_kms_key" "this" {
  count = var.create_kms_key ? 1 : 0

  description             = "Encryption key for secret: ${var.secret_name}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true # Best practice: rotate key material annually

  # Key policy allowing Secrets Manager service and current identity to use the key
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Key Administrators"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager to use the key"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.id}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "${var.secret_name}-kms-key"
      ManagedBy = "terraform"
      Purpose   = "secrets-manager-encryption"
    }
  )
}

# KMS key alias for easier identification
resource "aws_kms_alias" "this" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${replace(var.secret_name, "/", "-")}"
  target_key_id = aws_kms_key.this[0].key_id
}

# ==============================================================================
# TODOs & Production Considerations
# ==============================================================================

# TODO: Add KMS key policy for cross-account access
# Example: Allow another AWS account to decrypt secrets
#
# {
#   Sid = "Allow cross-account decrypt"
#   Effect = "Allow"
#   Principal = {
#     AWS = "arn:aws:iam::999999999:root"
#   }
#   Action = [
#     "kms:Decrypt",
#     "kms:DescribeKey"
#   ]
#   Resource = "*"
# }

# TODO: Add KMS grants for Lambda rotation function
# Grants provide temporary, granular permissions without modifying key policy
#
# resource "aws_kms_grant" "rotation_lambda" {
#   count = var.enable_rotation && var.create_kms_key ? 1 : 0
#
#   key_id            = aws_kms_key.this[0].key_id
#   grantee_principal = aws_lambda_function.rotation.arn
#   operations = [
#     "Decrypt",
#     "Encrypt",
#     "GenerateDataKey"
#   ]
# }

# TODO: Support multi-region KMS keys for replicated secrets
# resource "aws_kms_replica_key" "replica" {
#   for_each = toset(var.replica_regions)
#
#   description             = "Replica key for ${var.secret_name} in ${each.value}"
#   primary_key_arn         = aws_kms_key.this[0].arn
#   deletion_window_in_days = var.kms_deletion_window
# }

# ==============================================================================
# Cost Considerations
# ==============================================================================

# KMS Custom Keys Cost:
# - $1/month per key
# - $0.03 per 10,000 requests
# - Automatic key rotation: No additional cost
#
# When to use custom KMS key vs AWS-managed:
# - Simple secrets → Use AWS-managed (free)
# - Compliance/audit requirements → Use custom key
# - Cross-account access → Use custom key
# - High volume (>1M requests/month) → Consider cost
