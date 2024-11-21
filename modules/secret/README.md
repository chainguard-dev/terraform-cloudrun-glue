# `secret`

This module encapsulates the creation of a Google Secret Manager secret to hold
sensitive data in a manner that can be used as an environment variable or
volume with Cloud Run.  Unlike `configmap` this data is considered sensitive and
so it is NOT loaded directly by this logic, but by an authorized party. Notably,
the built-in alert policy WILL fire when the authorized party loads new values
into the secret, this is by design.

```hcl
module "my-secret" {
  source = "chainguard-dev/common/infra//modules/secret"

  project_id = var.project_id
  name       = "my-secret"

  # What the service accessing this configuration will run as.
  service-account = google_service_account.foo.email

  # What group of identities are authorized to add new secret versions.
  authorized-adder = "group:oncall@my-corp.dev"

  # Optionally: channels to notify if this secret is manipulated.
  notification_channels = [ ... ]
}

module "foo-service" {
  source     = "chainguard-dev/common/infra//modules/regional-go-service"
  project_id = var.project_id
  name       = "foo"
  regions    = module.networking.regional-networks

  service_account = google_service_account.foo.email
  containers = {
    "foo" = {
      source = {
        working_dir = path.module
        importpath  = "./cmd/foo"
      }
      ports = [{ container_port = 8080 }]
      volume_mounts = [{
        name       = "foo"
        mount_path = "/var/run/foo/"
      }]
    }
  }
  volumes = [{
    name = "foo"
    secret = {
      secret = module.my-secret.secret_id
      items = [{
        version = "latest"
        path    = "my-filename"
      }]
    }
  }]
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
| [google_monitoring_alert_policy.anomalous-secret-access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_secret_manager_secret.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret_iam_binding.authorize-service-access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_binding) | resource |
| [google_secret_manager_secret_iam_binding.authorize-version-adder](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_binding) | resource |
| [google_secret_manager_secret_version.placeholder](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_project.project](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authorized-adder"></a> [authorized-adder](#input\_authorized-adder) | A member-style representation of the identity authorized to add new secret values (e.g. group:oncall@my-corp.dev). | `string` | n/a | yes |
| <a name="input_create_placeholder_version"></a> [create\_placeholder\_version](#input\_create\_placeholder\_version) | Whether to create a placeholder secret version to avoid bad reference on first deploy. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | The name to give the secret. | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | The channels to notify if the configuration data is improperly accessed. | `list(string)` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_service-account"></a> [service-account](#input\_service-account) | The email of the service account that will access the secret. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_secret_id"></a> [secret\_id](#output\_secret\_id) | The ID of the secret. |
<!-- END_TF_DOCS -->
