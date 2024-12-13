variable "endpoint" {}

data "http" "endpoint" {
  url    = var.endpoint
  method = "GET"
}
