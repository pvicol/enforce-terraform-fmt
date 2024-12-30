#!/bin/bash

# Save the tested script content
TEST_SCRIPT="entrypoint.sh"

fail() {
    echo "Error: $1" >&2
    return 1
}

# Setup test environment
oneTimeSetUp() {
    ORIG_PWD=$(pwd)
    TEST_DIR=$(mktemp -d) || fail "Failed to create temporary directory"
    cd "$TEST_DIR" || fail "Failed to change to test directory"
    cp "$ORIG_PWD/$TEST_SCRIPT" . || fail "Failed to copy test script"

    # Configure git
    git config --global init.defaultBranch master
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
}


# Cleanup test environment
oneTimeTearDown() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        cd "$ORIG_PWD" || return 1
        rm -rf "$TEST_DIR"
    fi
}

setUp() {
    # Create a new temporary directory for each test
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR" || exit 1

    # Clear any previous state
    unset INPUT_TERRAFORM_VERSION

    # Initialize git
    git init &>/dev/null || fail "Failed to initialize git repository"

    # Copy necessary files to test directory
    cp /app/entrypoint.sh .
}


tearDown() {
    # Return to original directory
    cd "$ORIG_PWD" || exit 1

    # Clean up test directory
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi

    # Clean up any terraform files
    rm -f terraform* 2>/dev/null || true
}


# Test Cases
test_missing_terraform_version() {
    local output
    output=$(./$TEST_SCRIPT 2>&1)
    status=$?
    assertEquals "Exit code should be 1" 1 "$status"
    assertEquals "No Terraform version specified" "$output"
}

test_invalid_terraform_version() {
    export INPUT_TERRAFORM_VERSION="invalid"
    local output
    output=$(./$TEST_SCRIPT 2>&1)
    status=$?
    assertEquals "Exit code should be 1" 1 "$status"
    assertEquals "Invalid Terraform version specified" "$output"
}

test_valid_terraform_version_no_files() {
    export INPUT_TERRAFORM_VERSION="1.0.0"
    local output
    output=$(./$TEST_SCRIPT 2>&1)
    status=$?
    assertTrue "Should contain no files message" "echo '$output' | grep -q 'No Terraform files to check'"
}

test_malformed_terraform_file() {
    export INPUT_TERRAFORM_VERSION="1.0.0"
    # Create a malformed terraform file
    cat > main.tf << EOF
resource "aws_instance" "example" {
ami="ami-12345678"

instance_type=      "t2.micro"



}
EOF
    git add main.tf
    git commit -m "Add malformed terraform file" &>/dev/null

    local output
    output=$(./$TEST_SCRIPT 2>&1)
    status=$?
    assertTrue "Should detect formatting issues" "echo '$output' | grep -q 'failed formatting'"
}

test_well_formatted_terraform_file() {
    export INPUT_TERRAFORM_VERSION="1.0.0"
    # Create a well-formatted terraform file
    cat > main.tf << EOF
resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}
EOF
    git add main.tf
    git commit -m "Add well-formatted terraform file" &>/dev/null

    local output
    output=$(./$TEST_SCRIPT 2>&1)
    status=$?
    assertTrue "Should indicate proper formatting" "echo '$output' | grep -q 'properly formatted'"
}

# Load shUnit2
. ./shunit2
