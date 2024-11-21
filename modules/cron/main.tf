terraform {
  required_providers {
    ko          = { source = "ko-build/ko" }
    google      = { source = "hashicorp/google" }
    google-beta = { source = "hashicorp/google-beta" }
  }
}

resource "google_project_service" "cloud_run_api" {
  service = "run.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "cloudscheduler" {
  service = "cloudscheduler.googleapis.com"

  disable_on_destroy = false
}

module "audit-cronjob-serviceaccount" {
  source = "../audit-serviceaccount"

  project_id      = var.project_id
  service-account = var.service_account

  # The absence of authorized identities here means that
  # nothing is authorized to act as this service account.
  # Note: Cloud Run's usage doesn't show up in the
  # audit logs.

  notification_channels = var.notification_channels
}

locals {
  repo = var.repository != "" ? var.repository : "gcr.io/${var.project_id}/${var.name}"
  squad_label = {
    "squad" : var.squad
  }
}

resource "ko_build" "image" {
  importpath  = var.importpath
  working_dir = var.working_dir
  base_image  = var.base_image
  repo        = local.repo
  env         = var.ko_build_env
}

resource "google_project_iam_member" "metrics-writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${var.service_account}"
}

resource "google_project_iam_member" "trace-writer" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${var.service_account}"
}

resource "google_project_iam_member" "profiler-writer" {
  project = var.project_id
  role    = "roles/cloudprofiler.agent"
  member  = "serviceAccount:${var.service_account}"
}

resource "google_cloud_run_v2_job" "job" {
  provider = google-beta
  project  = var.project_id

  name     = "${var.name}-cron"
  location = var.region
  labels   = merge(var.labels, local.squad_label)

  deletion_protection = var.deletion_protection

  template {
    parallelism = var.parallelism
    task_count  = var.task_count
    labels      = merge(var.labels, local.squad_label)

    template {
      execution_environment = var.execution_environment
      service_account       = var.service_account
      max_retries           = var.max_retries
      timeout               = var.timeout
      dynamic "volumes" {
        for_each = var.volumes
        content {
          name = volumes.value.name

          dynamic "empty_dir" {
            for_each = volumes.value.empty_dir != null ? { "" : volumes.value.empty_dir } : {}
            content {
              medium     = empty_dir.value.medium
              size_limit = empty_dir.value.size_limit
            }
          }

          dynamic "secret" {
            for_each = volumes.value.secret != null ? { "" : volumes.value.secret } : {}
            content {
              secret = secret.value.secret
              dynamic "items" {
                for_each = secret.value.items
                content {
                  version = items.value.version
                  path    = items.value.path
                }
              }
            }
          }
        }
      }
      containers {
        image = ko_build.image.image_ref

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = var.env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = var.secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }

        dynamic "volume_mounts" {
          for_each = var.volume_mounts
          content {
            name       = volume_mounts.value.name
            mount_path = volume_mounts.value.mount_path
          }
        }
      }

      dynamic "containers" {
        for_each = var.enable_otel_sidecar ? [1] : []
        content {
          image = var.otel_collector_image
          // config via env is an option; https://pkg.go.dev/go.opentelemetry.io/collector/service#section-readme
          args = ["--config=env:OTEL_CONFIG"]
          env {
            name  = "OTEL_CONFIG"
            value = file("${path.module}/otel-config/config.yaml")
          }
        }
      }

      dynamic "vpc_access" {
        for_each = var.vpc_access[*]
        content {
          dynamic "network_interfaces" {
            for_each = vpc_access.value.network_interfaces[*]
            content {
              network    = network_interfaces.value.network
              subnetwork = network_interfaces.value.subnetwork
              tags       = network_interfaces.value.tags
            }
          }
          egress = vpc_access.value.egress
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      launch_stage,
    ]
  }
}

data "google_client_config" "default" {}

// Call cloud run api to execute job once.
// https://cloud.google.com/run/docs/execute/jobs#command-line
resource "null_resource" "exec" {
  count = var.exec ? 1 : 0

  provisioner "local-exec" {
    command = join(" ", [
      "gcloud",
      "--project=${var.project_id}",
      "run",
      "jobs",
      "execute",
      google_cloud_run_v2_job.job.name,
      "--region=${google_cloud_run_v2_job.job.location}",
      "--wait"
    ])
  }

  lifecycle {
    // Trigger job each time cron job is modified.
    replace_triggered_by = [
      google_cloud_run_v2_job.job
    ]
  }
}

resource "google_service_account" "delivery" {
  project      = var.project_id
  account_id   = "${var.name}-dlv"
  display_name = "Dedicated service account for invoking ${google_cloud_run_v2_job.job.name}."
}

module "audit-delivery-serviceaccount" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  source = "../audit-serviceaccount"

  project_id      = var.project_id
  service-account = google_service_account.delivery.email

  # The absence of authorized identities here means that
  # nothing is authorized to act as this service account.
  # Note: Cloud Scheduler's usage doesn't show up in the
  # audit logs.

  notification_channels = var.notification_channels
}

resource "google_cloud_run_v2_job_iam_binding" "authorize-calls" {
  project  = google_cloud_run_v2_job.job.project
  location = google_cloud_run_v2_job.job.location
  name     = google_cloud_run_v2_job.job.name
  role     = "roles/run.invoker"
  members  = concat(["serviceAccount:${google_service_account.delivery.email}"], var.invokers)
}

