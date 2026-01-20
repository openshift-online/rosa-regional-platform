import boto3
import sys
import os
import json
from datetime import datetime, timezone, timedelta
from boto3.dynamodb.conditions import Attr
import release_account  # Import the release logic

TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'AccountPool')
REGION = os.environ.get('AWS_REGION', 'us-east-2')

def cleanup_failed_accounts():
    print(f"Starting janitor cleanup in region {REGION}", file=sys.stderr)
    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table(TABLE_NAME)

    try:
        # Scan for FAILED accounts
        response = table.scan(
            FilterExpression=Attr('status').eq('FAILED')
        )
        failed_accounts = response.get('Items', [])
        
        if not failed_accounts:
            print("No FAILED accounts found.", file=sys.stderr)
            return

        now = datetime.now(timezone.utc)
        
        for account in failed_accounts:
            account_id = account['account_id']
            lease_ts_str = account.get('lease_timestamp')

            if not lease_ts_str:
                print(f"Account {account_id} is FAILED but has no lease_timestamp. Releasing immediately.", file=sys.stderr)
                # Use release_account function to nuke and reset to AVAILABLE
                try:
                    release_account.release_account(account_id, status='AVAILABLE')
                except Exception as e:
                     print(f"Error releasing account {account_id}: {e}", file=sys.stderr)
                continue

            try:
                lease_ts = datetime.fromisoformat(lease_ts_str)
                # Ensure lease_ts is timezone-aware
                if lease_ts.tzinfo is None:
                    lease_ts = lease_ts.replace(tzinfo=timezone.utc)
                
                age = now - lease_ts
                
                if age > timedelta(hours=3):
                    print(f"Account {account_id} has been FAILED for {age}. Releasing...", file=sys.stderr)
                    try:
                        release_account.release_account(account_id, status='AVAILABLE')
                    except Exception as e:
                        print(f"Error releasing account {account_id}: {e}", file=sys.stderr)
                else:
                    print(f"Account {account_id} FAILED timestamp is {age} old (threshold: 3 hours). Skipping.", file=sys.stderr)

            except ValueError:
                print(f"Invalid timestamp format for account {account_id}: {lease_ts_str}. Releasing immediately.", file=sys.stderr)
                try:
                    release_account.release_account(account_id, status='AVAILABLE')
                except Exception as e:
                    print(f"Error releasing account {account_id}: {e}", file=sys.stderr)

    except Exception as e:
        print(f"Error scanning table {TABLE_NAME}: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    cleanup_failed_accounts()
