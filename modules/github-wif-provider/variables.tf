variable "project_id" {
  type = string
}

variable "name" {
  description = "The name to give the provider pool."
  type        = string
}

variable "notification_channels" {
  description = "The list of notification channels to alert when this policy fires."
  type        = list(string)
}
