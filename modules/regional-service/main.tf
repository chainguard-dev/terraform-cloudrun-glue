module "audit-serviceaccount" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  source = "../audit-serviceaccount"

  project_id      = var.project_id
  service-account = var.service_account

  # The absence of authorized identities here means that
  # nothing is authorized to act as this service account.
  # Note: Cloud Run's usage doesn't show up in the audit logs.

  notification_channels = var.notification_channels
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

locals {
  // Pull out the containers from var.containers that has no port
  sidecars = {
    for key, value in var.containers : key => value if length(value.ports) == 0
  }
  // Pull out the main container from var.containers that has a port.
  // There should be only one of them, but using a map to make it easier to
  // iterate over and look up the ko_builds.
  has_port = {
    for key, value in var.containers : key => value if length(value.ports) > 0
  }

  default_labels = {
    "regional-service" : var.name
  }

  squad_label = {
    "squad" : var.squad
  }

  main_container_idx = keys(local.has_port)[0]
  main_container     = local.has_port[local.main_container_idx]
}

check "exactly_one_main_container" {
  assert {
    condition     = length(local.has_port) == 1
    error_message = "Exactly one container with ports must be specified."
  }
}

// Deploy the service into each of our regions.
resource "google_cloud_run_v2_service" "this" {
  for_each = var.regions

  provider = google-beta # For empty_dir
  project  = var.project_id
  name     = var.name
  location = each.key
  labels   = merge(var.labels, local.default_labels, local.squad_label)
  ingress  = var.ingress

  deletion_protection = var.deletion_protection

  template {
    scaling {
      min_instance_count = var.scaling.min_instances
      max_instance_count = var.scaling.max_instances
    }
    max_instance_request_concurrency = var.scaling.max_instance_request_concurrency
    execution_environment            = var.execution_environment
    labels                           = merge(var.labels, local.default_labels, local.squad_label)

    vpc_access {
      network_interfaces {
        network    = each.value.network
        subnetwork = each.value.subnet
      }
      egress = var.egress
      // TODO(mattmoor): When direct VPC egress supports network tags
      // for NAT egress, then we should incorporate those here.
    }
    service_account = var.service_account
    timeout         = "${var.request_timeout_seconds}s"

    // A main container has ports. It needs to go first to avoid a bug in the
    // Cloud Run terraform provider where omitting the port{} block does not
    // remove the port from the service.
    containers {
      image = local.main_container.image
      args  = local.main_container.args

      dynamic "ports" {
        for_each = local.main_container.ports
        content {
          name           = ports.value.name
          container_port = ports.value.container_port
        }
      }

      dynamic "resources" {
        for_each = local.main_container.resources != null ? { "" : local.main_container.resources } : {}
        content {
          limits            = resources.value.limits
          cpu_idle          = resources.value.cpu_idle
          startup_cpu_boost = resources.value.startup_cpu_boost
        }
      }

      dynamic "env" {
        for_each = local.main_container.env
        content {
          name  = env.value.name
          value = env.value.value
          dynamic "value_source" {
            for_each = env.value.value_source != null ? { "" : env.value.value_source } : {}
            content {
              secret_key_ref {
                secret  = value_source.value.secret_key_ref.secret
                version = value_source.value.secret_key_ref.version
              }
            }
          }
        }
      }

      // Iterate over regional environment variables and look up the
      // appropriate value to pass to each region.
      dynamic "env" {
        for_each = local.main_container.regional-env
        content {
          name  = env.value.name
          value = env.value.value[each.key]
        }
      }

      env {
        name  = "ENABLE_PROFILER"
        value = var.enable_profiler
      }

      dynamic "volume_mounts" {
        for_each = local.main_container.volume_mounts
        content {
          name       = volume_mounts.value.name
          mount_path = volume_mounts.value.mount_path
        }
      }
    }

    // Now the sidecar containers can be added.
    dynamic "containers" {
      for_each = local.sidecars
      content {
        image = containers.value.image
        args  = containers.value.args

        dynamic "resources" {
          for_each = containers.value.resources != null ? { "" : containers.value.resources } : {}
          content {
            limits            = resources.value.limits
            cpu_idle          = resources.value.cpu_idle
            startup_cpu_boost = resources.value.startup_cpu_boost
          }
        }

        dynamic "env" {
          for_each = containers.value.env
          content {
            name  = env.value.name
            value = env.value.value
            dynamic "value_source" {
              for_each = env.value.value_source != null ? { "" : env.value.value_source } : {}
              content {
                secret_key_ref {
                  secret  = value_source.value.secret_key_ref.secret
                  version = value_source.value.secret_key_ref.version
                }
              }
            }
          }
        }

        // Iterate over regional environment variables and look up the
        // appropriate value to pass to each region.
        dynamic "env" {
          for_each = containers.value.regional-env
          content {
            name  = env.value.name
            value = env.value.value[each.key]
          }
        }

        dynamic "volume_mounts" {
          for_each = containers.value.volume_mounts
          content {
            name       = volume_mounts.value.name
            mount_path = volume_mounts.value.mount_path
          }
        }
      }
    }
    containers {
      image = var.otel_collector_image
      // config via env is an option; https://pkg.go.dev/go.opentelemetry.io/collector/service#section-readme
      args = ["--config=env:OTEL_CONFIG"]
      env {
        name  = "OTEL_CONFIG"
        value = replace(file("${path.module}/otel-config/config.yaml"), "REPLACE_ME_TEAM", var.squad)
      }
    }

    dynamic "volumes" {
      for_each = var.volumes
      content {
        name = volumes.value.name

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

        dynamic "empty_dir" {
          for_each = volumes.value.empty_dir != null ? { "" : volumes.value.empty_dir } : {}
          content {
            medium     = empty_dir.value.medium
            size_limit = empty_dir.value.size_limit
          }
        }
      }
    }

    // Regional volumes
    dynamic "volumes" {
      for_each = var.regional-volumes
      content {
        name = volumes.value.name

        dynamic "gcs" {
          for_each = length(volumes.value.gcs) > 0 ? { "" : volumes.value.gcs[each.key] } : {}
          content {
            bucket    = gcs.value.bucket
            read_only = gcs.value.read_only
          }
        }
        dynamic "nfs" {
          for_each = length(volumes.value.nfs) > 0 ? { "" : volumes.value.nfs[each.key] } : {}
          content {
            server    = nfs.value.server
            path      = nfs.value.path
            read_only = nfs.value.read_only
          }
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

// Get a project number for this project ID.
data "google_project" "project" { project_id = var.project_id }

// What identity is deploying this?
data "google_client_openid_userinfo" "me" {}

// Create an alert policy to notify if the service is accessed by an unauthorized entity.
resource "google_monitoring_alert_policy" "anomalous-service-access" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  # In the absence of data, incident will auto-close after an hour
  alert_strategy {
    auto_close = "3600s"

    notification_rate_limit {
      period = "3600s" // re-alert hourly if condition still valid.
    }
  }

  display_name = "Abnormal Service Access: ${var.name}"
  combiner     = "OR"

  conditions {
    display_name = "Abnormal Service Access: ${var.name}"

    condition_matched_log {
      filter = <<EOT
      logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
      protoPayload.serviceName="run.googleapis.com"
      protoPayload.resourceName=("${join("\" OR \"", concat([
      "namespaces/${var.project_id}/services/${var.name}"
    ],
    [
      for region in keys(var.regions) : "projects/${var.project_id}/locations/${region}/services/${var.name}"
    ]))}")

      -- Allow CI to reconcile services and their IAM policies.
      -(
        protoPayload.authenticationInfo.principalEmail="${data.google_client_openid_userinfo.me.email}"
        protoPayload.methodName=("${join("\" OR \"", [
    "google.cloud.run.v2.Services.CreateService",
    "google.cloud.run.v2.Services.UpdateService",
    "google.cloud.run.v2.Services.SetIamPolicy",
])}")
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

// When the service is behind a load balancer, then it is publicly exposed and responsible
// for handling its own authentication.
resource "google_cloud_run_v2_service_iam_member" "public-services-are-unauthenticated" {
  for_each = var.ingress != "INGRESS_TRAFFIC_INTERNAL_ONLY" ? var.regions : {}

  // Ensure that the service exists before attempting to expose things publicly.
  depends_on = [google_cloud_run_v2_service.this]

  project  = var.project_id
  location = each.key
  name     = google_cloud_run_v2_service.this[each.key].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
