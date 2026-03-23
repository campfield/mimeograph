#
# configure_plugins.rb
#
# Manages Vagrant plugin ensure state from config/plugins/plugins.yaml.
#
# Expected YAML structure:
#
#   plugins:
#     vagrant-vbguest:
#       ensure: present   # present | absent | ignore
#       version: '0.29.0'  # optional; omit for latest
#     vagrant-cachier:
#       ensure: absent
#
# Any plugin entry with no keys (or just a name) defaults to ensure: present.
#
# Valid values for ensure: 'present' | 'absent' | 'ignore'
#   present - ensure the plugin is installed; install if missing (default)
#   absent  - ensure the plugin is removed; uninstall if present
#   ignore  - take no action regardless of current installed state
#
def configure_plugins(source_file)
  unless File.file?(source_file)
    handle_message("plugins configuration file [#{source_file}] not found - skipping plugin management.", 'WARNING')
    return
  end

  yaml    = YAML.safe_load(File.read(source_file))
  plugins = lookup_values_yaml(yaml, ['plugins'])

  unless plugins
    handle_message('No plugins key found in plugins.yaml - skipping plugin management.', 'WARNING')
    return
  end

  valid_states = %w[present absent ignore]

  plugins.each do |plugin_name, plugin_info|
    plugin_info ||= {}

    ensure_state = (plugin_info['ensure'] || 'present').to_s
    validate_value(ensure_state, valid_states)

    next if ensure_state == 'ignore'

    installed = Vagrant.has_plugin?(plugin_name)

    if !installed && ensure_state == 'present'
      version_flag = plugin_info['version'] ? "--plugin-version #{plugin_info['version']}" : ''
      handle_message("installing plugin [#{plugin_name}]#{version_flag.empty? ? '' : " version [#{plugin_info['version']}]"}.")
      unless system("vagrant plugin install #{plugin_name} #{version_flag}".strip)
        exit_with_message("failed to install plugin [#{plugin_name}].")
      end

    elsif installed && ensure_state == 'absent'
      handle_message("uninstalling plugin [#{plugin_name}].")
      unless system("vagrant plugin uninstall #{plugin_name}")
        exit_with_message("failed to uninstall plugin [#{plugin_name}].")
      end
    end
  end
end
