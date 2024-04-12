<!-- BEGIN_TF_DOCS -->

## Requirements

No requirements.

## Providers

| Name                                                      | Version |
| --------------------------------------------------------- | ------- |
| <a name="provider_google"></a> [google](#provider_google) | n/a     |

## Modules

| Name                                            | Source | Version |
| ----------------------------------------------- | ------ | ------- |
| <a name="module_cron"></a> [cron](#module_cron) | ../    | n/a     |

## Resources

| Name                                                                                                                          | Type     |
| ----------------------------------------------------------------------------------------------------------------------------- | -------- |
| [google_service_account.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |

## Inputs

| Name                                                            | Description                              | Type     | Default | Required |
| --------------------------------------------------------------- | ---------------------------------------- | -------- | ------- | :------: |
| <a name="input_project_id"></a> [project_id](#input_project_id) | The project that will host the cron job. | `string` | n/a     |   yes    |

## Outputs

No outputs.

<!-- END_TF_DOCS -->
