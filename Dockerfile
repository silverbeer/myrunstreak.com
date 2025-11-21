# ==============================================================================
# Dockerfile for AWS Lambda - MyRunStreak Functions
# ==============================================================================
# This Dockerfile creates container images for Lambda functions.
# Uses AWS Lambda Python 3.12 base image for full compatibility.
#
# Benefits over ZIP deployment:
# - Full control over Python environment and dependencies
# - No platform mismatch issues (Pydantic v2 compiled extensions work correctly)
# - 10 GB image size limit vs 250 MB ZIP limit
# - Reproducible builds
#
# Build:
#   docker build --build-arg HANDLER_MODULE=sync_runs -t myrunstreak-sync .
#   docker build --build-arg HANDLER_MODULE=query_runs -t myrunstreak-query .
#
# Test locally:
#   docker run -p 9000:8080 myrunstreak-sync
#   curl -X POST "http://localhost:9000/2015-03-31/functions/function/invocations" \
#     -d '{"source":"local-test"}'
# ==============================================================================

# Use AWS Lambda Python 3.12 base image
# This image is optimized for Lambda runtime and includes the Lambda Runtime Interface
FROM public.ecr.aws/lambda/python:3.12

# Build argument to specify which handler to use
# Values: sync_runs, query_runs
ARG HANDLER_MODULE=sync_runs

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/var/task

# Install UV for faster dependency installation
# UV is our exclusive package manager per project guidelines
RUN pip install --no-cache-dir uv

# Copy dependency files first (for better layer caching)
COPY pyproject.toml uv.lock ./

# Export dependencies to requirements format and install
# --no-emit-project excludes the package itself, only exports dependencies
RUN uv export --frozen --no-dev --no-hashes --no-emit-project -o requirements.txt && \
    uv pip install --system --no-cache -r requirements.txt

# Copy application source code
COPY src/ ${LAMBDA_TASK_ROOT}/src/

# Fix permissions - strip any macOS extended attributes issues
# Ensure all files are readable
RUN chmod -R 755 ${LAMBDA_TASK_ROOT}/src

# Create the Lambda handler entry point
# This imports the correct handler based on HANDLER_MODULE build arg
RUN printf '%s\n' \
    '"""' \
    'AWS Lambda entry point for MyRunStreak.com function.' \
    '"""' \
    'import sys' \
    'import os' \
    '' \
    '# Ensure task_root is at the beginning of sys.path' \
    'task_root = os.environ.get("LAMBDA_TASK_ROOT", "/var/task")' \
    'if task_root not in sys.path:' \
    '    sys.path.insert(0, task_root)' \
    '' \
    "from src.lambdas.${HANDLER_MODULE}.handler import lambda_handler" \
    '' \
    '# Re-export the handler function for Lambda to invoke' \
    'handler = lambda_handler' \
    > ${LAMBDA_TASK_ROOT}/lambda_function.py

# Set the Lambda handler
# Format: filename.function_name
CMD ["lambda_function.handler"]
