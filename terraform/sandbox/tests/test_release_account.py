import unittest
from unittest.mock import MagicMock, patch
import sys
import os
import io
import json
from botocore.exceptions import ClientError

# Add scripts to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'scripts'))

import release_account

class TestReleaseAccount(unittest.TestCase):

    @patch('release_account.subprocess.run')
    @patch('release_account.boto3.client')
    @patch('release_account.boto3.resource')
    def test_release_success(self, mock_boto_resource, mock_boto_client, mock_subprocess):
        # Mock cloud-nuke success
        mock_subprocess.return_value.returncode = 0
        # Mock table
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        # Mock get_item returning IN_USE account
        mock_table.get_item.return_value = {
            'Item': {'account_id': '123', 'status': 'IN_USE'}
        }
        mock_table.update_item.return_value = {}

        # Mock STS
        mock_sts = MagicMock()
        mock_boto_client.return_value = mock_sts
        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'ASIA_TEST',
                'SecretAccessKey': 'SECRET_TEST',
                'SessionToken': 'TOKEN_TEST'
            }
        }

        # Mock IAM
        # mock_boto_resource is used for both DynamoDB and IAM.
        # We can configure the User object to avoid errors during cleanup.
        mock_user = MagicMock()
        mock_boto_resource.return_value.User.return_value = mock_user

        # Ensure iteration over keys/policies doesn't fail
        mock_user.access_keys.all.return_value = []
        mock_user.attached_policies.all.return_value = []
        mock_user.policies.all.return_value = []

        captured_stdout = io.StringIO()
        sys.stdout = captured_stdout

        release_account.release_account('123')

        output = captured_stdout.getvalue()
        self.assertIn("Successfully released account 123", output)
        # Verify user cleanup was attempted
        self.assertIn("Successfully deleted user sandbox-temporary-user", output)

        sys.stdout = sys.__stdout__

    @patch('release_account.boto3.resource')
    def test_release_not_leased(self, mock_boto_resource):
        # Mock table
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        # Mock get_item returning AVAILABLE account
        mock_table.get_item.return_value = {
            'Item': {'account_id': '123', 'status': 'AVAILABLE'}
        }

        captured_stderr = io.StringIO()
        sys.stderr = captured_stderr

        with self.assertRaises(SystemExit) as cm:
            release_account.release_account('123')

        self.assertEqual(cm.exception.code, 1)

        output = captured_stderr.getvalue()
        # Helper to find JSON in mixed output
        error_json = None
        for line in output.splitlines():
            try:
                error_json = json.loads(line)
                break
            except json.JSONDecodeError:
                continue

        if error_json:
            self.assertEqual(error_json['status'], 'error')
            self.assertIn('not leased', error_json['message'])
        else:
            self.fail(f"Could not find valid JSON in output: {output}")

        sys.stderr = sys.__stderr__

    @patch('release_account.boto3.resource')
    def test_release_account_not_found(self, mock_boto_resource):
        # Mock table
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        # Mock get_item returning no item
        mock_table.get_item.return_value = {}

        captured_stderr = io.StringIO()
        sys.stderr = captured_stderr

        with self.assertRaises(SystemExit) as cm:
            release_account.release_account('123')

        self.assertEqual(cm.exception.code, 1)

        output = captured_stderr.getvalue()
        # Helper to find JSON in mixed output
        error_json = None
        for line in output.splitlines():
            try:
                error_json = json.loads(line)
                break
            except json.JSONDecodeError:
                continue

        if error_json:
            self.assertEqual(error_json['status'], 'error')
            self.assertIn('not found', error_json['message'])
        else:
            self.fail(f"Could not find valid JSON in output: {output}")

        sys.stderr = sys.__stderr__

    @patch('release_account.boto3.resource')
    def test_client_error(self, mock_boto_resource):
        mock_table = MagicMock()
        mock_boto_resource.return_value.Table.return_value = mock_table

        # Mock get_item to fail
        mock_table.get_item.side_effect = ClientError(
            {'Error': {'Code': 'ProvisionedThroughputExceededException', 'Message': 'Rate exceeded'}},
            'GetItem'
        )

        captured_stderr = io.StringIO()
        sys.stderr = captured_stderr

        with self.assertRaises(SystemExit) as cm:
            release_account.release_account('123')

        self.assertEqual(cm.exception.code, 1)

        output = captured_stderr.getvalue()
        # Helper to find JSON in mixed output
        error_json = None
        for line in output.splitlines():
            try:
                error_json = json.loads(line)
                break
            except json.JSONDecodeError:
                continue

        if error_json:
            self.assertEqual(error_json['status'], 'error')
        else:
            self.fail(f"Could not find valid JSON in output: {output}")

        sys.stderr = sys.__stderr__

if __name__ == '__main__':
    unittest.main()