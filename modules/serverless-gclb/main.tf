terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.79"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 4.79"
    }
  }
}

// Create the IP address for our LB to serve on.
resource "google_compute_global_address" "this" {
  project = var.project_id
  name    = var.name
}

// Create A records for each of our public service hostnames.
resource "google_dns_record_set" "public-service" {
  for_each = var.public-services

  project      = var.project_id
  name         = "${each.key}."
  managed_zone = var.dns_zone
  type         = "A"
  ttl          = 60

  rrdatas = [google_compute_global_address.this.address]
}

// Provision a managed SSL certificate for each of our public services.
resource "google_compute_managed_ssl_certificate" "public-service" {
  for_each = var.public-services

  name = each.value.name

  managed {
    domains = [google_dns_record_set.public-service[each.key].name]
  }
}

// Create the cross-product of public services and regions so we can for_each over it.
locals {
  regional-backends = merge([
    for svcinfo in values(var.public-services) : merge([
      for region in var.regions : {
        "${svcinfo.name}-${region}" : {
          name     = svcinfo.name
          region   = region
          disabled = svcinfo.disabled
        }
      }
    ]...)
  ]...)
}

// Create a network endpoint group for each service in each region.
resource "google_compute_region_network_endpoint_group" "regional-backends" {
  for_each = local.regional-backends

  name                  = each.value.name
  network_endpoint_type = "SERVERLESS"
  region                = each.value.region
  cloud_run {
    service = each.value.name
  }
}

// Create a backend service for each public service with a backend in each region.
resource "google_compute_backend_service" "public-services" {
  for_each = var.public-services

  project = var.project_id
  name    = each.value.name

  // Create a backend for each region hosting this cloud run service.
  dynamic "backend" {
    for_each = toset(var.serving_regions)
    content {
      group = google_compute_region_network_endpoint_group.regional-backends["${each.value.name}-${backend.key}"]["id"]
    }
  }

  dynamic "iap" {
    for_each = var.iap[*]
    content {
      oauth2_client_id     = iap.value["oauth2_client_id"]
      oauth2_client_secret = iap.value["oauth2_client_secret"]
      enabled              = iap.value["enabled"]
    }
  }

  security_policy = var.security-policy
}

// Create a URL map that routes each hostname to the appropriate backend service.
resource "google_compute_url_map" "public-service" {
  project = var.project_id
  name    = var.name

  default_url_redirect {
    host_redirect = "chainguard.dev"
    strip_query   = true
  }

  // For each of the public services create a host rule.
  dynamic "host_rule" {
    for_each = { for k, v in var.public-services : k => v if !v.disabled }
    content {
      hosts        = [host_rule.key]
      path_matcher = host_rule.value.name
    }
  }

  // For each of the public services create an empty path matcher
  // that routes to its backend service.
  dynamic "path_matcher" {
    for_each = { for k, v in var.public-services : k => v if !v.disabled }
    content {
      name            = path_matcher.value.name
      default_service = google_compute_backend_service.public-services[path_matcher.key].id
    }
  }
}

// Create an HTTPS proxy for our URL map.
resource "google_compute_target_https_proxy" "public-service" {
  project = var.project_id
  name    = var.name
  url_map = google_compute_url_map.public-service.id

  ssl_certificates = [for domain, cert in google_compute_managed_ssl_certificate.public-service : cert.id if !var.public-services[domain].disabled]
}

// Attach the HTTPS proxy to the global IP address via a forwarding rule.
resource "google_compute_global_forwarding_rule" "this" {
  project               = var.project_id
  name                  = var.name
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = 443
  ip_address            = google_compute_global_address.this.id
  target                = google_compute_target_https_proxy.public-service.id
}

// What identity is deploying this?
data "google_client_openid_userinfo" "me" {}

locals {
  authorized-accounts = [
    # CI robot
    data.google_client_openid_userinfo.me.email,
  ]
  audited-resources = concat(
    [for _, v in google_dns_record_set.public-service : v.id],
    [for _, v in google_compute_managed_ssl_certificate.public-service : v.id],
    [for _, v in google_compute_backend_service.public-services : v.id],
    [for _, v in google_compute_region_network_endpoint_group.regional-backends : v.id],
    [google_compute_url_map.public-service.id,
      google_compute_target_https_proxy.public-service.id,
      google_compute_global_forwarding_rule.this.id,
    ],
  )
}

resource "google_monitoring_alert_policy" "abnormal-gclb-access" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  # In the absence of data, incident will auto-close after an hour
  alert_strategy {
    auto_close = "3600s"

    notification_rate_limit {
      period = "3600s" // re-alert hourly if condition still valid.
    }
  }

  display_name = "Abnormal GCLB Access"
  combiner     = "OR"

  conditions {
    display_name = "Anomaly detected"

    condition_matched_log {
      filter = <<EOT
      logName=(
          "projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
       OR "projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Fdata_access"
      )

      protoPayload.resourceName=("${join("\" OR \"", local.audited-resources)}")
      -- Allows robots
      -protoPayload.authenticationInfo.principalEmail=("${join("\" OR \"", local.authorized-accounts)}")
      -- Allow read-only operations
      -protoPayload.methodName=~(".*\.get.*" OR ".*\.list.*" OR ".*\.aggregatedList")
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
