# `github-gsa`

This module creates a Google Service Account that can be assumed by particular
GitHub Actions workflows. It is intended to be used in conjunction with the
[`github-wif-provider` module](./github-wif-provider/README.md).

```hcl
module "github-wif" {
  source = "chainguard-dev/common/infra//modules/github-wif-provider"

  project_id = var.project_id
  name       = "my-wif-pool"

  notification_channels = var.notification_channels
}

module "foo" {
  source = "chainguard-dev/common/infra//modules/github-gsa"

  project_id = var.project_id
  name       = "foo"
  wif-pool   = module.github-wif.pool_name

  repository   = "the-org/the-repo"
  refspec      = "refs/heads/main"
  workflow_ref = ".github/workflows/my-workflow.yaml"

  notification_channels = var.notification_channels
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_audit-usage"></a> [audit-usage](#module\_audit-usage) | ../audit-serviceaccount | n/a |

## Resources

| Name | Type |
|------|------|
| [google_service_account.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_binding.allow-impersonation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_binding) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_audit_refspec"></a> [audit\_refspec](#input\_audit\_refspec) | The regular expression to use for auditing the refspec component when using '*' | `string` | `""` | no |
| <a name="input_audit_workflow_ref"></a> [audit\_workflow\_ref](#input\_audit\_workflow\_ref) | The regular expression to use for auditing the workflow ref component when using '*' | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | The name to give the service account. | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | The list of notification channels to alert when the service account is misused. | `list(string)` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_refspec"></a> [refspec](#input\_refspec) | The refspec to allow to federate with this identity. | `string` | n/a | yes |
| <a name="input_repository"></a> [repository](#input\_repository) | The name of the repository to allow to assume this identity. | `string` | n/a | yes |
| <a name="input_wif-pool"></a> [wif-pool](#input\_wif-pool) | The name of the Workload Identity Federation pool. | `string` | n/a | yes |
| <a name="input_workflow_ref"></a> [workflow\_ref](#input\_workflow\_ref) | The workflow to allow to federate with this identity (e.g. .github/workflows/deploy.yaml). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_email"></a> [email](#output\_email) | n/a |
<!-- END_TF_DOCS -->
