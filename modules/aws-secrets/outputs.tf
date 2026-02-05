# ==============================================================================
# Secret Output
# ==============================================================================

output "secret_arn" {
  description = "ARN of the secret. Use in IAM policies, Terraform refs, and application SDK (GetSecretValue accepts ARN)."
  value       = aws_secretsmanager_secret.this.arn
}

# ==============================================================================
# KMS Output
# ==============================================================================

output "kms_key_arn" {
  description = "ARN of the KMS key (if custom key was created)."
  value       = var.create_kms_key ? aws_kms_key.this[0].arn : null
}

