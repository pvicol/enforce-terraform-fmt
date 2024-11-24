# Enforce Terraform fmt
Status check which fails if any of the committed files have changes after running `terraform fmt`

## Example usage
```yaml
name: Validate Terraform Code
on:
  pull_request:
    paths:
      - '**/*.tf'
      - '**/*.tfvars'

jobs:
  tf-validate:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout the contents
        uses: actions/checkout@v4
        with:
          fetch-depth: '' # all history for all branches and tags

      - name: Check Terraform code formatting
        uses: pvicol/enforce-terraform-fmt@v1.1.0
        with:
          terraform_version: 1.9.8

```

## Inputs
### `terraform_version`
**Required** The Terraform version to use

## Outputs
### `diff`
The diff of terraform fmt changes
