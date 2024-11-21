# `configmap`

This module encapsulates the creation of a Google Secret Manager secret to hold
a piece of data in a manner that can be used as an environment variable or
volume with Cloud Run. As the expectation is that this data is not sensitive it
takes it directly to populate the secret.

```hcl
module "my-configmap" {
  source = "chainguard-dev/common/infra//modules/configmap"

  project_id = var.project_id
  name       = "my-configmap"

  # What the service accessing this configuration will run as.
  service-account = google_service_account.foo.email

  # The raw data of the configuration.
  data = <<EOT
  This is the data that will go into
  the "configmap".
  EOT

  # Optionally: channels to notify if this configuration is manipulated.
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
      secret = module.my-configmap.secret_id
      items = [{
        version = module.my-configmap.version
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
| [google_secret_manager_secret_iam_binding.authorize-access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_binding) | resource |
| [google_secret_manager_secret_version.data](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_client_openid_userinfo.me](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_openid_userinfo) | data source |
| [google_project.project](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_data"></a> [data](#input\_data) | The data to place in the secret. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name to give the secret. | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | The channels to notify if the configuration data is improperly accessed. | `list(string)` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_service-account"></a> [service-account](#input\_service-account) | The email of the service account that will access the secret. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_secret_id"></a> [secret\_id](#output\_secret\_id) | The ID of the secret. |
| <a name="output_secret_version_id"></a> [secret\_version\_id](#output\_secret\_version\_id) | The ID of the secret version. |
| <a name="output_version"></a> [version](#output\_version) | The secret version. |
<!-- END_TF_DOCS -->
