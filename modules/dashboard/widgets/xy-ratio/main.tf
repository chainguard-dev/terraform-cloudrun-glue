variable "title" { type = string }
variable "legend" { default = "" }
variable "numerator_group_by_fields" { default = [] }
variable "denominator_group_by_fields" { default = [] }
variable "numerator_filter" { type = list(string) }
variable "denominator_filter" { type = list(string) }
variable "plot_type" { default = "LINE" }
variable "alignment_period" { default = "60s" }
variable "numerator_align" { default = "ALIGN_RATE" }
variable "numerator_reduce" { default = "REDUCE_SUM" }
variable "denominator_align" { default = "ALIGN_RATE" }
variable "denominator_reduce" { default = "REDUCE_SUM" }
variable "thresholds" { default = [] }

locals {
  default_align  = "ALIGN_RATE"
  default_reduce = "REDUCE_NONE"
}

// https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#XyChart
output "widget" {
  value = {
    title = var.title
    xyChart = {
      chartOptions = { mode = "COLOR" }
      dataSets = [{
        minAlignmentPeriod = var.alignment_period
        plotType           = var.plot_type
        targetAxis         = "Y1"
        legendTemplate     = var.legend
        timeSeriesQuery = {
          // https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#timeseriesfilterratio
          timeSeriesFilterRatio = {
            numerator = {
              filter = join("\n", var.numerator_filter)
              aggregation = {
                alignmentPeriod    = var.alignment_period
                perSeriesAligner   = var.numerator_align == local.default_align ? null : var.numerator_align
                crossSeriesReducer = var.numerator_reduce == local.default_reduce ? null : var.numerator_reduce
                groupByFields      = length(var.numerator_group_by_fields) == 0 ? null : var.numerator_group_by_fields
              }
            }
            denominator = {
              filter = join("\n", var.denominator_filter)
              aggregation = {
                alignmentPeriod    = var.alignment_period
                perSeriesAligner   = var.denominator_align == local.default_align ? null : var.denominator_align
                crossSeriesReducer = var.denominator_reduce == local.default_reduce ? null : var.denominator_reduce
                groupByFields      = length(var.denominator_group_by_fields)
              }
            }
          }
        }
      }]
      thresholds = var.thresholds
      yAxis = {
        label = "y1Axis"
        scale = "LINEAR"
      }
    }
  }
}
