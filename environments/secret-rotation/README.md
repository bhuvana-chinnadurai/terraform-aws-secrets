# Production Environment - AWS Secrets Manager

This is a **production-ready configuration** demonstrating enterprise-grade secret management with:

- ✅ Custom KMS encryption for all secrets
- ✅ Cross-account secret sharing
- ✅ Automatic secret rotation
- ✅ Multi-region replication
- ✅ S3 backend with state locking
- ✅ Comprehensive tagging and compliance

## Architecture

```
Production Account (123456789012)
├─ Database Secrets
│  ├─ KMS Key (cross-account enabled)
│  ├─ Secret with rotation
│  └─ Replicated to us-west-2
│
├─ API Keys (Datadog, OAuth)
│  ├─ KMS Key (cross-account enabled)
│  └─ Shared with monitoring account
│
└─ Service Account Keys
   ├─ KMS Key (cross-account enabled)
   └─ Shared with app & partner accounts

Application Accounts (111111111111, 222222222222)
├─ IAM Role with KMS decrypt permissions
└─ Read secrets from production account
```

## Prerequisites

### 1. S3 Backend Setup

```bash
# Create S3 bucket for state storage
aws s3 mb s3://my-company-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-company-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Rotation Lambda Function

You need a Lambda function to rotate database credentials. See AWS documentation:
- [RDS PostgreSQL Rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_how.html)
- [RDS MySQL Rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_how.html)

### 3. AWS Accounts for Cross-Account Access

Ensure you have:
- **Production account** (where secrets live)
- **Application accounts** (that need to read secrets)
- **Monitoring account** (for observability)

## Deployment

### 1. Configure Variables

```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values (DO NOT COMMIT!)
vim terraform.tfvars
```

### 2. Initialize Terraform

```bash
cd environments/production
terraform init
```

This will:
- Download required providers
- Configure S3 backend
- Set up state locking

### 3. Review Changes

```bash
terraform plan
```

### 4. Deploy

```bash
terraform apply
```

## Cross-Account Access Setup

### In Application Account (111111111111)

Create an IAM role that can assume access:

```hcl
# Application account - IAM role
resource "aws_iam_role" "app_secrets_reader" {
  name = "secrets-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"  # Or your service
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Policy to read secrets from production account
resource "aws_iam_role_policy" "read_prod_secrets" {
  role = aws_iam_role.app_secrets_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "arn:aws:kms:us-east-1:123456789012:key/*"
      }
    ]
  })
}
```

### Testing Cross-Account Access

```bash
# From application account
aws secretsmanager get-secret-value \
  --secret-id arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/database/master-password \
  --region us-east-1
```

## Secrets Included

| Secret Name | Purpose | Rotation | Cross-Account |
|------------|---------|----------|---------------|
| `prod/database/master-password` | RDS credentials | Yes (30 days) | App accounts |
| `prod/monitoring/datadog-api-key` | Datadog API | No | Monitoring account |
| `prod/app/oauth-client-secret` | OAuth credentials | No | App accounts |
| `prod/service/api-gateway-key` | Service account | No | App + Partner accounts |

## Security Best Practices

✅ **State Encryption**: S3 backend uses encryption at rest  
✅ **State Locking**: DynamoDB prevents concurrent modifications  
✅ **Sensitive Variables**: All secrets marked as `sensitive = true`  
✅ **Recovery Window**: 30-day safety net for accidental deletions  
✅ **KMS Encryption**: Custom keys for all secrets  
✅ **Cross-Account IAM**: Least privilege access  
✅ **Tagging**: Compliance and cost tracking  
✅ **Replication**: DR regions configured  

## Monitoring & Alerts

Set up CloudWatch alarms for:
- Secret rotation failures
- Unauthorized access attempts
- KMS key usage anomalies

## Troubleshooting

### Error: "Access Denied" when reading secret

**Cause**: Missing KMS permissions in application account

**Solution**: Ensure IAM role has `kms:Decrypt` permission for the KMS key

### Error: "RotationLambdaARN is required"

**Cause**: Trying to enable rotation without Lambda function

**Solution**: Deploy rotation Lambda first, then set `rotation_lambda_arn`

### Error: "Secret already exists"

**Cause**: Secret name conflict

**Solution**: Either delete old secret or use `use_name_prefix = true`

## Cost Estimation

Approximate monthly costs for production setup:

- **Secrets Manager**: $0.40/secret × 4 secrets = **$1.60/month**
- **KMS Keys**: $1/key × 4 keys = **$4/month**
- **API Calls**: ~$0.05/10,000 requests
- **Lambda Rotation**: Minimal (within free tier)

**Total**: ~**$6-7/month** for complete secret management

## Next Steps

1. ✅ Deploy production secrets
2. Set up CloudWatch alarms
3. Configure application accounts
4. Test cross-account access
5. Enable CloudTrail logging
6. Document runbooks for rotation failures

## Support

- Module documentation: `modules/aws-secrets/README.md`
- AWS Secrets Manager: https://docs.aws.amazon.com/secretsmanager/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/
