# Testing Guide

## 📚 Table of Contents

1. [Current State Testing](#current-state-testing)
2. [Full End-to-End Testing](#full-end-to-end-testing)
3. [Manual Testing](#manual-testing)
4. [Monitoring and Debugging](#monitoring-and-debugging)

---

## Current State Testing

**What Works Now**: Infrastructure is deployed, but Lambda has placeholder code.

### Run Current Tests

```bash
# Test API Gateway → Lambda → CloudWatch Logs
curl https://9fmuhcz4y0.execute-api.us-east-2.amazonaws.com/dev/health
curl -X POST https://9fmuhcz4y0.execute-api.us-east-2.amazonaws.com/dev/sync \
  -H "x-api-key: $(cd terraform/environments/dev && terraform output -raw api_key_value)"
```

**What's Being Tested**:
- ✅ API Gateway endpoints respond
- ✅ API key authentication works
- ✅ Lambda function executes
- ✅ CloudWatch logs are captured
- ⚠️ **Not tested**: Actual SmashRun sync (placeholder code)

---

## Full End-to-End Testing

**When**: After deploying real Lambda sync code

### Prerequisites

1. **Real Lambda code deployed** (not placeholder)
2. **SmashRun OAuth tokens configured** in Secrets Manager
3. **AWS CLI configured** with correct profile
4. **Python 3.12+** with DuckDB installed

### Install DuckDB (if needed)

```bash
pip install duckdb
# or
uv pip install duckdb
```

### Run Full E2E Test

```bash
# Automated test script
./scripts/test_e2e.sh
```

**What This Tests**:
1. Health check endpoint
2. Pre-sync database state
3. Trigger sync via API Gateway
4. Verify Lambda execution
5. Check CloudWatch logs
6. Verify database updated in S3
7. Query sample data
8. Validate API response structure

**Expected Output**:
```
╔════════════════════════════════════════════════════════════════╗
║         MyRunStreak.com End-to-End Test Suite                 ║
╚════════════════════════════════════════════════════════════════╝

📊 Test 1: Health Check
✅ PASS: Health endpoint responding

💾 Test 2: Pre-Sync Database State
✅ INFO: Pre-sync run count: 31

🔄 Test 3: Trigger Sync
✅ PASS: Sync triggered successfully

...

╔════════════════════════════════════════════════════════════════╗
║                    E2E TEST SUMMARY                            ║
╚════════════════════════════════════════════════════════════════╝

✅ ALL TESTS PASSED

Database Stats:
  • Pre-sync runs: 31
  • Post-sync runs: 35
  • Runs added: 4

🎉 End-to-end workflow verified successfully!
```

---

## Manual Testing

### Test Health Endpoint

```bash
curl https://9fmuhcz4y0.execute-api.us-east-2.amazonaws.com/dev/health
```

**Expected**:
```json
{
  "environment": "dev",
  "service": "myrunstreak-api",
  "status": "healthy",
  "timestamp": "01/Nov/2025:14:30:00 +0000"
}
```

### Test Sync Endpoint

```bash
# Get API key
cd terraform/environments/dev
API_KEY=$(terraform output -raw api_key_value)

# Trigger sync
curl -X POST https://9fmuhcz4y0.execute-api.us-east-2.amazonaws.com/dev/sync \
  -H "x-api-key: $API_KEY" | jq
```

**Expected (after real code deployed)**:
```json
{
  "status": "success",
  "runs_synced": 4,
  "total_runs": 35,
  "sync_time_ms": 1234,
  "timestamp": "2025-11-01T14:30:00"
}
```

### Test Lambda Directly

```bash
export AWS_PROFILE=silverbeer

# Invoke Lambda directly (bypass API Gateway)
aws lambda invoke \
  --function-name myrunstreak-sync-runner-dev \
  --payload '{"source":"manual-test","action":"sync"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda-response.json

# View response
cat /tmp/lambda-response.json | jq
```

### Download and Query Database

```bash
export AWS_PROFILE=silverbeer

# Download database from S3
aws s3 cp s3://myrunstreak-data-dev-855323747881/runs.duckdb /tmp/runs.duckdb

# Query with DuckDB CLI
duckdb /tmp/runs.duckdb

# Or query with Python
python3 <<'EOF'
import duckdb
conn = duckdb.connect('/tmp/runs.duckdb', read_only=True)

# Get total runs
total = conn.execute('SELECT COUNT(*) FROM runs').fetchone()[0]
print(f"Total runs: {total}")

# Get latest 5 runs
runs = conn.execute('''
    SELECT startDateTimeLocal, distance, duration
    FROM runs
    ORDER BY startDateTimeLocal DESC
    LIMIT 5
''').fetchall()

print("\nLatest 5 runs:")
for run in runs:
    print(f"  {run[0]}: {run[1]:.2f} mi in {run[2]//60} min")

conn.close()
EOF
```

---

## Monitoring and Debugging

### View Lambda Logs (Live)

```bash
export AWS_PROFILE=silverbeer

# Tail logs (live view)
aws logs tail /aws/lambda/myrunstreak-sync-runner-dev --follow

# View recent logs
aws logs tail /aws/lambda/myrunstreak-sync-runner-dev --since 10m --format short

# Filter for errors
aws logs tail /aws/lambda/myrunstreak-sync-runner-dev --since 1h --filter-pattern "ERROR"
```

### View API Gateway Logs

```bash
export AWS_PROFILE=silverbeer

# API Gateway execution logs
aws logs tail /aws/apigateway/myrunstreak-dev --follow

# Recent API calls
aws logs tail /aws/apigateway/myrunstreak-dev --since 30m
```

### Check Lambda Metrics

```bash
export AWS_PROFILE=silverbeer

# Get invocation count (last hour)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=myrunstreak-sync-runner-dev \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 3600 \
  --statistics Sum

# Get error count
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=myrunstreak-sync-runner-dev \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 3600 \
  --statistics Sum
```

### Test EventBridge Schedule

```bash
export AWS_PROFILE=silverbeer

# Check EventBridge rule status
aws events describe-rule --name myrunstreak-daily-sync-dev

# List recent EventBridge invocations (check CloudTrail or Lambda logs)
aws logs tail /aws/lambda/myrunstreak-sync-runner-dev --since 24h --filter-pattern "eventbridge"

# Manually trigger EventBridge rule (for testing)
aws events put-events --entries '[{
  "Source": "manual-test",
  "DetailType": "Manual Trigger",
  "Detail": "{\"action\":\"test-eventbridge\"}"
}]'
```

### Verify S3 Database

```bash
export AWS_PROFILE=silverbeer

# List database file with metadata
aws s3 ls s3://myrunstreak-data-dev-855323747881/runs.duckdb --human-readable

# Check file size and last modified
aws s3api head-object --bucket myrunstreak-data-dev-855323747881 --key runs.duckdb

# Download for inspection
aws s3 cp s3://myrunstreak-data-dev-855323747881/runs.duckdb /tmp/runs.duckdb
ls -lh /tmp/runs.duckdb
```

### Check Secrets Manager

```bash
export AWS_PROFILE=silverbeer

# List secrets
aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `myrunstreak`)].Name'

# Get secret metadata (not the actual secret value!)
aws secretsmanager describe-secret --secret-id myrunstreak/dev/smashrun/oauth

# Retrieve secret value (if needed for debugging)
aws secretsmanager get-secret-value --secret-id myrunstreak/dev/smashrun/oauth --query SecretString --output text | jq
```

---

## Troubleshooting Common Issues

### "Internal Server Error" from API Gateway

**Check**: Lambda permissions

```bash
export AWS_PROFILE=silverbeer
aws lambda get-policy --function-name myrunstreak-sync-runner-dev
```

Should show permissions for `apigateway.amazonaws.com`.

### Lambda Times Out

**Check**: Lambda timeout and logs

```bash
# View timeout setting
aws lambda get-function-configuration --function-name myrunstreak-sync-runner-dev --query Timeout

# Check logs for timeout errors
aws logs tail /aws/lambda/myrunstreak-sync-runner-dev --since 1h --filter-pattern "Task timed out"
```

### No Runs Being Synced

**Check**:
1. SmashRun OAuth tokens in Secrets Manager
2. Lambda has internet access
3. SmashRun API is responding

```bash
# Test SmashRun API directly (requires valid access token)
curl -H "Authorization: Bearer YOUR_ACCESS_TOKEN" https://api.smashrun.com/v1/my/activities/search

# Check Lambda logs for API errors
aws logs tail /aws/lambda/myrunstreak-sync-runner-dev --since 1h --filter-pattern "SmashRun"
```

---

## Next Steps

1. **Deploy real Lambda code** via GitHub Actions
2. **Run E2E test** with `./scripts/test_e2e.sh`
3. **Monitor daily sync** via CloudWatch
4. **Add more endpoints** for querying stats

---

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md) - System design
- [GitHub Actions Guide](./GITHUB_ACTIONS.md) - CI/CD pipeline
- [Terraform Guide](./TERRAFORM_GUIDE.md) - Infrastructure details
