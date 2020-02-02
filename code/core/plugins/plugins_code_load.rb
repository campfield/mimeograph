#
# Function for executing optional Plugin-specific code/settings as provided in individual Ruby files.
#  Present outside of the core/ code area.
def plugins_code_load(
  plugin_settings = nil,
  code_load_default = false
)

  return false unless plugin_settings

  managed_plugins = lookup_values_yaml(plugin_settings, ['managed_plugins'])

  return false unless managed_plugins

  managed_plugins.each do | plugin_name, plugin_info |

    t_plugin_name = plugin_name.downcase

    next unless Vagrant.has_plugin?(t_plugin_name)

    code_load = [
      lookup_values_yaml(plugin_info, ['code_load']),
      lookup_values_yaml(plugin_settings, ['defaults', 'code_load']),
      code_load_default
    ].find { |i| !i.nil? }
    validate_value(code_load)

    next unless code_load

    plugin_function_name = 'configure_plugin_' + t_plugin_name.gsub('-', '_')

    ruby_file = "#{PLUGINS_DIR}/#{t_plugin_name}/#{plugin_function_name}.rb"

    if File.file?(ruby_file)
      exit_with_message("plugin code load for [#{plugin_name}] failed.") unless load ruby_file
      exit_with_message("plugin code send for [#{plugin_name}] failed.") unless send(plugin_function_name, plugin_info)
    else
      handle_message("code_load setting for plugin [#{plugin_name}] is set to true but expected file [#{ruby_file}] was not found.", 'WARNING')
    end

  end
end
