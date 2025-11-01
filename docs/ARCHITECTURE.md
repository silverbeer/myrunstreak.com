# MyRunStreak.com - AWS Serverless Architecture

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                                   │
│                                                                       │
│  ┌────────────────┐         ┌──────────────────┐                   │
│  │   CloudWatch   │────────▶│  Lambda Function │                   │
│  │  EventBridge   │  Daily  │   (Sync Runner)  │                   │
│  │  (Cron: 6am)   │  6am    └────────┬─────────┘                   │
│  └────────────────┘                  │                              │
│                                      │                              │
│  ┌────────────────┐                  │  ┌──────────────────┐       │
│  │  API Gateway   │                  ├─▶│  Secrets Manager │       │
│  │   (REST API)   │                  │  │  - SmashRun OAuth│       │
│  │                │                  │  │  - API Keys      │       │
│  │  /sync         │──────────────────┘  └──────────────────┘       │
│  │  /stats        │                                                 │
│  │  /health       │                     ┌──────────────────┐       │
│  └────────┬───────┘                     │   S3 Bucket      │       │
│           │                          ┌─▶│  runs.duckdb     │       │
│           │ API Key                  │  │  (versioned)     │       │
│           │ Required                 │  └──────────────────┘       │
│           ▼                          │                              │
│  ┌────────────────┐                  │  ┌──────────────────┐       │
│  │   IAM Roles    │                  └─▶│   CloudWatch     │       │
│  │ - Lambda Exec  │                     │      Logs        │       │
│  │ - API Gateway  │                     │  - Sync results  │       │
│  └────────────────┘                     │  - Errors        │       │
│                                         └──────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
                 ┌────────────────┐
                 │  SmashRun API  │
                 │  (External)    │
                 └────────────────┘
