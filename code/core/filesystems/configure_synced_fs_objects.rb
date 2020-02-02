#
# Manage the synchronization, mounting, creation, etc of filesystem objects.
#
def configure_synced_fs_objects(
  machine,
  instance_profile,
  filesystems,
  create_instance_path_default = true,
  group_default = 'root',
  mount_options_default = "dmode='777',fmode='777'",
  owner_default = 'root',
  prepend_base_directory_default = false,
  rsync__args_default = [
    '--archive',
    '--copy-links',
    '--delete',
    '--safe-links'
  ],
  rsync__auto_default = true,
  rsync__exclude_default = ['.vagrant/'],
  rsync__privileged_default = false,
  rsync__verbose_default = false,
  sharedfoldersenablesymlinkscreate_default = false,
  sync_type_default = 'sync',
  sync_types = ['file', 'sync', 'rsync']
)

  synced_fs_objects = lookup_values_yaml(filesystems, ['synced_fs_objects'])

  return false unless synced_fs_objects

  name = lookup_values_yaml(instance_profile, ['name'])

  synced_fs_objects.each do |object_name, object_info|
    rsync__verbose = false
    sync_type = [
      lookup_values_yaml(object_info, ['type']),
      lookup_values_yaml(filesystems, ['defaults', 'sync_type']),
      sync_type_default
    ].find { |i| !i.nil? }
    validate_value(sync_type, sync_types)

    rsync__args = [
      lookup_values_yaml(object_info, ['rsync', 'args']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'args']),
      rsync__args_default
    ].find { |i| !i.nil? }

    rsync__privileged = [
      lookup_values_yaml(object_info, ['rsync', 'privileged']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'privileged']),
      rsync__privileged_default
    ].find { |i| !i.nil? }
    validate_value(rsync__privileged)

    if rsync__privileged == true and !rsync__args.include?("--rsync-path='sudo rsync'")
      rsync__args.push("--rsync-path='sudo rsync'")
    end

    rsync__auto = [
      lookup_values_yaml(object_info, ['rsync', 'auto']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'auto']),
      rsync__auto_default
    ].find { |i| !i.nil? }

    rsync__verbose = [
      lookup_values_yaml(object_info, ['rsync', 'verbose']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'verbose']),
      rsync__verbose_default
    ].find { |i| !i.nil? }
    validate_value(rsync__verbose)

    rsync__exclude = [
      lookup_values_yaml(object_info, ['rsync', 'exclude']),
      rsync__exclude_default
    ].find { |i| !i.nil? }

    prepend_base_directory = [
      lookup_values_yaml(object_info, ['prepend_base_directory']),
      lookup_values_yaml(filesystems, ['defaults', 'prepend_base_directory']),
      prepend_base_directory_default
    ].find { |i| !i.nil? }

    mount_options = [
      lookup_values_yaml(object_info, ['mount_options']),
      lookup_values_yaml(filesystems, ['defaults', 'mount_options']),
      mount_options_default
    ].find { |i| !i.nil? }

    owner = [
      lookup_values_yaml(object_info, ['owner']),
      lookup_values_yaml(filesystems, ['defaults', 'owner']),
      owner_default
    ].find { |i| !i.nil? }

    group = [
      lookup_values_yaml(object_info, ['group']),
      lookup_values_yaml(filesystems, ['defaults', 'group']),
      group_default
    ].find { |i| !i.nil? }

    create_instance_path = [
      lookup_values_yaml(object_info, ['create_instance_path']),
      lookup_values_yaml(filesystems, ['defaults', 'create_instance_path']),
      create_instance_path_default
    ].find { |i| !i.nil? }
    validate_value(create_instance_path)

    sharedfoldersenablesymlinkscreate = [
      lookup_values_yaml(object_info, ['sharedfoldersenablesymlinkscreate']),
      lookup_values_yaml(filesystems, ['defaults', 'sharedfoldersenablesymlinkscreate']),
      sharedfoldersenablesymlinkscreate_default
    ].find { |i| !i.nil? }
    validate_value(sharedfoldersenablesymlinkscreate)

    instance_path = lookup_values_yaml(object_info, ['instance_path'])

    host_path = [
      lookup_values_yaml(object_info, ['host_path']),
      object_name
    ].find { |i| !i.nil? }


    unless instance_path
      exit_with_message("filesystem sync object [#{object_name}] missing value for 'instance_path.'")
    end

    case prepend_base_directory
    when true
      host_path = "#{BASE_DIR}/#{host_path}"
    when false
      # do nothing
    else
      host_path = "#{prepend_base_directory}/#{host_path}"
    end

    if File.file?(host_path)
      sync_type = 'file'
    elsif !File.exist?(host_path)
      handle_message("instance [#{name}] filesystem object [#{object_name}] at host path [#{host_path}] not found.", "WARNING")
    end

    case sync_type
    when 'sync'
      machine.vm.synced_folder host_path, instance_path.to_s, create: create_instance_path, mount_options: [mount_options.to_s], owner: owner, group: group, SharedFoldersEnableSymlinksCreate: sharedfoldersenablesymlinkscreate
    when 'rsync'
      machine.vm.synced_folder host_path, instance_path.to_s, create: create_instance_path, type: sync_type, rsync__args: rsync__args, rsync__exclude: rsync__exclude, rsync__verbose: rsync__verbose, rsync__auto: rsync__auto
    when 'file'
      if File.file?(host_path)
        machine.vm.provision sync_type, source: host_path, destination: instance_path.to_s
      end
    else
      exit_with_message("sync_type [#{sync_type}] is not supported.  You should not see this message.")
    end
  end
end
