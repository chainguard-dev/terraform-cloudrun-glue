resource "google_monitoring_alert_policy" "generate-access-token" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  # In the absence of data, incident will auto-close after an hour
  alert_strategy {
    auto_close = "3600s"

    notification_rate_limit {
      period = "3600s" // re-alert hourly if condition still valid.
    }
  }

  display_name = "Abnormal Access Token Generation: ${var.service-account}"
  combiner     = "OR"

  conditions {
    display_name = "Access Token Generation"

    condition_matched_log {
      filter = <<EOT
      logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Fdata_access"
      protoPayload.request.name="projects/-/serviceAccounts/${var.service-account}"
      protoPayload.serviceName="iamcredentials.googleapis.com"
      protoPayload.methodName="GenerateAccessToken"

      -- Allow these principals to generate tokens.
      ${join("\n", [for principal in var.allowed_principals : "-protoPayload.authenticationInfo.principalSubject=\"${principal}\""])}
      ${var.allowed_principal_regex != "" ? "-protoPayload.authenticationInfo.principalSubject=~\"${var.allowed_principal_regex}\"" : ""}
      EOT

      label_extractors = {
        "email"       = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
        "method_name" = "EXTRACT(protoPayload.methodName)"
        "user_agent"  = "REGEXP_EXTRACT(protoPayload.requestMetadata.callerSuppliedUserAgent, \"(\\\\S+)\")"
      }
    }
  }

  notification_channels = var.notification_channels

  enabled = "true"
  project = var.project_id
}
