#
# Configure the desired state of Vagrant Plugins.
#
def configure_plugins_state(
  plugin_settings = nil,
  source_file = nil,
  install_state_default = 'present',
  install_states = [
    'ignore',
    'installed',
    'uninstalled'
  ],
  manage_plugins_state_default = true,
  version_default = 'latest'
)

  managed_plugins = lookup_values_yaml(plugin_settings, ['managed_plugins'])

  return false unless managed_plugins

  manage_plugins_state = [
    lookup_values_yaml(plugin_settings, ['defaults', 'manage_plugins_state']),
    manage_plugins_state_default
  ].find { |i| !i.nil? }
  validate_value(manage_plugins_state)

  return unless manage_plugins_state

  plugins_managed = []

  managed_plugins.each do |plugin_name, plugin_info|

    exit_with_message("plugin [#{plugin_name}] defined more than once in [#{source_file}].") if plugins_managed.include?(plugin_name)

    plugins_managed.push(plugin_name)

    # Reserve for future as we may wish to error if a plugin is defined more than once across plugin files.
    $plugins_managed_state.push(plugin_name) unless $plugins_managed_state.include?(plugin_name)

    install_state = [
      lookup_values_yaml(plugin_info, ['install_state']),
      lookup_values_yaml(plugin_settings, ['defaults', 'install_state']),
      install_state_default
    ].find { |i| !i.nil? }
    validate_value(install_state, install_states)

    if !Vagrant.has_plugin?(plugin_name) and install_state == 'installed'

      version = [
        lookup_values_yaml(plugin_info, ['version']),
        version_default
      ].find { |i| !i.nil? }

      if version == 'latest'
        version = ''
      else
        version = "--plugin-version #{version}"
      end

      system_command = Thread.new do
        system("vagrant plugin install #{version} #{plugin_name}")
      end

      system_command.join

    elsif Vagrant.has_plugin?(plugin_name) and install_state == 'uninstalled'

      system_command = Thread.new do
        system("vagrant plugin uninstall #{plugin_name}")
      end

      system_command.join

    elsif install_states.include?(install_state)
      # No other cases require actions but this prevents error failthrough
    else
      exit_with_message("plugin [#{plugin_name}] install_state [#{install_state}] value unsupported.")
    end
  end
end