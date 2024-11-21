variable "project_id" {
  type = string
}

variable "name" {
  description = "The name to give the secret."
  type        = string
}

variable "data" {
  description = "The data to place in the secret."
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
