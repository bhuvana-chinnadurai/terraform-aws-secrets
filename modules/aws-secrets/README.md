# AWS Secrets Manager Terraform Module

This module provides a production-ready implementation of AWS Secrets Manager with support for:

- **KMS Encryption**: Custom or AWS-managed KMS keys
- **Secret Rotation**: Automatic rotation with Lambda integration
- **Cross-Account Access**: Resource policies for multi-account architectures
- **Multi-Region Replication**: Disaster recovery support
- **IAM Integration**: Fine-grained access policies

## Usage

```hcl
module "database_secret" {
  source = "../../modules/aws-secrets"

  secret_name = "prod/db/master-password"
  description = "Production database master password"
  
  # Enable KMS encryption
  create_kms_key = true
  
  # Optional: Set initial value
  secret_value = jsonencode({
    username = "admin"
    password = "change-me"
  })
  
  # Enable rotation
  enable_rotation     = true
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_days       = 30
  
  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 4.0 |

## Inputs

See [variables.tf](./variables.tf) for all available inputs.

## Outputs

See [outputs.tf](./outputs.tf) for all available outputs.

## Security Best Practices

1. **Always use KMS encryption** for production secrets
2. **Enable rotation** for database credentials and API keys
3. **Use least privilege IAM** policies
4. **Enable CloudWatch logging** for audit trails
5. **Set `prevent_destroy = true`** for production secrets
