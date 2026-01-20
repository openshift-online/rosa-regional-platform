import unittest
from unittest.mock import MagicMock, patch
import os
import sys
import json
from datetime import datetime, timezone

# Ensure scripts directory is in path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'scripts')))

import lease_account
import release_account

class TestIamUserLifecycle(unittest.TestCase):
    def setUp(self):
        self.region = 'us-east-2'
        self.table_name = 'AccountPool'
        self.account_id = '123456789012'
        self.role_arn = f"arn:aws:iam::{self.account_id}:role/OrganizationAccountAccessRole"
        self.user_name = 'sandbox-temporary-user'
        self.policy_arn = 'arn:aws:iam::aws:policy/AdministratorAccess'

    @patch('lease_account.subprocess.run')
    @patch('lease_account.boto3')
    @patch('time.sleep', return_value=None)  # skip sleeps
    def test_lease_account_creates_user(self, mock_sleep, mock_boto3, mock_subprocess):
        # Mock cloud-nuke success
        mock_subprocess.return_value.returncode = 0
        # Mock DynamoDB
        mock_dynamo = MagicMock()
        mock_table = MagicMock()
        mock_boto3.resource.return_value = mock_dynamo
        mock_dynamo.Table.return_value = mock_table

        # Mock Table Scan (Initial check not empty, then find available)
        mock_table.scan.side_effect = [
            {'Items': [{'account_id': self.account_id, 'status': 'AVAILABLE'}]}, # Initial check
            {'Items': [{'account_id': self.account_id, 'status': 'AVAILABLE'}]}  # Loop check
        ]

        # Mock STS
        mock_sts = MagicMock()
        mock_boto3.client.return_value = mock_sts
        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'ASIA_ROLE',
                'SecretAccessKey': 'SECRET_ROLE',
                'SessionToken': 'TOKEN_ROLE',
                'Expiration': datetime.now(timezone.utc)
            }
        }

        # We need to mock the IAM resource created WITH the assumed credentials
        # In the script, it will be something like: boto3.resource('iam', aws_access_key_id=..., ...)
        # So we verify that boto3.resource is called with these args.

        # However, boto3.resource is called once for dynamodb (no args usually) and once for IAM (with args).
        # We can inspect calls later. Let's setup the return value for the IAM resource.
        mock_iam = MagicMock()

        # Configure boto3.resource side effect to return mock_dynamo first, then mock_iam
        def resource_side_effect(*args, **kwargs):
            if args[0] == 'dynamodb':
                return mock_dynamo
            if args[0] == 'iam':
                return mock_iam
            return MagicMock()

        mock_boto3.resource.side_effect = resource_side_effect

        # Mock IAM User interactions
        mock_user = MagicMock()
        mock_iam.User.return_value = mock_user

        # Scenario: User exists, so we delete it first
        # verify delete is called
        # Then create_user call on mock_iam
        mock_new_user = MagicMock()
        mock_iam.create_user.return_value = mock_new_user

        mock_key_pair = MagicMock()
        mock_key_pair.id = 'AKIA_NEW'
        mock_key_pair.secret = 'SECRET_NEW'
        mock_new_user.create_access_key_pair.return_value = mock_key_pair

        # Capture stdout
        from io import StringIO
        captured_output = StringIO()
        sys.stdout = captured_output

        lease_account.lease_account()

        sys.stdout = sys.__stdout__
        output = json.loads(captured_output.getvalue())

        # Verifications
        self.assertEqual(output['credentials']['AccessKeyId'], 'AKIA_NEW')
        self.assertEqual(output['credentials']['SecretAccessKey'], 'SECRET_NEW')

        # Verify IAM interactions
        # 1. Check if user exists (User(name).load() or similar, or just try catch)
        # We'll expect the script to handle cleanup.
        # Verify create_user was called
        mock_iam.create_user.assert_called_with(UserName=self.user_name)

        # Verify policy attachment
        mock_new_user.attach_policy.assert_called_with(PolicyArn=self.policy_arn)


    @patch('release_account.subprocess.run')
    @patch('release_account.boto3')
    def test_release_account_deletes_user(self, mock_boto3, mock_subprocess):
        # Mock cloud-nuke success
        mock_subprocess.return_value.returncode = 0
        # Mock DynamoDB
        mock_dynamo = MagicMock()
        mock_table = MagicMock()
        mock_boto3.resource.return_value = mock_dynamo
        mock_dynamo.Table.return_value = mock_table

        # Mock Get Item (IN_USE)
        mock_table.get_item.return_value = {
            'Item': {'account_id': self.account_id, 'status': 'IN_USE'}
        }

        # Mock STS
        mock_sts = MagicMock()
        mock_boto3.client.return_value = mock_sts
        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'ASIA_ROLE',
                'SecretAccessKey': 'SECRET_ROLE',
                'SessionToken': 'TOKEN_ROLE'
            }
        }

        # Mock IAM
        mock_iam = MagicMock()

        def resource_side_effect(*args, **kwargs):
            if args[0] == 'dynamodb':
                return mock_dynamo
            if args[0] == 'iam':
                return mock_iam
            return MagicMock()

        mock_boto3.resource.side_effect = resource_side_effect

        mock_user = MagicMock()
        mock_iam.User.return_value = mock_user

        # Mock Access Keys iterator
        mock_key = MagicMock()
        mock_user.access_keys.all.return_value = [mock_key]

        # Mock Policies iterator
        mock_policy = MagicMock()
        mock_user.attached_policies.all.return_value = [mock_policy]

        # Run release
        release_account.release_account(self.account_id)

        # Verify Cleanup
        mock_sts.assume_role.assert_called()
        mock_iam.User.assert_called_with(self.user_name)

        # Verify Deletions
        mock_key.delete.assert_called()
        mock_user.detach_policy.assert_called()
        mock_user.delete.assert_called()

        # Verify DynamoDB update
        mock_table.update_item.assert_called()

if __name__ == '__main__':
    unittest.main()
