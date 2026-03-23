#
# Top-level handler for filesystem configuration.
#
def configure_filesystems(machine, instance_profile, provider)
  filesystems = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'storage', 'filesystems'])
  configure_synced_fs_objects(machine, instance_profile, filesystems)
end
