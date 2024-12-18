// Create a global network in which to place our resources.
resource "google_compute_network" "this" {
  name                            = var.name
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  project                         = var.project_id
  delete_default_routes_on_create = true
}

// Allow private Google access from the VPC.
resource "google_compute_route" "private-google-access" {
  name    = var.name
  network = google_compute_network.this.name

  # https://cloud.google.com/vpc/docs/configure-private-google-access-hybrid#config
  dest_range       = "199.36.153.8/30"
  next_hop_gateway = "default-internet-gateway"
}

moved {
  from = google_compute_route.egress-inet
  to   = google_compute_route.private-google-access
}

// Create regional subnets in each of the specified regions,
// which we will use to operate Cloud Run services.
resource "google_compute_subnetwork" "regional" {
  for_each = {
    for region in var.regions : region => index(var.regions, region)
  }

  name = "${var.name}-${each.key}"

  // This is needed in order to interact with Google APIs like Pub/Sub.
  private_ip_google_access = true

  network       = google_compute_network.this.id
  region        = each.key
  ip_cidr_range = cidrsubnet(var.cidr, 8, var.netnum_offset + each.value)

  log_config {
    aggregation_interval = "INTERVAL_15_MIN"
    flow_sampling        = 1.0
    metadata             = "INCLUDE_ALL_METADATA"
  }
}
