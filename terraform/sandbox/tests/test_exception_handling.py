import unittest
from unittest.mock import MagicMock, patch
import os
import sys
import json
from botocore.exceptions import ClientError

# Ensure scripts directory is in path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'scripts')))

import lease_account
import release_account

class TestExceptionHandling(unittest.TestCase):
    def setUp(self):
        self.account_id = '123456789012'

    @patch('lease_account.subprocess.run')
    @patch('lease_account.boto3')
    @patch('time.sleep', return_value=None)
    def test_lease_account_handles_no_such_entity(self, mock_sleep, mock_boto3, mock_subprocess):
        # Mock cloud-nuke success
        mock_subprocess.return_value.returncode = 0
        # Mock DynamoDB
        mock_dynamo = MagicMock()
        mock_table = MagicMock()
        mock_boto3.resource.return_value = mock_dynamo
        mock_dynamo.Table.return_value = mock_table

        # Mock Table Scan
        mock_table.scan.side_effect = [
            {'Items': [{'account_id': self.account_id, 'status': 'AVAILABLE'}]},
            {'Items': [{'account_id': self.account_id, 'status': 'AVAILABLE'}]}
        ]

        # Mock STS
        mock_sts = MagicMock()
        mock_boto3.client.return_value = mock_sts
        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'ASIA_ROLE',
                'SecretAccessKey': 'SECRET_ROLE',
                'SessionToken': 'TOKEN_ROLE',
                'Expiration': '2025-01-01T00:00:00Z' # Simplified
            }
        }

        # Mock IAM
        mock_iam = MagicMock()
        mock_iam_user = MagicMock()

        # Configure resource side effect
        def resource_side_effect(*args, **kwargs):
            if args[0] == 'dynamodb':
                return mock_dynamo
            if args[0] == 'iam':
                return mock_iam
            return MagicMock()

        mock_boto3.resource.side_effect = resource_side_effect

        # Mock User logic
        mock_iam.User.return_value = mock_iam_user
        mock_iam.create_user.return_value = mock_iam_user # return same mock for simplicity

        mock_key_pair = MagicMock()
        mock_key_pair.id = 'AKIA_NEW'
        mock_key_pair.secret = 'SECRET_NEW'
        mock_iam_user.create_access_key_pair.return_value = mock_key_pair

        # RAISE NoSuchEntity when loading user
        error_response = {'Error': {'Code': 'NoSuchEntity', 'Message': 'User not found'}}
        mock_iam_user.load.side_effect = ClientError(error_response, 'GetUser')

        # Run
        from io import StringIO
        captured_output = StringIO()
        sys.stdout = captured_output

        lease_account.lease_account()

        sys.stdout = sys.__stdout__
        output = json.loads(captured_output.getvalue())

        # Verify success
        self.assertEqual(output['status'], 'success')
        self.assertEqual(output['credentials']['AccessKeyId'], 'AKIA_NEW')

        # Verify load was called
        mock_iam_user.load.assert_called()


    @patch('release_account.subprocess.run')
    @patch('release_account.boto3')
    def test_release_account_handles_no_such_entity(self, mock_boto3, mock_subprocess):
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
        mock_iam_user = MagicMock()

        def resource_side_effect(*args, **kwargs):
            if args[0] == 'dynamodb':
                return mock_dynamo
            if args[0] == 'iam':
                return mock_iam
            return MagicMock()

        mock_boto3.resource.side_effect = resource_side_effect

        mock_iam.User.return_value = mock_iam_user

        # RAISE NoSuchEntity
        error_response = {'Error': {'Code': 'NoSuchEntity', 'Message': 'User not found'}}
        mock_iam_user.load.side_effect = ClientError(error_response, 'GetUser')

        # Run
        from io import StringIO
        captured_stdout = StringIO()
        sys.stdout = captured_stdout

        release_account.release_account(self.account_id)

        sys.stdout = sys.__stdout__
        output = captured_stdout.getvalue()

        # Verify it printed "not found" message
        self.assertIn("not found in account", output)
        self.assertIn("Successfully released account", output)

if __name__ == '__main__':
    unittest.main()
