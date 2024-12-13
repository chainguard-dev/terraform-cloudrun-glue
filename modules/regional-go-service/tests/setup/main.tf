variable "project_id" {}

resource "random_string" "name" {
  numeric = false
  upper   = false
  special = false
  length  = 6
}

resource "google_service_account" "iam" {
  project = var.project_id

  account_id   = random_string.name.id
  display_name = "test-${random_string.name.id}"
  description  = "Dedicated service account for ${random_string.name.id}"
}

output "name" {
  value = random_string.name.id
}

output "email" {
  value = google_service_account.iam.email
}
