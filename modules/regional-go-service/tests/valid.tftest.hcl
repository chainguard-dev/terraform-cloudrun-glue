variables {
  # set with -var 'project=your-project-id'
  # project_id = ""
}

run "setup" {
  module {
    source = "./tests/setup/"
  }
}

run "create" {
  variables {
    name = run.setup.name
    project_id = var.project_id
    regions = {
      "us-central1" = {
        network = "default"
        subnet = "default"
      }
    }

    service_account = run.setup.email

    ingress = "INGRESS_TRAFFIC_ALL"
    egress = "ALL_TRAFFIC"

    containers = {
      "hello" = {
        source = {
          working_dir = "./tests"
          importpath = "./cmd/"
        }
        ports = [{ container_port = 8080 }]
      }
    }

    notification_channels = []
  }

  assert {
    condition = google_cloud_run_v2_service.this["us-central1"].terminal_condition[0].type == "Ready"
    error_message = "Service not ready"
  }
}

run "validate" {
  module {
    source = "./tests/asserts/"
  }

  variables {
    endpoint = "${run.create.uris["us-central1"]}/bar"
  }

  assert {
    condition = data.http.endpoint.status_code == 200
    error_message = "Website responded with HTTP status ${data.http.endpoint.status_code}"
  }
}
