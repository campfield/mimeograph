#
# Generate a synced_fs_objects-compatible hash for syncing OS package manager
# repository configuration files from the host into the instance.
#
# Supports: yum, dnf (both use /etc/yum.repos.d)
#
# Expected site_settings structure in instance profile:
#
#   site_settings:
#     package_managers:
#       package_manager: yum       # or dnf
#       defaults:
#         package_manager: yum     # fallback
#         yum:
#           repository_id: centos-7-upstream
#
def load_os_package_repo_hash(
  instance_profile,
  provider               = 'virtualbox',
  package_manager_default = 'none',
  repository_id_default   = 'none',
  rsync_options           = %w[-a --delete --verbose],
  sync_type               = 'rsync'
)
  provider_info = lookup_values_yaml(instance_profile, ['providers', provider])
  return nil unless provider_info

  package_manager = [
    lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', 'package_manager']),
    lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', 'defaults', 'package_manager']),
    package_manager_default
  ].find { |v| !v.nil? }

  return nil if package_manager == 'none'

  repository_id = [
    lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', package_manager, 'repository_id']),
    lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', 'defaults', package_manager, 'repository_id']),
    repository_id_default
  ].find { |v| !v.nil? }

  return nil if repository_id == 'none'

  case package_manager
  when 'yum', 'dnf'
    {
      '/etc/yum.repos.d' => {
        'host_path'              => "files/os/package_managers/#{package_manager}/yum.repos.d/#{repository_id}",
        'instance_path'          => '/etc/yum.repos.d',
        'rsync'                  => {
          'options' => rsync_options,
          'verbose' => true
        },
        'prepend_base_directory' => true,
        'type'                   => sync_type
      }
    }
  else
    exit_with_message("package_manager [#{package_manager}] is not supported.")
  end
end
