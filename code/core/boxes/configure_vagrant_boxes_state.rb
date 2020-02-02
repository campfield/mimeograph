#
# Placeholder function for managing install state of particular boxes by name, source, and version.
#
def configure_vagrant_boxes_state(
  box_settings = nil,
  source_file = nil,
  install_state_default = 'present'
)

  managed_boxes = lookup_values_yaml(box_settings, ['managed_boxes'])

  return false unless managed_boxes

end