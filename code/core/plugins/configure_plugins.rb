#
# Top-level handler function for dealing with Vagrant Plugins.
#
def configure_plugins(
  source_file = "#{PLUGINS_CONFIG_DIR}/defaults.yaml"
)

  if File.file?(source_file)
    plugin_settings = lookup_values_yaml(YAML::load(File.read(source_file)), ['default_settings', 'vagrant', 'plugins'])
    return false unless plugin_settings
  else
    handle_message("unable to load plugins configuration file [#{source_file}].")
    return
  end

  configure_plugins_state(plugin_settings, source_file)

  plugins_code_load(plugin_settings)

end