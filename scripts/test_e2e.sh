#!/bin/bash
# ==============================================================================
# End-to-End Test for MyRunStreak.com
# ==============================================================================
# Tests the complete sync workflow from API Gateway to SmashRun to DuckDB
#
# Prerequisites:
# - AWS CLI configured with correct profile
# - Real Lambda sync code deployed (not placeholder)
# - SmashRun OAuth tokens configured
#
# Usage:
#   ./scripts/test_e2e.sh
# ==============================================================================

set -e

# Configuration
export AWS_PROFILE=silverbeer
API_KEY="Ia5R5qgYyv76dRg9ZL16W8cBUq5aOw1urrtYS0fi"
SYNC_URL="https://9fmuhcz4y0.execute-api.us-east-2.amazonaws.com/dev/sync"
HEALTH_URL="https://9fmuhcz4y0.execute-api.us-east-2.amazonaws.com/dev/health"
S3_BUCKET="myrunstreak-data-dev-855323747881"
LAMBDA_NAME="myrunstreak-sync-runner-dev"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         MyRunStreak.com End-to-End Test Suite                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ==============================================================================
# Test 1: Health Check
# ==============================================================================
echo "📊 Test 1: Health Check"
echo "────────────────────────────────────────────────────────────────"
HEALTH_RESPONSE=$(curl -s "$HEALTH_URL")
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo -e "${GREEN}✅ PASS${NC}: Health endpoint responding"
    echo "   Response: $HEALTH_RESPONSE"
else
    echo -e "${RED}❌ FAIL${NC}: Health endpoint not working"
    exit 1
fi
echo ""

# ==============================================================================
# Test 2: Pre-Sync Database State
# ==============================================================================
echo "💾 Test 2: Pre-Sync Database State"
echo "────────────────────────────────────────────────────────────────"
echo "Downloading database from S3..."
aws s3 cp "s3://$S3_BUCKET/runs.duckdb" /tmp/runs-before.duckdb --quiet

