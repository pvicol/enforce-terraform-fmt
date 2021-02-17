# Enforce Terraform fmt
Status check which fails if any of the committed files have changes after running `terraform fmt`

## Example usage
```yaml
uses: leigholiver/enforce-terraform-fmt@v1.0.0
with:
  terraform_version: 0.14.6
```

## Inputs
### `terraform_version`
**Required** The Terraform version to use

## Outputs
### `diff`
The diff of terraform fmt changes
