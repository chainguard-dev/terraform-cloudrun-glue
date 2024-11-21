variable "sections" {}

module "width" { source = "../width" }

locals {
  // The maximum height of a tile in each section.
  max_heights = [for s in var.sections : max([for t in s : t.yPos + t.height]...)]

  // The sum of the maximum tile heights in all of the sections prior to this one.
  // Note: sum doesn't work on an empty list, so we concatenate with 0 for the base case.
  sum_heights = [for s in var.sections : sum(concat([0], slice(local.max_heights, 0, index(var.sections, s))))]

  // Rebase the yPos of each tile in each section to be relative to the top of
  // the section, which starts after the topmost tile of the preceding section.
  rebased = [for s in var.sections : [
    for t in s : {
      yPos   = t.yPos + local.sum_heights[index(var.sections, s)] != 0 ? t.yPos + local.sum_heights[index(var.sections, s)] : null
      xPos   = t.xPos != 0 ? t.xPos : null
      height = t.height
      width  = t.width
      widget = t.widget
    }]
  ]
}

output "tiles" {
  value = concat(local.rebased...)
}