```

## 🎯 Core Components

### 1. **Lambda Function** (`sync-runner`)
**Purpose:** Execute the sync logic to fetch runs from SmashRun and update DuckDB

**Triggers:**
- CloudWatch EventBridge (daily at 6am EST)
- API Gateway (manual trigger via `/sync` endpoint)

**Responsibilities:**
- Fetch activities from SmashRun API
- Parse and validate data using Pydantic models
- Fetch per-mile splits for each activity
- Update DuckDB database
- Upload updated database to S3
- Return sync statistics

**Runtime:** Python 3.12
**Memory:** 512 MB
**Timeout:** 5 minutes
**Package Size:** ~50 MB (includes DuckDB, httpx, pydantic)

---

### 2. **API Gateway** (REST API)

**Purpose:** HTTP interface for triggering syncs and querying stats

#### Endpoints:

**`POST /sync`**
- Trigger a manual sync operation
- Returns: `{ "status": "success", "runs_synced": 31, "splits_stored": 118 }`
- Security: API Key required
- Rate Limit: 10 requests/minute

**`GET /stats`**
- Get current running statistics
- Returns: Current streak, total miles, fastest mile, etc.
- Security: API Key required
- Rate Limit: 100 requests/minute

**`GET /health`**
- Health check endpoint
- Returns: `{ "status": "healthy", "last_sync": "2025-10-31T06:00:00Z" }`
- Security: Public (no API key)
- Rate Limit: None

#### Security Layers:

1. **API Keys**
   - Each consumer gets a unique API key
   - Keys stored in Secrets Manager
   - Usage tracked in CloudWatch

2. **Usage Plans**
   - Rate limiting per endpoint
   - Throttling to prevent abuse
   - Quota limits (e.g., 1000 requests/day)

3. **IAM Authorization** (Optional)
   - AWS_IAM auth type for internal AWS services
   - Signature V4 signing required

4. **Resource Policies**
   - Restrict access by IP/CIDR (optional)
   - VPC endpoint access (optional)

---

### 3. **Secrets Manager**

**Purpose:** Securely store sensitive credentials

**Secrets Stored:**
```json
{
  "smashrun": {
    "client_id": "streak_xxxxx",
    "client_secret": "xxxxxxxx",
    "access_token": "xxxxxxxx",
    "refresh_token": "xxxxxxxx"
  },
  "api_keys": {
    "personal": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "github_actions": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}
```

**Features:**
- Automatic rotation (for API keys)
- Version tracking
- Encrypted at rest (KMS)
- IAM access control

---

### 4. **S3 Bucket**

**Purpose:** Store the DuckDB database file persistently

**Configuration:**
- **Bucket Name:** `myrunstreak-data-{account_id}`
- **Versioning:** Enabled (keep last 30 versions)
- **Encryption:** AES-256 (SSE-S3)
- **Lifecycle Policy:** Delete versions older than 30 days
- **Access:** Private (Lambda only)

**File Structure:**
```
s3://myrunstreak-data-{account_id}/
├── runs.duckdb              # Current database
├── runs.duckdb.backup       # Previous version (safety)
└── .versions/               # Version history (S3 versioning)
```

---

### 5. **CloudWatch EventBridge**

**Purpose:** Schedule automated daily syncs

**Cron Schedule:**
```
cron(0 11 * * ? *)  # 11:00 UTC = 6:00am EST (winter) / 7:00am EDT (summer)
```

**Event Payload:**
```json
{
  "source": "aws.events",
  "detail-type": "Scheduled Event",
  "detail": {
    "sync_type": "daily_automated"
  }
}
```

---

### 6. **CloudWatch Logs**

**Purpose:** Centralized logging and monitoring

**Log Groups:**
- `/aws/lambda/myrunstreak-sync-runner` - Lambda execution logs
- `/aws/apigateway/myrunstreak-api` - API Gateway access logs

**Metrics:**
- Sync duration
- Number of runs synced
- API errors
- Rate limit violations

**Alarms:**
- Sync failures (notify via SNS)
- High error rate (> 5% in 5 minutes)
- Lambda timeout (> 4.5 minutes)

---

## 🔐 Security Model

### Principle of Least Privilege

Each component has minimal required permissions:

#### Lambda Execution Role:
```
- secretsmanager:GetSecretValue (myrunstreak/* only)
- s3:GetObject (myrunstreak-data-* only)
- s3:PutObject (myrunstreak-data-* only)
- logs:CreateLogGroup
- logs:CreateLogStream
- logs:PutLogEvents
```

#### API Gateway Role:
```
- lambda:InvokeFunction (sync-runner only)
- logs:CreateLogGroup
- logs:CreateLogStream
- logs:PutLogEvents
```

### Network Security:
- Lambda runs in AWS managed VPC (no custom VPC needed)
- Outbound HTTPS to SmashRun API allowed
- No inbound connections to Lambda
- API Gateway uses AWS edge locations (CloudFront)

---

## 📊 Cost Estimation

**Monthly Costs (assuming 31 syncs/month):**

| Service | Usage | Cost |
|---------|-------|------|
| Lambda | 31 invocations × 30 sec × 512 MB | ~$0.00 (free tier) |
| API Gateway | ~50 requests/month | ~$0.00 (free tier) |
| S3 Storage | ~10 MB database | ~$0.00 |
| Secrets Manager | 2 secrets | ~$0.80/month |
| CloudWatch Logs | ~100 MB/month | ~$0.05/month |
| **Total** | | **~$0.85/month** |

*Note: All compute is within AWS Free Tier limits*

---

## 🚀 Deployment Strategy

### Infrastructure as Code (Terraform)

**Structure:**
```
terraform/
├── main.tf                 # Provider configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── backend.tf              # S3 backend for state
├── lambda.tf               # Lambda function resources
├── api_gateway.tf          # API Gateway resources
├── s3.tf                   # S3 bucket resources
├── secrets.tf              # Secrets Manager resources
├── cloudwatch.tf           # EventBridge + Logs
├── iam.tf                  # IAM roles and policies
└── environments/
    ├── dev.tfvars          # Development variables
    └── prod.tfvars         # Production variables
```

### GitHub Actions Workflows

**1. Terraform Plan (on PR)**
- Validate Terraform syntax
- Run `terraform plan`
- Post plan as PR comment
- Security scanning (tfsec)

**2. Terraform Apply (on merge to main)**
- Apply infrastructure changes
- Only if plan is approved
- Automatic rollback on failure

**3. Lambda Deploy (on code changes)**
- Package Lambda function
- Run tests (pytest)
- Upload to S3
- Update Lambda function code
- Run smoke tests

---

## 🔄 Sync Flow (Detailed)

### Daily Automated Sync:
```
1. EventBridge triggers Lambda at 6am EST
   ↓
2. Lambda downloads runs.duckdb from S3
   ↓
3. Lambda retrieves SmashRun credentials from Secrets Manager
   ↓
4. Lambda queries SmashRun API for new activities
   ↓
5. Lambda parses activities (Pydantic validation)
   ↓
6. Lambda fetches per-mile splits for each activity
   ↓
7. Lambda updates DuckDB database
   ↓
8. Lambda uploads updated runs.duckdb to S3
   ↓
9. Lambda logs results to CloudWatch
   ↓
10. Lambda returns success/failure status
```

### Manual Sync via API:
```
1. Client calls POST /sync with API key
   ↓
2. API Gateway validates API key
   ↓
3. API Gateway checks rate limits
   ↓
4. API Gateway invokes Lambda
   ↓
5. [Same as steps 2-9 above]
   ↓
6. Lambda returns JSON response to API Gateway
   ↓
7. API Gateway returns response to client
```

---

## 🎓 Learning Objectives

By building this architecture, you'll understand:

1. **Lambda Functions**
   - Execution model (event-driven)
   - Cold starts vs warm starts
   - Packaging dependencies (layers vs zip)
   - Environment variables vs Secrets Manager

2. **API Gateway**
   - REST API vs HTTP API (we'll use REST for features)
   - Request/response transformations
   - API key management
   - Usage plans and throttling
   - Integration with Lambda

3. **IAM**
   - Execution roles vs resource policies
   - Trust relationships
   - Least privilege principle
   - Service-to-service authentication

4. **Terraform**
   - Resource dependencies
   - State management (remote state in S3)
   - Workspaces (dev/prod)
   - Modules and reusability

5. **CI/CD**
   - GitHub Actions workflows
   - Infrastructure as Code deployment
   - Automated testing
   - Rollback strategies

---

## 📖 Next Steps

Now that you understand the architecture, we'll build it piece by piece:

1. ✅ Create Terraform directory structure
2. ✅ Set up S3 backend for Terraform state
3. ✅ Create Lambda function Terraform resources
4. ✅ Create API Gateway Terraform resources
5. ✅ Set up security (API keys, IAM roles)
6. ✅ Create GitHub Actions workflows
7. ✅ Deploy and test

Let's start building! 🚀
