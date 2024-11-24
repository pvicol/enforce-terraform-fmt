#!/bin/sh -l
set -e

# Validate input
if [ -z "${INPUT_TERRAFORM_VERSION}" ]; then
  echo "No Terraform version specified"
  exit 1
fi

VERSION=$(expr "${INPUT_TERRAFORM_VERSION}" : "[0-9]\+\.[0-9]\+\.[0-9]\+")
if [ "$VERSION" = "0" ]; then
  echo "Invalid Terraform version specified"
  exit 1
fi

# Ensure enough commits exist
if [ "$(git rev-list --count HEAD)" -lt 2 ]; then
  echo "Not enough commits to compare"
  exit 0
fi

# Download and unzip Terraform
curl -fSL "https://releases.hashicorp.com/terraform/${INPUT_TERRAFORM_VERSION}/terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip" \
--output terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip || {
  echo "Failed to download Terraform version ${INPUT_TERRAFORM_VERSION}"
  exit 1
}

unzip -o terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip

# Get changed files
CHANGED_FILES=$(git diff --name-only HEAD HEAD~1)

# Exit early if no files have changed
if [ -z "$CHANGED_FILES" ]; then
  echo "No Terraform files changed."
  exit 0
fi

# Check Terraform formatting
FAILED="false"
for FILENAME in $CHANGED_FILES; do
    if [[ "$FILENAME" =~ \.(tf|tf\.json)$ ]]; then
        RESULT=$(./terraform fmt "$FILENAME" || echo "error")
        if [ "$RESULT" = "$FILENAME" ] || [ "$RESULT" = "error" ]; then
            FAILED="true"
            echo "$FILENAME failed formatting."
        else
            echo "$FILENAME is properly formatted."
        fi
    fi
done

# Output results
if [ "$FAILED" = "true" ]; then
    echo "Formatting errors found in the following files:"
    echo "diff=$(git diff "$CHANGED_FILES")" >> "$GITHUB_ENV"
    exit 1
else
    echo "All Terraform files are properly formatted."
fi

exit 0
