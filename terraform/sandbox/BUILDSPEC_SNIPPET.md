```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Lease an account
# The script outputs JSON like: {"account_id": "123456789", "status": "success", "credentials": {...}}
# Debug logs are printed to stderr, so we can capture stdout cleanly.
LEASE_OUTPUT=$(python3 scripts/lease_account.py)

# Extract account_id and credentials using python
eval $(echo "$LEASE_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(f'export ACCOUNT_ID={data[\"account_id\"]}')
    print(f'export AWS_ACCESS_KEY_ID={data[\"credentials\"][\"AccessKeyId\"]}')
    print(f'export AWS_SECRET_ACCESS_KEY={data[\"credentials\"][\"SecretAccessKey\"]}')
    # IAM User keys don't usually have session tokens, but we handle it if present
    if data[\"credentials\"].get(\"SessionToken\"):
        print(f'export AWS_SESSION_TOKEN={data[\"credentials\"][\"SessionToken\"]}')
except Exception as e:
    sys.exit(1)
")

if [ -z "$ACCOUNT_ID" ]; then
  echo "Failed to acquire account."
  exit 1
fi

echo "Leased Account ID: $ACCOUNT_ID"
echo "Identity acquired."

# Verify identity (optional)
aws sts get-caller-identity
```
