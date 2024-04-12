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
| <a name="module_collapsible"></a> [collapsible](#module\_collapsible) | ../collapsible | n/a |
| <a name="module_oldest-unacked"></a> [oldest-unacked](#module\_oldest-unacked) | ../../widgets/xy | n/a |
| <a name="module_push-latency"></a> [push-latency](#module\_push-latency) | ../../widgets/latency | n/a |
| <a name="module_received-events"></a> [received-events](#module\_received-events) | ../../widgets/xy | n/a |
| <a name="module_unacked-messages-alert"></a> [unacked-messages-alert](#module\_unacked-messages-alert) | ../../widgets/alert | n/a |
| <a name="module_width"></a> [width](#module\_width) | ../width | n/a |

## Resources

| Name | Type |
|------|------|
| [google_monitoring_alert_policy.pubsub_unacked_messages](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alert_threshold"></a> [alert\_threshold](#input\_alert\_threshold) | n/a | `number` | `50000` | no |
| <a name="input_collapsed"></a> [collapsed](#input\_collapsed) | n/a | `bool` | `false` | no |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | n/a | `list(string)` | n/a | yes |
| <a name="input_subscription_prefix"></a> [subscription\_prefix](#input\_subscription\_prefix) | n/a | `string` | n/a | yes |
| <a name="input_title"></a> [title](#input\_title) | n/a | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_section"></a> [section](#output\_section) | n/a |
<!-- END_TF_DOCS -->