// project iam, as job iam does allow user to actually list the job to access it
// only grant it to groups, individual should have access otherwise.
resource "google_project_iam_member" "authorize-list" {
  for_each = toset([for i in var.invokers : i if startswith(i, "group:")])

  project = google_cloud_run_v2_job.job.project
  role    = "roles/run.viewer"
  member  = each.key
}

locals {
  env_list_body = join(",", [for e in var.scheduled_env_overrides : "{\"name\": ${e.name}, \"value\": ${e.value}}"])
}

resource "google_cloud_scheduler_job" "cron" {
  paused = var.paused

  name     = "${var.name}-cron"
  schedule = var.schedule
  region   = var.region

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.job.name}:run"
    // Override body ref:
    //   https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job#body
    //   https://cloud.google.com/run/docs/reference/rest/v2/projects.locations.jobs/run#request-body
    body = length(var.scheduled_env_overrides) == 0 ? null : base64encode("{\"overrides\": { \"containerOverrides\": [ { \"name\": ${var.name}-1, \"env\" [ ${local.env_list_body} ] } ] } }")

    oauth_token {
      service_account_email = google_service_account.delivery.email
    }
  }
}

// Get a project number for this project ID.
data "google_project" "project" { project_id = var.project_id }

// What identity is deploying this?
data "google_client_openid_userinfo" "me" {}

// Create an alert policy to notify if the job is accessed by an unauthorized entity.
resource "google_monitoring_alert_policy" "anomalous-job-access" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  # In the absence of data, incident will auto-close after an hour
  alert_strategy {
    auto_close = "3600s"

    notification_rate_limit {
      period = "3600s" // re-alert hourly if condition still valid.
    }
  }

  display_name = "Abnormal CronJob Access: ${var.name}"
  combiner     = "OR"

  conditions {
    display_name = "Abnormal CronJob Access: ${var.name}"

    condition_matched_log {
      filter = <<EOT
      logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
      protoPayload.serviceName="run.googleapis.com"
      protoPayload.resourceName=("${join("\" OR \"", [
      "namespaces/${var.project_id}/jobs/${var.name}-cron",
      "projects/${var.project_id}/locations/${var.region}/jobs/${var.name}-cron",
      ])}")

      -- Allow CI to reconcile jobs and their IAM policies.
      -(
        protoPayload.authenticationInfo.principalEmail="${data.google_client_openid_userinfo.me.email}"
        protoPayload.methodName=("${join("\" OR \"", [
      "google.cloud.run.v2.Jobs.CreateJob",
      "google.cloud.run.v2.Jobs.UpdateJob",
      "google.cloud.run.v2.Jobs.SetIamPolicy",
])}")
      )
      -(
        protoPayload.authenticationInfo.principalEmail=~"${join("|", concat(var.invokers, [data.google_client_openid_userinfo.me.email]))}"
        protoPayload.methodName="google.cloud.run.v1.Jobs.RunJob"
      )
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

// Create an alert policy to notify if the job is accessed by an unauthorized entity.
resource "google_monitoring_alert_policy" "anomalous-job-execution" {
  # In the absence of data, incident will auto-close after an hour
  alert_strategy {
    auto_close = "3600s"

    notification_rate_limit {
      period = "3600s" // re-alert hourly if condition still valid.
    }
  }

  display_name = "Abnormal Job Execution: ${var.name}"
  combiner     = "OR"

  conditions {
    display_name = "Abnormal Job Execution: ${var.name}"

    condition_matched_log {
      filter = <<EOT
      logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Fdata_access"
      protoPayload.serviceName="run.googleapis.com"
      protoPayload.methodName="google.cloud.run.v1.Jobs.RunJob"
      protoPayload.resourceName=("${join("\" OR \"", [
      "namespaces/${var.project_id}/jobs/${var.name}-cron",
      "projects/${var.project_id}/locations/${var.region}/jobs/${var.name}-cron",
])}")

      -- Allow the delivery service account to run the job, but flag anyone else
      -protoPayload.authenticationInfo.principalEmail=~"${join("|", [google_service_account.delivery.email, data.google_client_openid_userinfo.me.email])}"
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


resource "google_monitoring_alert_policy" "success" {
  count = var.success_alert_alignment_period_seconds == 0 ? 0 : 1

  # In the absence of data, incident will auto-close after an hour
  alert_strategy {
    auto_close = "3600s"
  }

  display_name = "Cloud Run Job Success Execcution: ${var.name}"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run Job Success Execcution: ${var.name}"

    condition_absent {
      filter = <<EOT
        resource.type = "cloud_run_job"
        AND resource.labels.job_name = "${google_cloud_run_v2_job.job.name}"
        AND metric.type = "run.googleapis.com/job/completed_execution_count"
        AND metric.labels.result = "succeeded"
      EOT

      aggregations {
        alignment_period     = "${var.success_alert_alignment_period_seconds}s"
        cross_series_reducer = "REDUCE_NONE"
        per_series_aligner   = "ALIGN_MAX"
      }

      duration = "${ceil(var.success_alert_alignment_period_seconds / 4)}s"
      trigger {
        count = "1"
      }
    }
  }

  notification_channels = var.notification_channels

  enabled = "true"
  project = var.project_id
}
