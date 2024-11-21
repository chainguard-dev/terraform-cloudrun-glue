// Create the actual service account.
resource "google_service_account" "this" {
  project    = var.project_id
  account_id = var.name
}

locals {
  # Build up the "ref" portion of the principal match regular expression.
  refPart = (var.refspec == "*") ? (
    (var.audit_refspec != "") ? (
      var.audit_refspec
      ) : (
      "[^|]+"
    )
    ) : (
    (var.refspec == "pull_request") ? (
      "refs/pull/[0-9]+/merge"
      ) : (
      (var.refspec == "version_tags") ? (
        "refs/tags/v[0-9]+([.][0-9]+([.][0-9]+)?)?"
        ) : (
        # TODO(mattmoor): How can we "quote" this?
        var.refspec
      )
    )
  )
  # Build up the "workflow" portion of the principal match regular expression.
  workflowPart = "${var.repository}/${(var.workflow_ref == "*") ? (
    (var.audit_workflow_ref != "") ? (
      var.audit_workflow_ref
      ) : (
      "[^|]+"
    )
    ) : (
    # TODO(mattmoor): How can we "quote" this?
    var.workflow_ref
  )}"
  # TODO(mattmoor): How can we "quote" the `wif-pool` here?
  principalSubject = "^(principal://iam\\.googleapis\\.com/${var.wif-pool}/subject/${join("[|]", [
    local.workflowPart,
    local.refPart,
  ])})$"

  exact = "attribute.exact/${join("|", [
    var.repository,
    var.refspec,
    "${var.repository}/${var.workflow_ref}",
  ])}"

  exact-any-ref = "attribute.exactanyref/${join("|", [
    var.repository,
    "${var.repository}/${var.workflow_ref}",
  ])}"

  exact-any-ref-any-workflow = "attribute.exactanyrefanyworkflow/${var.repository}"

  exact-any-workflow = "attribute.exactanyworkflow/${join("|", [
    var.repository,
    var.refspec,
  ])}"

  pull-request = "attribute.pullrequest/${join("|", [
    var.repository,
    "true",
    "${var.repository}/${var.workflow_ref}",
  ])}"

  pull-request-any-workflow = "attribute.pullrequestanyworkflow/${join("|", [
    var.repository,
    "true",
  ])}"

  version-tags = "attribute.versiontags/${join("|", [
    var.repository,
    "true",
    "${var.repository}/${var.workflow_ref}",
  ])}"

  version-tags-any-workflow = "attribute.versiontagsanyworkflow/${join("|", [
    var.repository,
    "true",
  ])}"

  attribute-match = var.refspec == "*" ? (
    var.workflow_ref == "*" ? (
      local.exact-any-ref-any-workflow
      ) : (
      local.exact-any-ref
    )
    ) : (
    var.refspec == "pull_request" ? (
      var.workflow_ref == "*" ? (
        local.pull-request-any-workflow
        ) : (
        local.pull-request
      )
      ) : (
      var.refspec == "version_tags" ? (
        var.workflow_ref == "*" ? (
          local.version-tags-any-workflow
          ) : (
          local.version-tags
        )
        ) : (
        var.workflow_ref == "*" ? (
          local.exact-any-workflow
          ) : (
          local.exact
        )
      )
    )
  )
}

// Create the IAM binding allowing workflows to impersonate the service account.
resource "google_service_account_iam_binding" "allow-impersonation" {
  service_account_id = google_service_account.this.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${var.wif-pool}/${local.attribute-match}",
  ]

  lifecycle {
    precondition {
      condition     = var.audit_workflow_ref == "" || var.workflow_ref == "*"
      error_message = "audit_workflow_ref may only be specified when workflow_ref is '*'"
    }
    precondition {
      condition     = var.audit_refspec == "" || var.refspec == "*"
      error_message = "audit_refspec may only be specified when refspec is '*'"
    }
  }
}

// Create an auditing policy to ensure that tokens are only issued for identities
// matching our expectations.
module "audit-usage" {
  count = length(var.notification_channels) > 0 ? 1 : 0

  source = "../audit-serviceaccount"

  project_id      = var.project_id
  service-account = google_service_account.this.email

  allowed_principal_regex = local.principalSubject
  notification_channels   = var.notification_channels
}
