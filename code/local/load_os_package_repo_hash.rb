#
# site_settings-based function to generate the stanza type for file copying (defaults to rsync)
#  from the host into the instance's OS-specific package repository list (YUM, Apt, etc).
#
def load_os_package_repo_hash(
  instance_profile,
  provider = 'virtualbox',
  package_manager_default = 'none',
  prepend_base_directory = true,
  repository_id_default = 'none',
  rsync__options = [
    '-a',
    '--delete',
    '--verbose'
  ],
  sync_type = 'rsync'
)

  repository_hash = nil

  provider_info = lookup_values_yaml(instance_profile, ['providers', provider])

  case provider
  when 'virtualbox'
    package_manager = [
      lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', 'package_manager']),
      lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', 'defaults', 'package_manager']),
      package_manager_default
    ].find { |i| !i.nil? }

    repository_id = [
      lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', package_manager, 'repository_id']),
      lookup_values_yaml(provider_info, ['instance', 'site_settings', 'package_managers', 'defaults', package_manager, 'repository_id']),
      repository_id_default
    ].find { |i| !i.nil? } if package_manager

    case package_manager
    when 'none'
      # No package manager specified ignore repository sync setup.
    when 'dnf'
      case repository_id
      when 'none'
        # No repository specified ignore repository sync setup.
      else
        repository_hash = {
          '/etc/yum.repos.d' => {
            'host_path' => "files/os/package_managers/#{package_manager}/yum.repos.d/#{repository_id}",
            'instance_path' => '/etc/yum.repos.d',
            'rsync__options' => rsync__options,
            'rsync__verbose' => true,
            'prepend_base_directory' => true,
            'type' => sync_type
          }
        }
        repository_hash
      end
    when 'yum'
      case repository_id
      when 'none'
        # No repository specified ignore repository sync setup.
      else
        repository_hash = {
          '/etc/yum.repos.d' => {
            'host_path' => "files/os/package_managers/#{package_manager}/yum.repos.d/#{repository_id}",
            'instance_path' => '/etc/yum.repos.d',
            'rsync__options' => rsync__options,
            'rsync__verbose' => true,
            'prepend_base_directory' => true,
            'type' => sync_type
          }
        }
        repository_hash
      end
    else
      exit_with_message("package_manager [#{package_manager}] not supported.")
    end
  end
  repository_hash
end
