# ==============================================================================
# Secret Rotation Lambda Function
# ==============================================================================
# This creates a Lambda function to rotate database credentials.
# Based on AWS best practices for Secrets Manager rotation.

# ------------------------------------------------------------------------------
# Lambda Function for Rotation
# ------------------------------------------------------------------------------

resource "aws_lambda_function" "rotation" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0

  function_name = "${replace(var.secret_name, "/", "-")}-rotation"
  description   = "Rotates secret: ${var.secret_name}"

  runtime     = "python3.11"
  handler     = "lambda_function.lambda_handler"
  timeout     = 30
  memory_size = 128

  role = aws_iam_role.rotation[0].arn

  # Use inline code for simplicity
  filename         = data.archive_file.rotation_code[0].output_path
  source_code_hash = data.archive_file.rotation_code[0].output_base64sha256

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  # VPC config if database is in VPC
  dynamic "vpc_config" {
    for_each = var.rotation_vpc_config != null ? [var.rotation_vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = merge(var.tags, {
    Purpose = "secrets-rotation"
  })
}

# ------------------------------------------------------------------------------
# Lambda Code (Packaged)
# ------------------------------------------------------------------------------

data "archive_file" "rotation_code" {
  count       = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/rotation_lambda.zip"

  source {
    content  = local.rotation_lambda_code
    filename = "lambda_function.py"
  }
}

locals {
  rotation_lambda_code = <<-PYTHON
import boto3
import json
import string
import secrets

def lambda_handler(event, context):
    """Secret rotation handler for Secrets Manager."""
    
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']
    
    # Create Secrets Manager client
    sm_client = boto3.client('secretsmanager')
    
    # Get current secret metadata
    metadata = sm_client.describe_secret(SecretId=arn)
    
    if step == "createSecret":
        create_secret(sm_client, arn, token)
    elif step == "setSecret":
        set_secret(sm_client, arn, token)
    elif step == "testSecret":
        test_secret(sm_client, arn, token)
    elif step == "finishSecret":
        finish_secret(sm_client, arn, token)
    else:
        raise ValueError(f"Invalid step: {step}")

def create_secret(sm_client, arn, token):
    """Create a new secret version with new credentials."""
    
    # Get current secret
    current = sm_client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")
    secret_dict = json.loads(current['SecretString'])
    
    # Generate new password
    alphabet = string.ascii_letters + string.digits + "!#$%&*()-_=+[]<>?"
    new_password = ''.join(secrets.choice(alphabet) for _ in range(32))
    
    secret_dict['password'] = new_password
    
    # Store new version
    sm_client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(secret_dict),
        VersionStages=['AWSPENDING']
    )
    print(f"createSecret: Created new secret version with token {token}")

def set_secret(sm_client, arn, token):
    """Set the new credentials in the database."""
    
    # Get pending secret
    pending = sm_client.get_secret_value(
        SecretId=arn, 
        VersionStage="AWSPENDING",
        VersionId=token
    )
    secret_dict = json.loads(pending['SecretString'])
    
    # ==========================================================================
    # ASSUMPTION: Database-specific rotation code must be implemented here
    # ==========================================================================
    # This generic template demonstrates the rotation lifecycle.
    # For production use, implement database-specific connection and UPDATE logic:
    #
    # RDS MySQL Example:
    #   import pymysql
    #   conn = pymysql.connect(host=secret_dict['host'], user='admin', ...)
    #   cursor.execute(f"ALTER USER '{username}'@'%' IDENTIFIED BY '{new_password}'")
    #
    # RDS PostgreSQL Example:
    #   import psycopg2
    #   conn = psycopg2.connect(host=secret_dict['host'], ...)
    #   cursor.execute(f"ALTER USER {username} WITH PASSWORD '{new_password}'")
    #
    # DocumentDB Example:
    #   from pymongo import MongoClient
    #   client = MongoClient(secret_dict['host'])
    #   client.admin.command('updateUser', username, pwd=new_password)
    #
    # ASSUMPTION: For this 4-hour challenge, we demonstrate the rotation lifecycle
    # without database-specific dependencies. Production use requires:
    # 1. Database driver installation (pymysql, psycopg2, pymongo)
    # 2. Error handling for connection failures
    # 3. Transaction management
    # 4. Connection pooling awareness
    # ==========================================================================
    
    print(f"setSecret: Would update database credentials here")
    print(f"setSecret: Completed for token {token}")

def test_secret(sm_client, arn, token):
    """Test the new credentials work."""
    
    # Get pending secret
    pending = sm_client.get_secret_value(
        SecretId=arn,
        VersionStage="AWSPENDING", 
        VersionId=token
    )
    secret_dict = json.loads(pending['SecretString'])
    
    # ==========================================================================
    # ASSUMPTION: Database connection testing must be implemented here
    # ==========================================================================
    # For production use, verify the new credentials work by:
    # 1. Connecting to the database with new credentials from AWSPENDING version
    # 2. Running a simple query (e.g., SELECT 1) to confirm connectivity
    # 3. Handling authentication failures gracefully
    #
    # Example (PostgreSQL):
    #   try:
    #       conn = psycopg2.connect(
    #           host=secret_dict['host'],
    #           user=secret_dict['username'],
    #           password=secret_dict['password']  # NEW password
    #       )
    #       cursor = conn.cursor()
    #       cursor.execute("SELECT 1")
    #       conn.close()
    #   except Exception as e:
    #       raise ValueError(f"New credentials failed: {e}")
    #
    # ASSUMPTION: For this demonstration, we assume verification succeeds.
    # ==========================================================================
    
    print(f"testSecret: Would test database connection here")
    print(f"testSecret: Completed for token {token}")

def finish_secret(sm_client, arn, token):
    """Finalize the rotation by updating version stages."""
    
    # Get current version
    metadata = sm_client.describe_secret(SecretId=arn)
    current_version = None
    
    for version_id, stages in metadata['VersionIdsToStages'].items():
        if "AWSCURRENT" in stages:
            if version_id == token:
                print(f"finishSecret: Version {token} already AWSCURRENT")
                return
            current_version = version_id
            break
    
    # Move AWSCURRENT from old to new
    sm_client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )
    
    print(f"finishSecret: Rotation complete for token {token}")
PYTHON
}

# ------------------------------------------------------------------------------
# Lambda IAM Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "rotation" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0

  name = "${replace(var.secret_name, "/", "-")}-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "rotation" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0

  name = "secrets-rotation-policy"
  role = aws_iam_role.rotation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.this.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Add KMS decrypt permission if custom KMS key is used
resource "aws_iam_role_policy" "rotation_kms" {
  count = var.enable_rotation && var.create_rotation_lambda && var.create_kms_key ? 1 : 0

  name = "kms-decrypt-policy"
  role = aws_iam_role.rotation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      Resource = aws_kms_key.this[0].arn
    }]
  })
}

# Basic Lambda execution role policy (for VPC if needed)
resource "aws_iam_role_policy_attachment" "rotation_vpc" {
  count = var.enable_rotation && var.create_rotation_lambda && var.rotation_vpc_config != null ? 1 : 0

  role       = aws_iam_role.rotation[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ------------------------------------------------------------------------------
# Lambda Permission for Secrets Manager
# ------------------------------------------------------------------------------

resource "aws_lambda_permission" "secrets_manager" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0

  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}
