"""
AWS Lambda handler for MyRunStreak.com sync function.

This is a PLACEHOLDER that will be replaced by GitHub Actions deployment.
The actual sync logic is in src/lambda_sync.py

This handler is invoked by:
- EventBridge (daily scheduled sync)
- API Gateway (manual sync trigger)
"""

import json
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    Lambda function handler.

    Args:
        event: Event data (from EventBridge or API Gateway)
        context: Lambda context object

    Returns:
        Response dict for API Gateway or success status
    """
    logger.info(f"Lambda invoked: {json.dumps(event)}")

    # Determine invocation source
    source = event.get("source", "api-gateway")

    result = {
        "status": "success",
        "message": "Placeholder Lambda function - deploy actual code via GitHub Actions",
        "source": source,
        "timestamp": datetime.utcnow().isoformat(),
        "function_name": context.function_name,
        "function_version": context.function_version,
    }

    logger.info(f"Response: {result}")

    # Return response for API Gateway
    if source == "api-gateway" or "httpMethod" in event:
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps(result),
        }

    # Return simple dict for EventBridge
    return result
