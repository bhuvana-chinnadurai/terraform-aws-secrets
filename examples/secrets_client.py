#!/usr/bin/env python3
"""
AWS Secrets Manager Client with Rotation Handling

This script demonstrates best practices for retrieving secrets
that may be rotated, including edge case handling.
"""

import boto3
import json
import time
from botocore.exceptions import ClientError
from typing import Optional, Dict, Any


class SecretsClient:
    """
    A robust client for AWS Secrets Manager with rotation handling.
    
    Handles:
    - Secret retrieval with caching
    - Rotation-aware version handling
    - Connection retry with rotated credentials
    - Edge cases (pending rotation, failed rotation)
    """
    
    def __init__(self, region: str = "ap-south-1", cache_ttl: int = 300):
        """
        Initialize the secrets client.
        
        Args:
            region: AWS region
            cache_ttl: Cache time-to-live in seconds (default 5 min)
        """
        self.client = boto3.client('secretsmanager', region_name=region)
        self.cache: Dict[str, Dict[str, Any]] = {}
        self.cache_ttl = cache_ttl
    
    def get_secret(
        self, 
        secret_id: str, 
        version_stage: str = "AWSCURRENT",
        use_cache: bool = True
    ) -> Dict[str, Any]:
        """
        Retrieve a secret value with caching and rotation handling.
        
        Args:
            secret_id: Name or ARN of the secret
            version_stage: AWSCURRENT (latest) or AWSPENDING (next rotation)
            use_cache: Whether to use cached value if available
            
        Returns:
            Parsed secret as dictionary
            
        Raises:
            SecretNotFoundError: Secret doesn't exist
            SecretRotationInProgressError: Rotation is in progress
            SecretAccessDeniedError: No permission to access secret
        """
        cache_key = f"{secret_id}:{version_stage}"
        
        # Check cache
        if use_cache and cache_key in self.cache:
            cached = self.cache[cache_key]
            if time.time() - cached['timestamp'] < self.cache_ttl:
                print(f"[CACHE HIT] Using cached secret for {secret_id}")
                return cached['value']
        
        try:
            response = self.client.get_secret_value(
                SecretId=secret_id,
                VersionStage=version_stage
            )
            
            # Parse the secret
            if 'SecretString' in response:
                secret_value = json.loads(response['SecretString'])
            else:
                # Binary secret (base64 encoded)
                import base64
                secret_value = {"binary": base64.b64encode(response['SecretBinary']).decode()}
            
            # Cache it
            self.cache[cache_key] = {
                'value': secret_value,
                'version_id': response['VersionId'],
                'timestamp': time.time()
            }
            
            print(f"[FETCHED] Secret {secret_id} v:{response['VersionId'][:8]}...")
            return secret_value
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            
            if error_code == 'ResourceNotFoundException':
                raise SecretNotFoundError(f"Secret not found: {secret_id}")
            
            elif error_code == 'InvalidRequestException':
                # Often happens during rotation
                msg = e.response['Error']['Message']
                if 'pending' in msg.lower():
                    raise SecretRotationInProgressError(
                        f"Secret rotation in progress for {secret_id}"
                    )
                raise
            
            elif error_code == 'AccessDeniedException':
                raise SecretAccessDeniedError(f"Access denied to {secret_id}")
            
            elif error_code == 'DecryptionFailure':
                raise SecretDecryptionError(
                    f"Cannot decrypt {secret_id} - check KMS permissions"
                )
            
            else:
                raise
    
    def get_both_versions(self, secret_id: str) -> Dict[str, Any]:
        """
        Get both AWSCURRENT and AWSPENDING versions.
        
        Useful during rotation when you need to try both credentials.
        
        Returns:
            {
                'current': {...},      # Active credentials
                'pending': {...},      # New credentials (if rotating)
                'is_rotating': bool
            }
        """
        result = {'current': None, 'pending': None, 'is_rotating': False}
        
        # Get current version
        result['current'] = self.get_secret(secret_id, "AWSCURRENT")
        
        # Try to get pending version (may not exist)
        try:
            result['pending'] = self.get_secret(secret_id, "AWSPENDING")
            result['is_rotating'] = True
            print(f"[ROTATION] Pending version available for {secret_id}")
        except (ClientError, SecretNotFoundError):
            pass  # No pending version = not rotating
        
        return result
    
    def invalidate_cache(self, secret_id: str = None):
        """
        Invalidate cached secrets.
        
        Args:
            secret_id: Specific secret to invalidate, or None for all
        """
        if secret_id:
            keys_to_remove = [k for k in self.cache if k.startswith(secret_id)]
            for key in keys_to_remove:
                del self.cache[key]
            print(f"[CACHE] Invalidated cache for {secret_id}")
        else:
            self.cache.clear()
            print("[CACHE] Cleared all cached secrets")


