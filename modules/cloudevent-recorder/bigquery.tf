// The BigQuery dataset that will hold the recorded cloudevents.
resource "google_bigquery_dataset" "this" {
  project    = var.project_id
  dataset_id = "cloudevents_${replace(var.name, "-", "_")}"
  location   = var.location

  default_partition_expiration_ms = (var.retention-period) * 24 * 60 * 60 * 1000
}

// A BigQuery table for each of the cloudevent types with the specified
// schema for that type.
resource "google_bigquery_table" "types" {
  for_each = var.types

  project    = var.project_id
  dataset_id = google_bigquery_dataset.this.dataset_id
  table_id   = replace(each.key, ".", "_")
  schema     = each.value.schema

  require_partition_filter = false

  time_partitioning {
    type  = "DAY"
    field = each.value.partition_field

    expiration_ms = (var.retention-period) * 24 * 60 * 60 * 1000
  }

  deletion_protection = var.deletion_protection
}

// Create an identity that will be used to run the BQ DTS job,
// which we will grant the necessary permissions to.
resource "google_service_account" "import-identity" {
  project      = var.project_id
  account_id   = "${var.name}-import"
  display_name = "BigQuery import identity"
}

// Only the DTS import identity should ever write to our dataset's tables.
resource "google_bigquery_table_iam_binding" "import-writes-to-tables" {
  for_each = var.types

  project    = var.project_id
  dataset_id = google_bigquery_dataset.this.dataset_id
  table_id   = google_bigquery_table.types[each.key].table_id
  role       = "roles/bigquery.admin"
  members    = ["serviceAccount:${google_service_account.import-identity.email}"]
}

// The BigQuery Data Transfer Service jobs are the only things that should
// be reading from these buckets.
resource "google_storage_bucket_iam_binding" "import-reads-from-gcs-buckets" {
  for_each = var.regions

  bucket  = google_storage_bucket.recorder[each.key].name
  role    = "roles/storage.objectViewer"
  members = ["serviceAccount:${google_service_account.import-identity.email}"]
}

// The BQ DTS service account for this project is the only identity that should
// be able to create tokens as the identity we are assigning to the DTS job.
resource "google_service_account_iam_binding" "bq-dts-assumes-import-identity" {
  service_account_id = google_service_account.import-identity.name
  role               = "roles/iam.serviceAccountShortTermTokenMinter"
  members            = ["serviceAccount:service-${data.google_project.project.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"]
}

// The only identity that should be authorized to "act as" the import identity
// is the release automation that applies these terraform modules.
resource "google_service_account_iam_binding" "provisioner-acts-as-import-identity" {
  service_account_id = google_service_account.import-identity.name
  role               = "roles/iam.serviceAccountUser"
  members            = [var.provisioner]
}

module "audit-import-serviceaccount" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  source = "../audit-serviceaccount"

  project_id      = var.project_id
  service-account = google_service_account.import-identity.email

  # The absence of authorized identities here means that
  # nothing is authorized to act as this service account.
  # Note: BigQuery DTS's usage doesn't show up in the
  # audit logs.

  notification_channels = var.notification_channels
}

// Create a BQ DTS job for each of the regions x types pulling from the appropriate buckets and paths.
resource "google_bigquery_data_transfer_config" "import-job" {
  for_each = local.regional-types

  depends_on = [google_service_account_iam_binding.provisioner-acts-as-import-identity]

  project              = var.project_id
  display_name         = "${var.name}-${each.key}"
  location             = google_bigquery_dataset.this.location // These must be colocated
  service_account_name = google_service_account.import-identity.email
  disabled             = false

  data_source_id         = "google_cloud_storage"
  schedule               = "every 15 minutes"
  destination_dataset_id = google_bigquery_dataset.this.dataset_id

  // TODO(mattmoor): Bring back pubsub notification.
  # notification_pubsub_topic = google_pubsub_topic.bq_notification[each.key].id
  params = {
    data_path_template              = "gs://${google_storage_bucket.recorder[each.value.region].name}/${each.value.type}/*"
    destination_table_name_template = google_bigquery_table.types[each.value.type].table_id
    file_format                     = "JSON"
    max_bad_records                 = 0
    delete_source_files             = false
    ignore_unknown_values           = var.ignore_unknown_values
  }
}

// Alert when no successful run in 30min, it should be successful every 15min
resource "google_monitoring_alert_policy" "bq_dts" {
  for_each = var.types

  // Close after 7 days
  alert_strategy {
    auto_close = "604800s"
  }

  combiner = "OR"

  dynamic "conditions" {
    for_each = var.regions

    content {
      condition_absent {
        aggregations {
          alignment_period     = "1800s"
          cross_series_reducer = "REDUCE_MAX"
          per_series_aligner   = "ALIGN_MAX"
        }

        duration = "1800s"
        // config_id is the last value in the name, separated by '/'
        filter = <<EOT
        resource.type = "bigquery_dts_config"
        AND metric.type = "bigquerydatatransfer.googleapis.com/transfer_config/completed_runs"
        AND metric.labels.completion_state = "SUCCEEDED"
        AND metric.labels.run_cause = "AUTO_SCHEDULE"
        AND resource.labels.config_id = "${element(reverse(split("/", google_bigquery_data_transfer_config.import-job["${conditions.key}-${each.key}"].name)), 0)}"
        EOT

        trigger {
          count = "1"
        }
      }

      display_name = "BQ DTS Scheduled Success Runs for ${var.name} ${conditions.key}"
    }
  }

  display_name = "BQ DTS Scheduled Success Runs for ${var.name}"

  enabled = "true"
  project = var.project_id

  notification_channels = var.notification_channels
}
