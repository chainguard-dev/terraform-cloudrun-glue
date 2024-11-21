variable "project_id" {
  type = string
}

variable "service-account" {
  description = "The email of the service account being audited."
  type        = string
}

variable "allowed_principals" {
  description = "The list of principals authorized to assume this identity."
  type        = list(string)
  default     = []
}

variable "allowed_principal_regex" {
  description = "A regular expression to match allowed principals."
  type        = string
  default     = ""
}

variable "notification_channels" {
  description = "The list of notification channels to alert when this policy fires."
  type        = list(string)
}