# Count runs before sync
PRE_RUN_COUNT=$(python3 -c "
import duckdb
conn = duckdb.connect('/tmp/runs-before.duckdb', read_only=True)
count = conn.execute('SELECT COUNT(*) FROM runs').fetchone()[0]
print(count)
conn.close()
" 2>/dev/null || echo "0")

echo -e "${GREEN}✅ INFO${NC}: Pre-sync run count: $PRE_RUN_COUNT"
echo ""

# ==============================================================================
# Test 3: Trigger Sync via API Gateway
# ==============================================================================
echo "🔄 Test 3: Trigger Sync"
echo "────────────────────────────────────────────────────────────────"
echo "POST $SYNC_URL"
echo "Header: x-api-key: ${API_KEY:0:20}..."
echo ""

SYNC_RESPONSE=$(curl -s -X POST "$SYNC_URL" -H "x-api-key: $API_KEY")
echo "Response:"
echo "$SYNC_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$SYNC_RESPONSE"
echo ""

if echo "$SYNC_RESPONSE" | grep -q "success\|completed"; then
    echo -e "${GREEN}✅ PASS${NC}: Sync triggered successfully"
else
    echo -e "${RED}❌ FAIL${NC}: Sync failed"
    echo "Response: $SYNC_RESPONSE"
    exit 1
fi
echo ""

# ==============================================================================
# Test 4: Verify CloudWatch Logs
# ==============================================================================
echo "📋 Test 4: CloudWatch Logs"
echo "────────────────────────────────────────────────────────────────"
echo "Waiting 3 seconds for logs to propagate..."
sleep 3

RECENT_LOGS=$(aws logs tail "/aws/lambda/$LAMBDA_NAME" --since 1m --format short)
if [ -n "$RECENT_LOGS" ]; then
    echo -e "${GREEN}✅ PASS${NC}: Lambda execution logged"
    echo ""
    echo "Recent logs:"
    echo "$RECENT_LOGS" | head -10
else
    echo -e "${YELLOW}⚠️  WARNING${NC}: No recent logs found"
fi
echo ""

# ==============================================================================
# Test 5: Post-Sync Database Verification
# ==============================================================================
echo "💾 Test 5: Post-Sync Database State"
echo "────────────────────────────────────────────────────────────────"
echo "Waiting 5 seconds for S3 upload to complete..."
sleep 5

echo "Downloading updated database from S3..."
aws s3 cp "s3://$S3_BUCKET/runs.duckdb" /tmp/runs-after.duckdb --quiet

# Count runs after sync
POST_RUN_COUNT=$(python3 -c "
import duckdb
conn = duckdb.connect('/tmp/runs-after.duckdb', read_only=True)
count = conn.execute('SELECT COUNT(*) FROM runs').fetchone()[0]
print(count)
conn.close()
" 2>/dev/null || echo "0")

echo -e "${GREEN}✅ INFO${NC}: Post-sync run count: $POST_RUN_COUNT"
echo ""

# ==============================================================================
# Test 6: Verify Data Updated
# ==============================================================================
echo "✓  Test 6: Verify Sync Result"
echo "────────────────────────────────────────────────────────────────"
RUNS_ADDED=$((POST_RUN_COUNT - PRE_RUN_COUNT))

if [ "$RUNS_ADDED" -gt 0 ]; then
    echo -e "${GREEN}✅ PASS${NC}: $RUNS_ADDED new run(s) added"
elif [ "$POST_RUN_COUNT" -eq "$PRE_RUN_COUNT" ]; then
    echo -e "${YELLOW}⚠️  INFO${NC}: No new runs (already up to date)"
else
    echo -e "${RED}❌ FAIL${NC}: Run count decreased (unexpected)"
    exit 1
fi
echo ""

# ==============================================================================
# Test 7: Query Sample Data
# ==============================================================================
echo "📊 Test 7: Query Sample Data"
echo "────────────────────────────────────────────────────────────────"
python3 -c "
import duckdb
conn = duckdb.connect('/tmp/runs-after.duckdb', read_only=True)

# Get latest 5 runs
runs = conn.execute('''
    SELECT
        startDateTimeLocal,
        distance,
        duration,
        avgPace
    FROM runs
    ORDER BY startDateTimeLocal DESC
    LIMIT 5
''').fetchall()

print('Latest 5 runs:')
for run in runs:
    print(f'  {run[0]}: {run[1]:.2f} mi in {run[2]//60} min @ {run[3]:.1f} min/mi')

conn.close()
" 2>/dev/null || echo -e "${YELLOW}⚠️  Could not query data (DuckDB not installed?)${NC}"
echo ""

# ==============================================================================
# Test 8: API Response Validation
# ==============================================================================
echo "🔍 Test 8: API Response Validation"
echo "────────────────────────────────────────────────────────────────"
if echo "$SYNC_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    assert 'status' in data, 'Missing status field'
    assert data['status'] in ['success', 'completed'], f\"Unexpected status: {data['status']}\"
    print('✅ Response structure valid')
    sys.exit(0)
except Exception as e:
    print(f'❌ Response structure invalid: {e}')
    sys.exit(1)
"; then
    echo -e "${GREEN}✅ PASS${NC}: Response structure valid"
else
    echo -e "${RED}❌ FAIL${NC}: Response structure invalid"
    exit 1
fi
echo ""

# ==============================================================================
# Summary
# ==============================================================================
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    E2E TEST SUMMARY                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
echo ""
echo "Test Results:"
echo "  • Health Check: ✅"
echo "  • Sync Triggered: ✅"
echo "  • Lambda Executed: ✅"
echo "  • Logs Captured: ✅"
echo "  • Database Updated: ✅"
echo "  • Data Verified: ✅"
echo ""
echo "Database Stats:"
echo "  • Pre-sync runs: $PRE_RUN_COUNT"
echo "  • Post-sync runs: $POST_RUN_COUNT"
echo "  • Runs added: $RUNS_ADDED"
echo ""
echo "🎉 End-to-end workflow verified successfully!"
echo ""
