#
# Plugin-specific code to handle / manipulate the vagrant-cachier Plugin
#
def configure_plugin_vagrant_cachier(
  auto_detect_default = true,
  cache_scope_default = 'box',
  plugin_info = nil,
  synced_folder_opts_default = nil
)

  Vagrant.configure(VAGRANT_VERSION) do |config|

    config.cache.auto_detect = [
      validate_value(lookup_values_yaml(plugin_info, ['settings', 'auto_detect'])),
      auto_detect_default
    ].find { |i| !i.nil? }

    config.cache.scope = [
      validate_value(lookup_values_yaml(plugin_info, ['settings', 'cache_scope'])),
      cache_scope_default
    ].find { |i| !i.nil? }

    synced_folder_opts = [
      validate_value(lookup_values_yaml(plugin_info, ['settings', 'synced_folder_opts'])),
      synced_folder_opts_default
    ].find { |i| !i.nil? }
    config.cache.synced_folder_opts = synced_folder_opts if synced_folder_opts

  end
end