# Custom exceptions for better error handling
class SecretNotFoundError(Exception):
    pass

class SecretRotationInProgressError(Exception):
    pass

class SecretAccessDeniedError(Exception):
    pass

class SecretDecryptionError(Exception):
    pass


class DatabaseConnectionWithRotation:
    """
    Example: Database connection that handles credential rotation.
    
    This is the pattern you'd use for any service that needs
    to reconnect when credentials are rotated.
    """
    
    def __init__(self, secret_id: str, region: str = "ap-south-1"):
        self.secret_id = secret_id
        self.secrets = SecretsClient(region=region)
        self.connection = None
        self.current_credentials = None
    
    def connect(self) -> bool:
        """
        Connect to database using current credentials.
        If connection fails, tries pending credentials (rotation handling).
        """
        versions = self.secrets.get_both_versions(self.secret_id)
        
        # Try current credentials first
        if self._try_connect(versions['current'], "CURRENT"):
            return True
        
        # If rotation is happening, try pending credentials
        if versions['is_rotating'] and versions['pending']:
            print("[FALLBACK] Trying pending (rotated) credentials...")
            if self._try_connect(versions['pending'], "PENDING"):
                return True
        
        print("[ERROR] All credential versions failed!")
        return False
    
    def _try_connect(self, credentials: Dict[str, Any], version: str) -> bool:
        """Try connecting with specific credentials."""
        try:
            # Simulated connection (replace with actual DB connection)
            print(f"[CONNECT] Trying {version} credentials for {credentials.get('username', 'unknown')}")
            
            # Actual connection code would be:
            # import psycopg2
            # self.connection = psycopg2.connect(
            #     host=credentials['host'],
            #     port=credentials['port'],
            #     database=credentials['dbname'],
            #     user=credentials['username'],
            #     password=credentials['password']
            # )
            
            self.current_credentials = credentials
            print(f"[SUCCESS] Connected using {version} credentials")
            return True
            
        except Exception as e:
            print(f"[FAILED] {version} credentials: {e}")
            return False
    
    def execute_with_retry(self, query: str, max_retries: int = 2):
        """
        Execute query with automatic credential refresh on auth failure.
        """
        for attempt in range(max_retries + 1):
            try:
                # Execute query (simulated)
                print(f"[QUERY] Executing: {query[:50]}...")
                return {"result": "success"}
                
            except Exception as e:
                if "authentication" in str(e).lower() or "password" in str(e).lower():
                    print(f"[AUTH FAILED] Credentials may have rotated, refreshing...")
                    self.secrets.invalidate_cache(self.secret_id)
                    
                    if attempt < max_retries:
                        self.connect()
                        continue
                raise
        
        raise Exception("Max retries exceeded")


def demo():
    """Demonstrate the secrets client with rotation handling."""
    
    print("=" * 60)
    print("AWS Secrets Manager - Rotation-Aware Client Demo")
    print("=" * 60)
    
    # Initialize client
    client = SecretsClient(region="ap-south-1")
    
    try:
        # 1. Basic secret retrieval
        print("\n1. Fetching production database credentials...\n")
        secret = client.get_secret("prod/database/credentials")
        
        print(f"   Username: {secret.get('username')}")
        print(f"   Host: {secret.get('host')}")
        print(f"   Database: {secret.get('dbname')}")
        print(f"   Password: {'*' * len(secret.get('password', ''))}")
        
        # 2. Check rotation status
        print("\n2. Checking rotation status...\n")
        versions = client.get_both_versions("prod/database/credentials")
        
        if versions['is_rotating']:
            print("   ⚠️  Rotation in progress!")
            print("   Current and pending credentials available")
        else:
            print("   ✅ No rotation in progress")
        
        # 3. Demo cached retrieval
        print("\n3. Testing cache...\n")
        client.get_secret("prod/database/credentials")  # Should hit cache
        
        # 4. Database connection with rotation handling
        print("\n4. Simulating database connection with rotation handling...\n")
        db = DatabaseConnectionWithRotation("prod/database/credentials")
        db.connect()
        
        print("\n" + "=" * 60)
        print("Demo complete!")
        print("=" * 60)
        
    except SecretNotFoundError as e:
        print(f"❌ Secret not found: {e}")
    except SecretAccessDeniedError as e:
        print(f"❌ Access denied: {e}")
    except SecretRotationInProgressError as e:
        print(f"⚠️  Rotation in progress: {e}")
    except Exception as e:
        print(f"❌ Error: {e}")


if __name__ == "__main__":
    demo()
