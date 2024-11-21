terraform {
  required_providers {
    ko     = { source = "ko-build/ko" }
    cosign = { source = "chainguard-dev/cosign" }
  }
}

data "google_project" "project" {
  project_id = var.project_id
}

locals {
  regional-types = merge([
    for region in keys(var.regions) : merge([
      for type in keys(var.types) : {
        "${region}-${type}" : {
          region = region
          type   = type
        }
      }
    ]...)
  ]...)
}

resource "random_id" "suffix" {
  byte_length = 2
}

resource "google_storage_bucket" "recorder" {
  for_each = var.regions

  name          = "${var.name}-${each.key}-${random_id.suffix.hex}"
  project       = var.project_id
  location      = each.key
  force_destroy = !var.deletion_protection

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      // 1 week + 1 day buffer
      age = 8
    }
  }
}

// What identity is deploying this?
data "google_client_openid_userinfo" "me" {}

resource "google_monitoring_alert_policy" "bucket-access" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  # In the absence of data, incident will auto-close after an hour
  alert_strategy {
    auto_close = "3600s"

    notification_rate_limit {
      period = "3600s" // re-alert hourly if condition still valid.
    }
  }

  display_name = "Abnormal Event Bucket Access: ${var.name}"
  combiner     = "OR"

  conditions {
    display_name = "Bucket Access"

    condition_matched_log {
      filter = <<EOT
      logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Fdata_access"
      protoPayload.serviceName="storage.googleapis.com"
      protoPayload.resourceName=~"projects/_/buckets/${var.name}-(${join("|", keys(var.regions))})-${random_id.suffix.hex}"

      -- Exclude things that happen during terraform plan.
      -protoPayload.methodName=("storage.buckets.get")

      -- Don't alert if someone just opens the bucket list in the UI
      -protoPayload.methodName=("storage.managedFolders.list")

      -- The recorder service write objects into the bucket.
      -(
        protoPayload.authenticationInfo.principalEmail="${google_service_account.recorder.email}"
        protoPayload.methodName="storage.objects.create"
      )

      -- The importer identity (used by DTS) enumerates and reads objects.
      -(
        protoPayload.authenticationInfo.principalEmail="${google_service_account.import-identity.email}"
        protoPayload.methodName=("storage.objects.get" OR "storage.objects.list")
      )

      -- Our CI identity reconciles the bucket.
      -(
        protoPayload.authenticationInfo.principalEmail="${data.google_client_openid_userinfo.me.email}"
        protoPayload.methodName=("storage.getIamPermissions")
      )

      -- Security scanners frequently probe for public buckets via listing buckets
      -- and then getting permissions, so we ignore these even though they pierce
      -- the abstraction.
      -protoPayload.methodName="storage.getIamPermissions"
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
