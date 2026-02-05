# ==============================================================================
# REQUIRED VARIABLES
# ==============================================================================

variable "secret_name" {
  description = "Name of the secret. Must be unique within your AWS account in the region."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]+$", var.secret_name))
    error_message = "Secret name can only contain alphanumeric characters and /_+=.@- characters"
  }

  validation {
    condition     = length(var.secret_name) <= 512
    error_message = "Secret name must be 512 characters or less"
  }
}

# ==============================================================================
# OPTIONAL VARIABLES - Secret Configuration
# ==============================================================================

variable "description" {
  description = "Description of the secret"
  type        = string
  default     = null
}

variable "secret_value" {
  description = "The secret value to store. If not provided, secret must be set manually via AWS console or CLI. Use sensitive variables in your root module."
  type        = string
  default     = null
  sensitive   = true
}

variable "secret_binary" {
  description = "Binary secret value (base64 encoded). Use this for non-text secrets like certificates."
  type        = string
  default     = null
  sensitive   = true
}

variable "use_name_prefix" {
  description = "Whether to use name_prefix instead of name. Useful to avoid naming conflicts when multiple engineers provision resources."
  type        = bool
  default     = false
}

# ==============================================================================
# OPTIONAL VARIABLES - Encryption
# ==============================================================================

variable "kms_key_id" {
  description = "ARN or ID of the KMS key to encrypt the secret. If not specified, uses the default AWS-managed key (aws/secretsmanager)."
  type        = string
  default     = null
}

variable "create_kms_key" {
  description = "Whether to create a dedicated KMS key for this secret. Recommended for compliance requirements or cross-account access."
  type        = bool
  default     = false
}

variable "kms_deletion_window" {
  description = "Duration in days before KMS key deletion (7-30 days). Only used if create_kms_key = true."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days"
  }
}

# ==============================================================================
# OPTIONAL VARIABLES - Secret Rotation
# ==============================================================================

variable "enable_rotation" {
  description = "Whether to enable automatic secret rotation."
  type        = bool
  default     = false
}

variable "create_rotation_lambda" {
  description = "Whether to create the rotation Lambda function. If false, rotation_lambda_arn must be provided."
  type        = bool
  default     = true
}

variable "rotation_lambda_arn" {
  description = "ARN of an existing Lambda function to use for secret rotation. Only used if create_rotation_lambda = false."
  type        = string
  default     = null
}

variable "rotation_days" {
  description = "Number of days between automatic secret rotations"
  type        = number
  default     = 30

  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365
    error_message = "Rotation days must be between 1 and 365"
  }
}

variable "rotation_vpc_config" {
  description = "VPC configuration for the rotation Lambda (required if database is in VPC)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "rotation_lambda_timeout" {
  description = "Lambda timeout for rotation function in seconds."
  type        = number
  default     = 30

  validation {
    condition     = var.rotation_lambda_timeout >= 10 && var.rotation_lambda_timeout <= 900
    error_message = "Lambda timeout must be between 10 seconds and 15 minutes"
  }
}

# ==============================================================================
# OPTIONAL VARIABLES - Lifecycle & Recovery
# ==============================================================================

variable "recovery_window_days" {
  description = "Number of days AWS Secrets Manager waits before permanently deleting the secret. Set to 0 to delete immediately (not recommended for production)."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_days == 0 || (var.recovery_window_days >= 7 && var.recovery_window_days <= 30)
    error_message = "Recovery window must be 0 (force delete) or between 7 and 30 days"
  }
}

variable "force_overwrite_replica_secret" {
  description = "Whether to overwrite a secret with the same name in replica regions"
  type        = bool
  default     = false
}


# ==============================================================================
# OPTIONAL VARIABLES - Replication (Advanced)
# ==============================================================================

variable "replica_regions" {
  description = "List of AWS regions to replicate this secret to for disaster recovery"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for region in var.replica_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", region))
    ])
    error_message = "All replica regions must be valid AWS region names (e.g., us-west-2, eu-west-1)"
  }
}

# ==============================================================================
# OPTIONAL VARIABLES - Tagging
# ==============================================================================

variable "tags" {
  description = "Tags to apply to the secret. Will be merged with default tags (ManagedBy, Module)."
  type        = map(string)
  default     = {}
}
