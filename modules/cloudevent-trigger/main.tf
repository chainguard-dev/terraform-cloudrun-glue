resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

// A dedicated service account for this subscription.
resource "google_service_account" "this" {
  project = var.project_id

  account_id   = "${var.name}-${random_string.suffix.result}"
  display_name = "Delivery account for ${var.private-service.name} in ${var.private-service.region}."
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
  service_account_id = google_service_account.this.name

  role    = "roles/iam.serviceAccountTokenCreator"
  members = ["serviceAccount:${google_project_service_identity.pubsub.email}"]
}

module "audit-trigger-serviceaccount" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  source = "../audit-serviceaccount"

  project_id      = var.project_id
  service-account = google_service_account.this.email

  # The absence of authorized identities here means that
  # nothing is authorized to act as this service account.
  # Note: Cloud Pub/Sub's usage doesn't show up in the
  # audit logs.

  notification_channels = var.notification_channels
}

// Authorize this service account to invoke the private service receiving
// events from this trigger.
module "authorize-delivery" {
  source = "../authorize-private-service"

  project_id = var.project_id
  region     = var.private-service.region
  name       = var.private-service.name

  service-account = google_service_account.this.email
}

locals {
  // See https://cloud.google.com/pubsub/docs/subscription-message-filter#filtering_syntax
  filter-elements = concat(
    [for key, value in var.filter : "attributes.ce-${key}=\"${value}\""],
    [for key, value in var.filter_prefix : "hasPrefix(attributes.ce-${key}, \"${value}\")"],
    [for key in var.filter_has_attributes : "attributes:ce-${key}"],
    [for key in var.filter_not_has_attributes : "NOT attributes:ce-${key}"],
  )
}

resource "google_pubsub_topic" "dead-letter" {
  name = "${var.name}-dlq-${random_string.suffix.result}"

  message_storage_policy {
    allowed_persistence_regions = [var.private-service.region]
  }
}

// Grant the pubsub service account the ability to send to the dead-letter topic.
resource "google_pubsub_topic_iam_binding" "allow-pubsub-to-send-to-dead-letter" {
  topic = google_pubsub_topic.dead-letter.name

  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${google_project_service_identity.pubsub.email}"]
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

// Configure the subscription to deliver the events matching our filter to this service
// using the above identity to authorize the delivery..
resource "google_pubsub_subscription" "this" {
  name  = "${var.name}-${random_string.suffix.result}"
  topic = var.broker

  ack_deadline_seconds = var.ack_deadline_seconds

  filter = var.raw_filter == "" ? join(" AND ", local.filter-elements) : var.raw_filter

  push_config {
    push_endpoint = module.authorize-delivery.uri

    // Authenticate requests to this service using tokens minted
    // from the given service account.
    oidc_token {
      service_account_email = google_service_account.this.email
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

  retry_policy {
    minimum_backoff = "${var.minimum_backoff}s"
    maximum_backoff = "${var.maximum_backoff}s"
  }
}

// Grant the pubsub service account the ability to Acknowledge messages on this "this" subscription.
resource "google_pubsub_subscription_iam_binding" "allow-pubsub-to-ack" {
  subscription = google_pubsub_subscription.this.name

  role    = "roles/pubsub.subscriber"
  members = ["serviceAccount:${google_project_service_identity.pubsub.email}"]
}
