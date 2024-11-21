variable "project_id" {
  type = string
}

variable "name" {
  description = "The name to give the secret."
  type        = string
}

variable "authorized-adder" {
  description = "A member-style representation of the identity authorized to add new secret values (e.g. group:oncall@my-corp.dev)."
  type        = string
}

variable "service-account" {
  description = "The email of the service account that will access the secret."
  type        = string
}

variable "notification_channels" {
  description = "The channels to notify if the configuration data is improperly accessed."
  type        = list(string)
}

variable "create_placeholder_version" {
  description = "Whether to create a placeholder secret version to avoid bad reference on first deploy."
  type        = bool
  default     = false
}
