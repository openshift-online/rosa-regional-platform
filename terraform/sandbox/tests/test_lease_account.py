import unittest
from unittest.mock import MagicMock, patch
import sys
import os
import io
import json
import time
from datetime import datetime, timezone
from botocore.exceptions import ClientError

# Add scripts to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'scripts'))

import lease_account

class TestLeaseAccount(unittest.TestCase):

    @patch('lease_account.boto3.resource')
    @patch('lease_account.time.sleep') # Don't actually sleep
    def test_empty_pool(self, mock_sleep, mock_boto_resource):
        # Mock table
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        mock_table.scan.return_value = {'Items': []}

        captured_stderr = io.StringIO()
        sys.stderr = captured_stderr

        with self.assertRaises(SystemExit) as cm:
            lease_account.lease_account()

        self.assertEqual(cm.exception.code, 1)
        # We expect a specific error message about configuration
        self.assertIn("No accounts configured", captured_stderr.getvalue())

        sys.stderr = sys.__stderr__

    @patch('lease_account.boto3.resource')
    @patch('lease_account.time.sleep')
    def test_timeout(self, mock_sleep, mock_boto_resource):
        # Set short timeout via env var
        with patch.dict(os.environ, {'LEASE_TIMEOUT': '1'}):
            mock_table = MagicMock()
            mock_boto_resource.return_value.Table.return_value = mock_table

            # Mock scan behavior
            def scan_side_effect(**kwargs):
                # If checking for available (FilterExpression present)
                if 'FilterExpression' in kwargs:
                    return {'Items': []}
                # Initial check for empty pool (no filter)
                return {'Items': [{'account_id': '123', 'status': 'IN_USE'}]}

            mock_table.scan.side_effect = scan_side_effect

            captured_stderr = io.StringIO()
            sys.stderr = captured_stderr

            with self.assertRaises(SystemExit) as cm:
                lease_account.lease_account()

            self.assertEqual(cm.exception.code, 1)
            self.assertIn("Timeout", captured_stderr.getvalue())

            sys.stderr = sys.__stderr__

    @patch('lease_account.subprocess.run')
    @patch('lease_account.boto3.client')
    @patch('lease_account.boto3.resource')
    @patch('lease_account.time.sleep')
    def test_success(self, mock_sleep, mock_boto_resource, mock_boto_client, mock_subprocess):
        # Mock cloud-nuke success
        mock_subprocess.return_value.returncode = 0
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        def scan_side_effect(**kwargs):
            # Both initial check and availability check return the item
            return {'Items': [{'account_id': '123', 'status': 'AVAILABLE'}]}

        mock_table.scan.side_effect = scan_side_effect
        mock_table.update_item.return_value = {}

        # Mock IAM User creation
        mock_iam_user = MagicMock()
        # Mock iam_resource.User(...)
        mock_boto_resource.return_value.User.return_value = mock_iam_user
        # Mock iam_resource.create_user(...)
        mock_boto_resource.return_value.create_user.return_value = mock_iam_user

        mock_key_pair = MagicMock()
        mock_key_pair.id = 'AKIA_NEW_USER'
        mock_key_pair.secret = 'SECRET_NEW_USER'
        mock_iam_user.create_access_key_pair.return_value = mock_key_pair

        # Mock STS
        mock_sts = MagicMock()
        mock_boto_client.return_value = mock_sts

        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'AKIA_TEST',
                'SecretAccessKey': 'SECRET_TEST',
                'SessionToken': 'TOKEN_TEST',
                'Expiration': datetime(2025, 1, 1, tzinfo=timezone.utc)
            }
        }

        captured_stdout = io.StringIO()
        sys.stdout = captured_stdout

        lease_account.lease_account()

        output = captured_stdout.getvalue()
        self.assertIn('"status": "success"', output)
        self.assertIn('"account_id": "123"', output)
        self.assertIn('"AccessKeyId": "AKIA_NEW_USER"', output)

        # Verify STS call
        mock_sts.assume_role.assert_called_with(
            RoleArn='arn:aws:iam::123:role/OrganizationAccountAccessRole',
            RoleSessionName='LeasedSession',
            DurationSeconds=3600
        )

        sys.stdout = sys.__stdout__

    @patch('lease_account.boto3.resource')
    @patch('lease_account.time.sleep')
    def test_timeout_prints_in_use_accounts(self, mock_sleep, mock_boto_resource):
        # Set short timeout via env var
        with patch.dict(os.environ, {'LEASE_TIMEOUT': '1'}):
            mock_table = MagicMock()
            mock_boto_resource.return_value.Table.return_value = mock_table

            # Mock scan behavior
            def scan_side_effect(**kwargs):
                if 'FilterExpression' in kwargs:
                    fe = kwargs['FilterExpression']
                    if fe == lease_account.Attr('status').eq('AVAILABLE'):
                        return {'Items': []}
                    if fe == lease_account.Attr('status').eq('IN_USE'):
                        return {'Items': [{'account_id': 'ACC_1', 'status': 'IN_USE'}, {'account_id': 'ACC_2', 'status': 'IN_USE'}]}

                # Initial check (no filter)
                return {'Items': [{'account_id': 'ACC_1', 'status': 'IN_USE'}]}

            mock_table.scan.side_effect = scan_side_effect

            captured_stderr = io.StringIO()
            sys.stderr = captured_stderr

            with self.assertRaises(SystemExit) as cm:
                lease_account.lease_account()

            self.assertEqual(cm.exception.code, 1)
            output = captured_stderr.getvalue()
            self.assertIn("Timeout", output)
            self.assertIn("Accounts currently IN_USE:", output)
            self.assertIn("ACC_1", output)
            self.assertIn("ACC_2", output)

            sys.stderr = sys.__stderr__

if __name__ == '__main__':
    unittest.main()
