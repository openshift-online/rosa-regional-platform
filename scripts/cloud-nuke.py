#!/usr/bin/env python3
"""
cloud-nuke wrapper script for AWS resource cleanup
Handles credential management and executes cloud-nuke with proper configuration
"""

import os
import sys
import subprocess
import argparse
import json
import boto3
from pathlib import Path


def get_aws_credentials():
    """
    Retrieve AWS credentials from the current environment or session
    Returns a dictionary with AccessKeyId, SecretAccessKey, and optional SessionToken
    """
    # First try to get credentials from boto3 session (handles various credential sources)
    try:
        session = boto3.Session()
        credentials = session.get_credentials()

        if credentials is None:
            print("ERROR: No AWS credentials found. Please configure AWS credentials.", file=sys.stderr)
            sys.exit(1)

        # Get frozen credentials to access the actual values
        frozen_creds = credentials.get_frozen_credentials()

        creds_dict = {
            'AccessKeyId': frozen_creds.access_key,
            'SecretAccessKey': frozen_creds.secret_key,
        }

        if frozen_creds.token:
            creds_dict['SessionToken'] = frozen_creds.token

        return creds_dict

    except Exception as e:
        print(f"ERROR: Failed to retrieve AWS credentials: {e}", file=sys.stderr)
        sys.exit(1)


def get_caller_identity():
    """Get and display AWS caller identity for verification"""
    try:
        sts = boto3.client('sts')
        identity = sts.get_caller_identity()
        return identity
    except Exception as e:
        print(f"ERROR: Failed to get AWS caller identity: {e}", file=sys.stderr)
        sys.exit(1)


def run_cloud_nuke(credentials, region, dry_run=False, timeout="30m"):
    """
    Execute cloud-nuke with the provided credentials and configuration

    Args:
        credentials: Dict with AWS credentials (AccessKeyId, SecretAccessKey, SessionToken)
        region: AWS region to target
        dry_run: If True, run in dry-run mode
        timeout: Timeout value for cloud-nuke operation

    Returns:
        True if successful, False otherwise
    """
    env = os.environ.copy()
    env['AWS_ACCESS_KEY_ID'] = credentials['AccessKeyId']
    env['AWS_SECRET_ACCESS_KEY'] = credentials['SecretAccessKey']
    if credentials.get('SessionToken'):
        env['AWS_SESSION_TOKEN'] = credentials['SessionToken']

    # Disable telemetry by default (can be overridden by environment)
    env.setdefault('DISABLE_TELEMETRY', 'true')

    # Calculate absolute path to config file
    script_dir = Path(__file__).parent.absolute()
    config_path = script_dir.parent / 'configs' / 'cloud-nuke.yaml'

    if not config_path.exists():
        print(f"WARNING: Config file not found at {config_path}", file=sys.stderr)
        print("Proceeding without config file - will use default behavior", file=sys.stderr)
        config_args = []
    else:
        config_args = ["--config", str(config_path)]

    # Build command
    cmd = [
        "cloud-nuke", "aws",
        "--region", region,
        *config_args,
        "--timeout", timeout
    ]

    if dry_run:
        cmd.append("--dry-run")
    else:
        cmd.append("--force")

    print(f"Executing: {' '.join(cmd)}", file=sys.stderr)
    print("", file=sys.stderr)

    try:
        # Stream output to stderr to allow viewing progress while keeping stdout clean
        subprocess.run(
            cmd,
            env=env,
            check=True,
            capture_output=False,
            text=True,
            stdout=sys.stderr,  # Redirect stdout to stderr
            stderr=sys.stderr   # Redirect stderr to stderr
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"ERROR: cloud-nuke failed with exit code {e.returncode}", file=sys.stderr)
        return False
    except FileNotFoundError:
        print("ERROR: cloud-nuke binary not found.", file=sys.stderr)
        print("Install it with: make install-cloud-nuke", file=sys.stderr)
        return False


def confirm_account(account_number, dry_run=False):
    """
    Prompt user to confirm the AWS account number before proceeding

    Args:
        account_number: AWS account number to confirm
        dry_run: If True, skip confirmation for dry-run mode

    Returns:
        True if user confirms, False otherwise
    """
    if dry_run:
        # For dry-run, still show the account but don't require strict confirmation
        print(f"⚠️  This will run against AWS Account: {account_number}", file=sys.stderr)
        print("", file=sys.stderr)
        try:
            response = input("Continue with dry-run? [y/N]: ").strip().lower()
            return response in ['y', 'yes']
        except (EOFError, KeyboardInterrupt):
            print("\n❌ Operation cancelled.", file=sys.stderr)
            return False
    else:
        # For destructive mode, require exact account number confirmation
        print(f"⚠️  ⚠️  ⚠️  This will DELETE resources in AWS Account: {account_number} ⚠️  ⚠️  ⚠️", file=sys.stderr)
        print("", file=sys.stderr)
        try:
            response = input(f"Type the account number '{account_number}' to confirm: ").strip()
            if response == account_number:
                return True
            else:
                print("❌ Account number does not match. Operation cancelled.", file=sys.stderr)
                return False
        except (EOFError, KeyboardInterrupt):
            print("\n❌ Operation cancelled.", file=sys.stderr)
            return False


def main():
    parser = argparse.ArgumentParser(
        description="Run cloud-nuke with proper credential and configuration management"
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "us-east-1"),
        help="AWS region to target (default: us-east-1 or AWS_REGION env var)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run in dry-run mode (show what would be deleted without deleting)"
    )
    parser.add_argument(
        "--timeout",
        default="30m",
        help="Timeout for cloud-nuke operation (default: 30m)"
    )
    parser.add_argument(
        "--show-identity",
        action="store_true",
        help="Show AWS caller identity and exit"
    )
    parser.add_argument(
        "--skip-confirmation",
        action="store_true",
        help="Skip account confirmation prompt (use with caution!)"
    )

    args = parser.parse_args()

    # Get and display caller identity
    print("🔑 AWS Caller Identity:", file=sys.stderr)
    identity = get_caller_identity()
    account_number = identity['Account']
    print(f"  Account: {account_number}", file=sys.stderr)
    print(f"  UserId:  {identity['UserId']}", file=sys.stderr)
    print(f"  ARN:     {identity['Arn']}", file=sys.stderr)
    print("", file=sys.stderr)

    if args.show_identity:
        # Output identity as JSON to stdout for programmatic use
        print(json.dumps(identity, indent=2))
        sys.exit(0)

    # Confirm account number before proceeding (unless skipped)
    if not args.skip_confirmation:
        if not confirm_account(account_number, args.dry_run):
            sys.exit(1)
        print("", file=sys.stderr)

    # Get credentials
    credentials = get_aws_credentials()

    # Run cloud-nuke
    if args.dry_run:
        print("☢️  Running cloud-nuke in DRY RUN mode...", file=sys.stderr)
        print(f"Region: {args.region}", file=sys.stderr)
        print("", file=sys.stderr)
    else:
        print("☢️  ⚠️  WARNING: Running cloud-nuke in DESTRUCTIVE mode! ⚠️", file=sys.stderr)
        print(f"Region: {args.region}", file=sys.stderr)
        print("", file=sys.stderr)

    success = run_cloud_nuke(credentials, args.region, args.dry_run, args.timeout)

    if success:
        print("", file=sys.stderr)
        print("✅ cloud-nuke completed successfully", file=sys.stderr)
        sys.exit(0)
    else:
        print("", file=sys.stderr)
        print("❌ cloud-nuke failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
