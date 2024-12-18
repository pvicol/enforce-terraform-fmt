#!/bin/sh -l
set -e

# Validate input
if [ -z "${INPUT_TERRAFORM_VERSION}" ]; then
  echo "No Terraform version specified"
  exit 1
fi

VERSION=$(expr "${INPUT_TERRAFORM_VERSION}" : "[0-9]\+\.[0-9]\+\.[0-9]\+")
if [ "${VERSION}" = "0" ]; then
  echo "Invalid Terraform version specified"
  exit 1
fi

# Download and unzip Terraform
curl -fSLs "https://releases.hashicorp.com/terraform/${INPUT_TERRAFORM_VERSION}/terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip" \
--output "terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip" || {
  echo "Failed to download Terraform version ${INPUT_TERRAFORM_VERSION}"
  exit 1
}

unzip -o "terraform_${INPUT_TERRAFORM_VERSION}_linux_amd64.zip"

# Set current directory as safe directory to be able to commit changed files and use diff
git config --global --add safe.directory "${PWD}"

# Get changed files
if git diff --name-only HEAD HEAD~1 >/dev/null 2>&1; then
  CHANGED_FILES=$(git diff --name-only HEAD HEAD~1 | grep -E '\.(tf|tf\.json)$')
  echo "Using git diff to determine changed files."
else
  echo "Unable to determine changed files using git diff. Checking all Terraform files."
  CHANGED_FILES=$(find . -type f \( -name "*.tf" -o -name "*.tf.json" \))
fi

# Exit early if no Terraform files are found or changed
if [ -z "${CHANGED_FILES}" ]; then
  echo "No Terraform files to check."
  exit 0
fi

# Check Terraform formatting
FAILED="false"
for FILENAME in $CHANGED_FILES; do
    # Skip deleted files
    if [ ! -f "$FILENAME" ]; then
        echo "Skipping deleted file: ${FILENAME}"
        continue
    fi
    case "$FILENAME" in
        *.tf|*.tf.json)
            echo "Checking formatting for ${FILENAME}"
            RESULT=$(./terraform fmt "$FILENAME" || echo "error")
            if [ "${RESULT}" = "${FILENAME}" ] || [ "${RESULT}" = "error" ]; then
                FAILED="true"
                echo "${FILENAME} failed formatting."
            else
                FAILED="false"
                echo "${FILENAME} is properly formatted."
            fi
            ;;
    esac
done

post_comment() {
  if [ "$GITHUB_TOKEN" ]; then
    # Extract the pull request number from the GitHub event JSON
    PR_NUMBER=$(jq -r '.pull_request.number // empty' "${GITHUB_EVENT_PATH}")

    # If there is no pull request number, exit the function
    if [ -z "${PR_NUMBER}" ]; then
      echo "Not a pull request, skipping comment."
      return 0
    fi

    # Extract the repository owner and name
    REPO_FULL_NAME=$(jq -r '.repository.full_name' "${GITHUB_EVENT_PATH}")

    API_URL="https://api.github.com/repos/${REPO_FULL_NAME}/issues/${PR_NUMBER}/comments"
    echo "Adding comment to PR #${PR_NUMBER} in ${REPO_FULL_NAME}..."
    JSON_BODY=$(jq -n --arg body "${1}" '{body: $body}')
    curl -s -X POST -H "Authorization: Bearer ${GITHUB_TOKEN}" \
       -H "Content-Type: application/json" \
       -d "${JSON_BODY}" \
       "${API_URL}"
  else
    # If Github token is not passed, print result to screen
    echo "${1}"
  fi
}

# Output results
if [ "${FAILED}" = "true" ]; then
    echo "Formatting errors found in the files"
    COMMENT_BODY=":x: **Formatting errors found in the following files:**\n\n"
    for FILE in $CHANGED_FILES; do
      # Skip deleted files
      if [ ! -f "${FILE}" ]; then
          echo "Skipping deleted file: ${FILE}"
          continue
      fi
      DIFF=$(git diff "${FILE}")
      COMMENT_BODY="${COMMENT_BODY}${FILE}\n\`\`\`\n${DIFF}\n\`\`\`\n\n"
    done

    # Render new lines before passing as payload to API
    COMMENT_BODY=$(printf "%b" "${COMMENT_BODY}")
    post_comment "${COMMENT_BODY}"
    exit 1
else
    post_comment ":white_check_mark: All Terraform files are properly formatted."
fi

exit 0
