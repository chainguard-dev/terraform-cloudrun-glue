# `audit-serviceaccount`

This module creates an alert policy to monitor the principals that are
generating tokens for a particular service account.

The set of authorized principals can be enumerated explicitly:
```hcl
module "audit-foo-usage" {
  source = "chainguard-dev/common/infra//modules/audit-serviceaccount"

  project_id      = var.project_id
  service-account = google_service_account.foo.email

  allowed_principals = [
    # Only GKE should generate tokens for this service account.
    "serviceAccount:${var.project_id}.svc.id.goog[foo-system/foo]",
  ]

  notification_channels = var.notification_channels
}
```

Or a regular expression can be provided for the allowed principals:
```hcl
module "audit-foo-usage" {
  source = "chainguard-dev/common/infra//modules/audit-serviceaccount"

  project_id      = var.project_id
  service-account = google_service_account.foo.email

  # Match v1.2.3 style tags on this repository.
  allowed_principal_regex = "principal://iam[.]googleapis[.]com/${google_iam_workload_identity_pool.pool.name}/subject/repo:chainguard-dev/terraform-infra-common:ref:refs/tags/v[0-9]+[.][0-9]+[.][0-9]+"

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

No modules.

## Resources

| Name | Type |
|------|------|
| [google_monitoring_alert_policy.generate-access-token](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_principal_regex"></a> [allowed\_principal\_regex](#input\_allowed\_principal\_regex) | A regular expression to match allowed principals. | `string` | `""` | no |
| <a name="input_allowed_principals"></a> [allowed\_principals](#input\_allowed\_principals) | The list of principals authorized to assume this identity. | `list(string)` | `[]` | no |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | The list of notification channels to alert when this policy fires. | `list(string)` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_service-account"></a> [service-account](#input\_service-account) | The email of the service account being audited. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
