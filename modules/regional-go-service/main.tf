terraform {
  required_providers {
    ko     = { source = "ko-build/ko" }
    cosign = { source = "chainguard-dev/cosign" }
  }
}

moved {
  from = google_project_iam_member.metrics-writer
  to   = module.this.google_project_iam_member.metrics-writer
}

moved {
  from = google_project_iam_member.trace-writer
  to   = module.this.google_project_iam_member.trace-writer
}

moved {
  from = google_project_iam_member.profiler-writer
  to   = module.this.google_project_iam_member.profiler-writer
}

// Build each of the application images from source.
resource "ko_build" "this" {
  for_each    = var.containers
  base_image  = each.value.source.base_image
  working_dir = each.value.source.working_dir
  importpath  = each.value.source.importpath
  env         = each.value.source.env
}

resource "cosign_sign" "this" {
  for_each = var.containers
  image    = ko_build.this[each.key].image_ref
  conflict = "REPLACE"
}

module "this" {
  source = "../regional-service"

  project_id = var.project_id
  name       = var.name
  regions    = var.regions
  ingress    = var.ingress
  egress     = var.egress

  deletion_protection = var.deletion_protection

  service_account = var.service_account
  containers = {
    for name, container in var.containers : name => {
      image         = cosign_sign.this[name].signed_ref
      args          = container.args
      ports         = container.ports
      resources     = container.resources
      env           = container.env
      regional-env  = container.regional-env
      volume_mounts = container.volume_mounts
    }
  }

  labels           = var.labels
  squad            = var.squad
  require_squad    = var.require_squad
  scaling          = var.scaling
  volumes          = var.volumes
  regional-volumes = var.regional-volumes
  enable_profiler  = var.enable_profiler

  request_timeout_seconds = var.request_timeout_seconds
  execution_environment   = var.execution_environment

  notification_channels = var.notification_channels
}

moved {
  from = google_cloud_run_v2_service.this
  to   = module.this.google_cloud_run_v2_service.this
}

moved {
  from = google_monitoring_alert_policy.anomalous-service-access
  to   = module.this.google_monitoring_alert_policy.anomalous-service-access
}

moved {
  from = google_monitoring_alert_policy.bad-rollout
  to   = module.this.google_monitoring_alert_policy.bad-rollout
}

moved {
  from = google_cloud_run_v2_service_iam_member.public-services-are-unauthenticated
  to   = module.this.google_cloud_run_v2_service_iam_member.public-services-are-unauthenticated
}
