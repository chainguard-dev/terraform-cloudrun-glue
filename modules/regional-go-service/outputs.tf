output "names" {
  value = module.this.names
}

output "locations" {
  value = module.this.locations
}

output "uris" {
  value = module.this.uris
}

output "uris" {
  value = {
    for k, v in google_cloud_run_v2_service.this : k => v.uri
  }
}
