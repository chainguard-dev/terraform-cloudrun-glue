resource "random_string" "service-suffix" {
  length  = 4
  upper   = false
  special = false
}

// A dedicated service account for the trampoline service.
resource "google_service_account" "service" {
  project = var.project_id

  account_id   = "${var.name}-${random_string.service-suffix.result}"
  display_name = "Service account for GitHub events trampoline service"
}

module "webhook-secret" {
  source = "../secret"

  project_id = var.project_id
  name       = "${var.name}-webhook-secret"

  service-account  = google_service_account.service.email
  authorized-adder = var.secret_version_adder

  notification_channels = var.notification_channels
}

module "this" {
  source     = "../regional-go-service"
  project_id = var.project_id
  name       = var.name
  regions    = var.regions

  ingress = var.service-ingress

  deletion_protection = var.deletion_protection

  squad            = var.squad
  require_squad    = var.require_squad
  service_account = google_service_account.service.email
  containers = {
    "trampoline" = {
      source = {
        working_dir = path.module
        importpath  = "./cmd/trampoline"
      }
      ports = [{ container_port = 8080 }]
      env = [{
        name = "WEBHOOK_SECRET"
        value_source = {
          secret_key_ref = {
            secret  = module.webhook-secret.secret_id
            version = "latest"
          }
        }
      }]
      regional-env = [{
        name  = "EVENT_INGRESS_URI"
        value = { for k, v in module.trampoline-emits-events : k => v.uri }
      }]
    }
  }

  enable_profiler = var.enable_profiler

  notification_channels = var.notification_channels
}

// Authorize the trampoline service account to publish events on the broker.
module "trampoline-emits-events" {
  for_each = var.regions
  source   = "../authorize-private-service"

  project_id = var.project_id
  region     = each.key
  name       = var.ingress.name

  service-account = google_service_account.service.email
}

data "google_cloud_run_v2_service" "this" {
  for_each   = var.service-ingress == "INGRESS_TRAFFIC_ALL" ? var.regions : {}
  project    = var.project_id
  location   = each.key
  name       = var.name
  depends_on = [module.this]
}

output "public-urls" {
  description = "Map of region to public URL for the service, if service-ingress is INGRESS_TRAFFIC_ALL."
  value = var.service-ingress == "INGRESS_TRAFFIC_ALL" ? {
    for r, _ in var.regions : r => data.google_cloud_run_v2_service.this[r].uri
  } : {}
}

// READ THIS BEFORE YOU EDIT!!!
// These schemas are used to generate bigquery table names used by the recorder.
// If you are adding a schema you're fine to proceed. If you are changing the
// name of a schema, or removing a schema, terraform will try to delete the old
// schema. The recorders have a parameter `deletion_protection` enabled by default
// so terraform will fail to delete the schema.
//
// The proper process for deleting or modifying a schema is in this playbook
// https://eng.inky.wtf/docs/infra/playbooks/schema-names/
output "recorder-schemas" {
  value = {
    "dev.chainguard.github.pull_request" : {
      schema = file("${path.module}/schemas/pull_request.schema.json")
    }
    "dev.chainguard.github.workflow_run" : {
      schema = file("${path.module}/schemas/workflow_run.schema.json")
    }
    "dev.chainguard.github.issue_comment" : {
      schema = file("${path.module}/schemas/issue_comment.schema.json")
    }
    "dev.chainguard.github.issues" : {
      schema = file("${path.module}/schemas/issues.schema.json")
    }
    "dev.chainguard.github.check_run" : {
      schema = file("${path.module}/schemas/check_run.schema.json")
    }
    "dev.chainguard.github.check_suite" : {
      schema = file("${path.module}/schemas/check_suite.schema.json")
    }
    "dev.chainguard.github.projects_v2_item" : {
      schema = file("${path.module}/schemas/projects_v2_item.schema.json")
    }
  }
}
