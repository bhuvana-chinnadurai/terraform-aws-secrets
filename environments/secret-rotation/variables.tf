# Production Environment Variables

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "db_master_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
}

variable "db_host" {
  description = "Database host"
  type        = string
  default     = "prod-db.example.com"
}

variable "cross_account_principals" {
  description = "AWS accounts that can access secrets (cross-account)"
  type        = list(string)
  default     = []
  # Example: ["arn:aws:iam::999999999999:root"]
}
