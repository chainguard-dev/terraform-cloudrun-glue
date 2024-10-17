variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "location" {
  default     = "US"
  description = "The location to create the BigQuery dataset in, and in which to run the data transfer jobs from GCS."
}

variable "provisioner" {
  type        = string
  description = "The identity as which this module will be applied (so it may be granted permission to 'act as' the DTS service account).  This should be in the form expected by an IAM subject (e.g. user:sally@example.com)"
}

variable "retention-period" {
  type        = number
  description = "The number of days to retain data in BigQuery."
}

variable "deletion_protection" {
  default     = true
  description = "Whether to enable deletion protection on data resources."
}

variable "regions" {
  description = "A map from region names to a network and subnetwork.  A recorder service and cloud storage bucket (into which the service writes events) will be created in each region."
  type = map(object({
    network = string
    subnet  = string
  }))
}

variable "broker" {
  type        = map(string)
  description = "A map from each of the input region names to the name of the Broker topic in that region."
}

variable "notification_channels" {
  description = "List of notification channels to alert (for service-level issues)."
  type        = list(string)
}

variable "types" {
  description = "A map from cloudevent types to the BigQuery schema associated with them, as well as an alert threshold and a list of notification channels (for subscription-level issues)."

  type = map(object({
    schema                = string
    alert_threshold       = optional(number, 50000)
    notification_channels = optional(list(string), [])
    partition_field       = optional(string)
  }))
}

variable "method" { # todo (jr) add bq method that writes events directly to bq https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription#example-usage---pubsub-subscription-push-bq
  type        = string
  description = "The method used to transfer events (e.g., trigger, gcs)."
  default     = "trigger"
  validation {
    condition     = contains(["trigger", "gcs"], var.method)
    error_message = "The environment must be one of: trigger or gcs."
  }
}

variable "max_delivery_attempts" {
  description = "The maximum number of delivery attempts for any event."
  type        = number
  default     = 5
}

variable "ack_deadline_seconds" {
  description = "The number of seconds to acknowledge a message before it is redelivered."
  type        = number
  default     = 300
}

variable "minimum_backoff" {
  description = "The minimum delay between consecutive deliveries of a given message."
  type        = number
  default     = 10
}

variable "maximum_backoff" {
  description = "The maximum delay between consecutive deliveries of a given message."
  type        = number
  default     = 600
}

variable "cloud_storage_config_max_bytes" {
  description = "The maximum bytes that can be written to a Cloud Storage file before a new file is created. Min 1 KB, max 10 GiB."
  type        = number
  default     = 1000000000 // default 1 GB
}

variable "cloud_storage_config_max_duration" {
  description = "The maximum duration that can elapse before a new Cloud Storage file is created. Min 1 minute, max 10 minutes, default 5 minutes."
  type        = number
  default     = 300 // default 5 minutes
}

variable "ignore_unknown_values" {
  description = "Whether to ignore unknown values in the data, when transferring data to BigQuery."
  type        = bool
  default     = false
}

variable "limits" {
  description = "Resource limits for the regional go service."
  type = object({
    cpu    = string
    memory = string
  })
  default = null
}

variable "scaling" {
  description = "The scaling configuration for the service."
  type = object({
    min_instances                    = optional(number, 0)
    max_instances                    = optional(number, 100)
    max_instance_request_concurrency = optional(number)
  })
  default = {}
}

variable "enable_profiler" {
  type        = bool
  default     = false
  description = "Enable cloud profiler."
}

variable "split_triggers" {
  description = "Opt-in flag to split into per-trigger dashboards. Helpful when hitting widget limits"
  type        = bool
  default     = false
}

variable "flush_interval" {
  description = "Flush interval for logrotate, as a duration string."
  type        = string
  default     = "3m"
}
