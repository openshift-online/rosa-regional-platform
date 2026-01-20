import unittest
from unittest.mock import MagicMock, patch, call
import sys
import os
import io
import json
from datetime import datetime, timezone
from botocore.exceptions import ClientError

# Add scripts to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'scripts'))

import lease_account
import release_account

class TestCloudNukeIntegration(unittest.TestCase):

    def setUp(self):
        # Redirect stdout/stderr to capture output
        self.captured_stdout = io.StringIO()
        self.captured_stderr = io.StringIO()
        sys.stdout = self.captured_stdout
        sys.stderr = self.captured_stderr

    def tearDown(self):
        sys.stdout = sys.__stdout__
        sys.stderr = sys.__stderr__

    @patch('lease_account.boto3.client')
    @patch('lease_account.boto3.resource')
    @patch('lease_account.subprocess.run')
    @patch('lease_account.time.sleep')
    def test_lease_account_nuke_success(self, mock_sleep, mock_subprocess, mock_boto_resource, mock_boto_client):
        # Setup mocks
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        # Scan returns one available account
        mock_table.scan.side_effect = [
             # Initial check (all items)
            {'Items': [{'account_id': '123', 'status': 'AVAILABLE'}]},
             # Loop check
            {'Items': [{'account_id': '123', 'status': 'AVAILABLE'}]}
        ]
        mock_table.update_item.return_value = {} # Mock lock success

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

        # Mock Cloud Nuke Success (exit code 0)
        mock_subprocess.return_value.returncode = 0

        # Mock IAM
        mock_iam_user = MagicMock()
        mock_boto_resource.return_value.User.return_value = mock_iam_user
        mock_boto_resource.return_value.create_user.return_value = mock_iam_user
        mock_key_pair = MagicMock()
        mock_key_pair.id = 'AKIA_NEW'
        mock_key_pair.secret = 'SECRET_NEW'
        mock_iam_user.create_access_key_pair.return_value = mock_key_pair

        # Run
        lease_account.lease_account()

        # Verify
        output = self.captured_stdout.getvalue()
        self.assertIn('"status": "success"', output)
        self.assertIn('"account_id": "123"', output)

        # Verify cloud-nuke was called
        mock_subprocess.assert_called_once()
        cmd_args = mock_subprocess.call_args[0][0]
        self.assertIn('cloud-nuke', cmd_args)
        # Check if any arg ends with configs/cloud-nuke.yaml
        self.assertTrue(any(arg.endswith('configs/cloud-nuke.yaml') for arg in cmd_args))

    @patch('lease_account.boto3.client')
    @patch('lease_account.boto3.resource')
    @patch('lease_account.subprocess.run')
    @patch('lease_account.time.sleep')
    def test_lease_account_nuke_failure_then_success(self, mock_sleep, mock_subprocess, mock_boto_resource, mock_boto_client):
        # Scenario: Account 123 fails nuke (marked dirty), Account 456 succeeds.
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        # Initial check
        # Then scan loop. First iteration returns [123, 456]
        # Or side effect for scan calls

        mock_table.scan.side_effect = [
            # Initial check
            {'Items': [{'account_id': '123'}, {'account_id': '456'}]},
            # Loop check
            {'Items': [{'account_id': '123', 'status': 'AVAILABLE'}, {'account_id': '456', 'status': 'AVAILABLE'}]}
        ]

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

        # Mock Cloud Nuke: First call fails (raise CalledProcessError), second succeeds
        from subprocess import CalledProcessError
        mock_subprocess.side_effect = [
            CalledProcessError(1, 'cloud-nuke', stderr='Failure'),
            MagicMock(returncode=0)
        ]

        # Mock IAM (for second account)
        mock_iam_user = MagicMock()
        mock_boto_resource.return_value.User.return_value = mock_iam_user
        mock_boto_resource.return_value.create_user.return_value = mock_iam_user
        mock_key_pair = MagicMock()
        mock_key_pair.id = 'AKIA_NEW'
        mock_key_pair.secret = 'SECRET_NEW'
        mock_iam_user.create_access_key_pair.return_value = mock_key_pair

        # Run
        lease_account.lease_account()

        # Verify
        output = self.captured_stdout.getvalue()
        self.assertIn('"status": "success"', output)
        self.assertIn('"account_id": "456"', output) # Should be the second account

        # Verify cloud-nuke was called twice
        self.assertEqual(mock_subprocess.call_count, 2)

        # Verify Account 123 was marked DIRTY
        # We need to check calls to table.update_item
        # First update: Lock 123
        # Second update: Mark 123 DIRTY
        # Third update: Lock 456

        # Find calls with account_id='123' and UpdateExpression setting DIRTY
        dirty_calls = [
            c for c in mock_table.update_item.call_args_list
            if c[1]['Key']['account_id'] == '123' and ':dirty' in c[1]['ExpressionAttributeValues']
        ]
        self.assertEqual(len(dirty_calls), 1, "Account 123 should be marked DIRTY")


    @patch('release_account.boto3.client')
    @patch('release_account.boto3.resource')
    @patch('release_account.subprocess.run')
    def test_release_account_nuke_success(self, mock_subprocess, mock_boto_resource, mock_boto_client):
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        # Get Item returns IN_USE
        mock_table.get_item.return_value = {'Item': {'account_id': '123', 'status': 'IN_USE'}}

        # Mock STS
        mock_sts = MagicMock()
        mock_boto_client.return_value = mock_sts
        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'AKIA_TEST', 'SecretAccessKey': 'S', 'SessionToken': 'T'
            }
        }

        # Mock Nuke Success
        mock_subprocess.return_value.returncode = 0

        # Mock IAM (User deletion)
        mock_iam_user = MagicMock()
        mock_boto_resource.return_value.User.return_value = mock_iam_user

        # Run
        release_account.release_account('123')

        # Verify released to AVAILABLE
        available_calls = [
            c for c in mock_table.update_item.call_args_list
            if ':available' in c[1]['ExpressionAttributeValues']
        ]
        self.assertEqual(len(available_calls), 1)

    @patch('release_account.boto3.client')
    @patch('release_account.boto3.resource')
    @patch('release_account.subprocess.run')
    def test_release_account_nuke_failure(self, mock_subprocess, mock_boto_resource, mock_boto_client):
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        mock_table.get_item.return_value = {'Item': {'account_id': '123', 'status': 'IN_USE'}}

        mock_sts = MagicMock()
        mock_boto_client.return_value = mock_sts
        mock_sts.assume_role.return_value = {
            'Credentials': {'AccessKeyId': 'A', 'SecretAccessKey': 'S', 'SessionToken': 'T'}
        }

        # Mock Nuke Failure
        from subprocess import CalledProcessError
        mock_subprocess.side_effect = CalledProcessError(1, 'cmd', stderr='Error')

        # Run - expects exit(1)
        with self.assertRaises(SystemExit):
            release_account.release_account('123')

        # Verify marked DIRTY
        dirty_calls = [
            c for c in mock_table.update_item.call_args_list
            if ':dirty' in c[1]['ExpressionAttributeValues']
        ]
        self.assertEqual(len(dirty_calls), 1)

if __name__ == '__main__':
    unittest.main()
