data "google_storage_bucket" "bucket" { name = var.bucket }

locals {
  lowercase = lower(data.google_storage_bucket.bucket.location)
  region = lookup({
    "us" : "us-central1",
    "eu" : "europe-west1",
    "asia" : "asia-east1",
  }, local.lowercase, local.lowercase)
}

resource "random_string" "service-suffix" {
  length  = 4
  upper   = false
  special = false
}

// A dedicated service account for the trampoline service.
resource "google_service_account" "service" {
  project = var.project_id

  account_id   = "${var.name}-${random_string.service-suffix.result}"
  display_name = "Service account for ${var.bucket} trampoline service"
}

resource "random_string" "delivery-suffix" {
  length  = 4
  upper   = false
  special = false
}

// A dedicated service account for this subscription.
resource "google_service_account" "delivery" {
  project = var.project_id

  account_id   = "${var.name}-${random_string.delivery-suffix.result}"
  display_name = "Delivery account for ${var.bucket} events"
}

// Lookup the identity of the pubsub service agent.
resource "google_project_service_identity" "pubsub" {
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"
}

// Authorize Pub/Sub to impersonate the delivery service account to authorize
// deliveries using this service account.
// NOTE: we use binding vs. member because we expect nothing but pubsub to be
// able to assume this identity.
resource "google_service_account_iam_binding" "allow-pubsub-to-mint-tokens" {
  service_account_id = google_service_account.delivery.name

  role    = "roles/iam.serviceAccountTokenCreator"
  members = ["serviceAccount:${google_project_service_identity.pubsub.email}"]
}

module "audit-delivery-serviceaccount" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  source = "../audit-serviceaccount"

  project_id      = var.project_id
  service-account = google_service_account.delivery.email

  # The absence of authorized identities here means that
  # nothing is authorized to act as this service account.
  # Note: Cloud Pub/Sub's usage doesn't show up in the
  # audit logs.

  notification_channels = var.notification_channels
}

module "this" {
  source     = "../regional-go-service"
  project_id = var.project_id
  name       = var.name
  regions = {
    (local.region) : var.regions[local.region]
  }

  squad           = var.squad
  require_squad   = var.require_squad
  service_account = google_service_account.service.email
  containers = {
    "trampoline" = {
      source = {
        working_dir = path.module
        importpath  = "./cmd/trampoline"
      }
      ports = [{ container_port = 8080 }]
      env = [{
        name  = "INGRESS_URI"
        value = module.trampoline-emits-events.uri
      }]
    }
  }

  enable_profiler = var.enable_profiler

  notification_channels = var.notification_channels
}

// Authorize the Pub/Sub topic to deliver events to the service.
module "authorize-delivery" {
  source = "../authorize-private-service"

  project_id = var.project_id
  region     = local.region
  name       = var.name

  service-account = google_service_account.delivery.email
}

resource "google_pubsub_topic" "dead-letter" {
  name = "${var.name}-dlq-${random_string.delivery-suffix.result}"

  message_storage_policy {
    allowed_persistence_regions = [local.region]
  }
}

// Create a subscription to the dead-letter topic so dead-lettered messages
// are retained. This also allows us to alerts based on better metrics
// like the age or count of dead-lettered messages.
resource "google_pubsub_subscription" "dead-letter-pull-sub" {
  name                       = google_pubsub_topic.dead-letter.name
  topic                      = google_pubsub_topic.dead-letter.name
  message_retention_duration = "86400s"

  expiration_policy {
    ttl = "86400s"
  }

  enable_message_ordering = true
}

// Grant the pubsub service account the ability to send to the dead-letter topic.
resource "google_pubsub_topic_iam_binding" "allow-pubsub-to-send-to-dead-letter" {
  topic = google_pubsub_topic.dead-letter.name

  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${google_project_service_identity.pubsub.email}"]
}

// Configure the subscription to deliver the events matching our filter to this service
// using the above identity to authorize the delivery..
resource "google_pubsub_subscription" "this" {
  depends_on = [module.this]

  name  = "${var.name}-${random_string.delivery-suffix.result}"
  topic = google_pubsub_topic.internal.id

  // TODO: Tune this and/or make it configurable?
  ack_deadline_seconds = 300

  push_config {
    push_endpoint = module.authorize-delivery.uri

    // Authenticate requests to this service using tokens minted
    // from the given service account.
    oidc_token {
      service_account_email = google_service_account.delivery.email
    }

    // Make the body of the push notification the raw Pub/Sub message.
    // Include the Pub/Sub message attributes as HTTP headers.
    // This aligns the shape of the notification with the "binary"
    // Cloud Event delivery form.
    // See: https://cloud.google.com/pubsub/docs/payload-unwrapping
    no_wrapper {
      write_metadata = true
    }
  }

  expiration_policy {
    ttl = "" // This does not expire.
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead-letter.id
    max_delivery_attempts = var.max_delivery_attempts
  }
}

// Grant the pubsub service account the ability to Acknowledge messages on this "this" subscription.
resource "google_pubsub_subscription_iam_binding" "allow-pubsub-to-ack" {
  subscription = google_pubsub_subscription.this.name

  role    = "roles/pubsub.subscriber"
  members = ["serviceAccount:${google_project_service_identity.pubsub.email}"]
}

// Lookup the GCS service account.
data "google_storage_project_service_account" "gcs_account" {}

// Allow the GCS service account to publish to the internal topic.
resource "google_pubsub_topic_iam_binding" "binding" {
  topic   = google_pubsub_topic.internal.id
  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"]
}

// Creage the topic to receive the GCS events.
resource "google_pubsub_topic" "internal" {
  name = "${var.name}-internal"

  // TODO: Tune this and/or make it configurable?
  message_retention_duration = "600s"

  message_storage_policy {
    allowed_persistence_regions = [local.region]
  }
}

// Create a notification to the topic.
resource "google_storage_notification" "notification" {
  bucket         = var.bucket
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.internal.id
  event_types    = var.gcs_event_types
  depends_on     = [google_pubsub_topic_iam_binding.binding]
}

// Authorize the trampoline service account to publish events.
module "trampoline-emits-events" {
  source = "../authorize-private-service"

  project_id = var.project_id
  region     = local.region
  name       = var.ingress.name

  service-account = google_service_account.service.email
}
