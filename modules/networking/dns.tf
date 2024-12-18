resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

// Create a special DNS zone attached to the network in which
// we will operate our services that reroutes *.run.app to records
// that we control.
resource "google_dns_managed_zone" "cloud-run-internal" {
  project     = var.project_id
  name        = "cloud-run-internal-${random_string.suffix.result}"
  dns_name    = "run.app."
  description = "This reroutes run.app requests to private.googleapis.com"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }
}

// Create a record for *.run.app that points to private.googleapis.com
resource "google_dns_record_set" "cloud-run-cname" {
  project      = var.project_id
  name         = "*.run.app."
  managed_zone = google_dns_managed_zone.cloud-run-internal.name
  type         = "CNAME"
  ttl          = 60

  rrdatas = ["private.googleapis.com."]
}

// Create a special DNS zone attached to the network in which
// we will operate our services that reroutes *.google.com
// that we control.
resource "google_dns_managed_zone" "private-google-com" {
  project     = var.project_id
  name        = "private-google-com-${random_string.suffix.result}"
  dns_name    = "google.com."
  description = "This reroutes google.com requests to private.googleapis.com"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }
}

// Create a record for *.google.com that points to private.googleapis.com
resource "google_dns_record_set" "private-google-com-cname" {
  project      = var.project_id
  name         = "*.google.com."
  managed_zone = google_dns_managed_zone.private-google-com.name
  type         = "CNAME"
  ttl          = 60

  rrdatas = ["private.googleapis.com."]
}

// Create a special DNS zone attached to the network in which
// we will operate our services that reroutes private.googleapis.com
// to records that we control.
resource "google_dns_managed_zone" "private-google-apis" {
  project     = var.project_id
  name        = "private-google-apis-${random_string.suffix.result}"
  dns_name    = "private.googleapis.com."
  description = "This maps DNS for private.googleapis.com"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }
}

// Create a record for private.googleapis.com that points to
// the documented internal IP addresses for the Google APIs.
resource "google_dns_record_set" "private-googleapis-a-record" {
  project      = var.project_id
  name         = "private.googleapis.com."
  managed_zone = google_dns_managed_zone.private-google-apis.name
  type         = "A"
  ttl          = 60

  // This IP range is documented here:
  // https://cloud.google.com/vpc/docs/configure-private-google-access-hybrid
  rrdatas = [for x in range(8, 12) : "199.36.153.${x}"]
}
