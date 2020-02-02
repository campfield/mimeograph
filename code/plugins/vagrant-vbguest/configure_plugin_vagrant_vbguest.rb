#
# Plugin-specific code to handle / manipulate the vagrant-vbguest Plugin
#
def configure_plugin_vagrant_vbguest(
  plugin_info = nil,
  auto_update_default = false,
  no_remote_default = true,
  iso_path_default = nil
)

  Vagrant.configure(VAGRANT_VERSION) do |config|

    config.vbguest.auto_update = [
      validate_value(lookup_values_yaml(plugin_info, ['settings', 'auto_update'])),
      auto_update_default
    ].find { |i| !i.nil? }

    config.vbguest.no_remote = [
      validate_value(lookup_values_yaml(plugin_info, ['settings', 'no_remote'])),
      no_remote_default
    ].find { |i| !i.nil? }

    iso_path = [
      lookup_values_yaml(plugin_info, ['settings', 'iso_path']),
      iso_path_default
    ].find { |i| !i.nil? }
    config.vbguest.iso_path = iso_path if iso_path

  end
end
