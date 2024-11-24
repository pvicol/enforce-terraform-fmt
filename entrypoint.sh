#!/bin/sh -l
set -e

# Validate a Terraform version was passed
if [ -z "${INPUT_TERRAFORM_VERSION}" ]; then
  echo "No terraform version specified"
  exit 1
fi

# Validate the Terraform version is valid
VERSION=$(expr "${INPUT_TERRAFORM_VERSION}" : "[0-9]\\+\.[0-9]\\+\.[0-9]\\+")
if [ "$VERSION" = "0" ]; then
  echo "Invalid terraform version specified"
  exit 1
fi

# Fix git directory
git config --global --add safe.directory "$PWD"

# Validate there are enough commits to compare with
if [ "$(git rev-list --count HEAD)" -lt 2 ]; then
  echo "Not enough commits to compare"
  exit 0
fi

# Download Terraform
curl -fSL "https://releases.hashicorp.com/terraform/${INPUT_TERRAFORM_VERSION}/terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip" \
--output "terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip" || {
  echo "Failed to download Terraform version ${INPUT_TERRAFORM_VERSION}"
  exit 1
}

# Unzip the Terraform archive
if [ -f "terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip" ]; then
    unzip -o "terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip"
else
  echo "Couldn't find terraform version"
  exit 1
fi

# get the changed .tf/.tf.json files
FAILED="false"
for FILENAME in $(git diff --name-only HEAD HEAD~1); do
    if [ ! "$(expr "${FILENAME}" : ".*\.[tf|tf.json]")" = "0" ]; then
        # fmt them
        RESULT=$(./terraform fmt "${FILENAME}" || echo "error")
        if [ "${RESULT}" = "${FILENAME}" ] || [ "${RESULT}" = "error" ]; then
            FAILED="true"
            echo "${FILENAME} failed"
        else
          echo "${FILENAME} is ok"
        fi
    fi
done

if [ "$FAILED" = "true" ] ; then
    # output the git diff
    echo "diff=$(git diff "$(git diff --name-only HEAD HEAD~1)")" >> "$GITHUB_ENV"
    exit 1
fi
exit 0
