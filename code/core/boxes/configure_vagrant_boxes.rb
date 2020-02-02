#
# Top-level handler function for dealing with Vagrant Boxes, the global catalog, etc.
#
def configure_vagrant_boxes(
  source_file = "#{BOXES_CONFIG_DIR}/defaults.yaml"
)

  if File.file?(source_file)
    box_settings = lookup_values_yaml(YAML::load(File.read(source_file)), ['default_settings', 'vagrant', 'boxes'])
    return false unless box_settings
  else
    handle_message("unable to load plugins configuration file [#{source_file}].")
    return
  end

  configure_vagrant_boxes_state(box_settings, source_file)

end