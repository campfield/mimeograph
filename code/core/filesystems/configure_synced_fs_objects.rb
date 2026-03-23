#
# configure_synced_fs_objects.rb
#
# Manages synced filesystem objects between the host and guest.
# Called for every provider; sync type availability depends on the provider
# and guest OS (see notes per type below).
#
# YAML path: providers.<provider>.instance.storage.filesystems
#
# Top-level structure:
#   filesystems:
#     defaults:          Hash  Default values applied to every synced_fs_object
#                              in this instance unless overridden per-object.
#     synced_fs_objects: Hash  Map of object names to their configuration.
#                              The key is used as host_path if host_path is omitted.
#
# Per-object keys (synced_fs_objects.<name>):
#   instance_path             String   Required. Absolute path on the guest.
#   host_path                 String   Path on the host. Defaults to the object
#                                      key name. See prepend_base_directory.
#   type                      String   Sync mechanism. One of:
#                                        sync  - VirtualBox shared folder (vboxsf).
#                                                Bi-directional, auto-mounted.
#                                                Not available on libvirt without
#                                                VirtualBox Guest Additions.
#                                        rsync - One-way host→guest rsync.
#                                                Available on all providers.
#                                                Runs on provision; optionally
#                                                on every boot via rsync.auto.
#                                        nfs   - NFS mount from host to guest.
#                                                Host must export the path;
#                                                guest must have nfs-common.
#                                                Recommended for libvirt.
#                                        file  - Vagrant file provisioner.
#                                                Copies a single file on
#                                                provision only.
#                                                Auto-selected when host_path
#                                                resolves to a regular file.
#                                      Default: sync
#   prepend_base_directory    Mixed    Controls host_path prefix resolution:
#                                        true   - prepend mimeograph root dir
#                                        false  - use host_path as-is
#                                        String - prepend this string
#                                      Default: false
#   create_instance_path      Boolean  Create instance_path on the guest if
#                                      it does not exist.  Default: true
#   owner                     String   Guest filesystem owner.  Default: 'root'
#   group                     String   Guest filesystem group.  Default: 'root'
#   mount_options             String   Mount options string passed to the
#                                      hypervisor synced folder API.
#                                      Default: "dmode='777',fmode='777'"
#   sharedfoldersenablesymlinkscreate
#                             Boolean  Allow symlink creation inside VirtualBox
#                                      shared folders.  Default: false
#
# rsync sub-keys (under synced_fs_objects.<name>.rsync):
#   options    Array    rsync CLI arguments.
#                       Default: ['--archive','--copy-links','--delete','--safe-links']
#   exclude    Array    Paths to exclude from rsync.  Default: ['.vagrant/']
#   auto       Boolean  Re-sync on `vagrant rsync-auto`.  Default: true
#   verbose    Boolean  Print rsync output.  Default: false
#   privileged Boolean  Run rsync as root on the guest via sudo.
#                       Automatically appends --rsync-path='sudo rsync'
#                       to options when true.  Default: false
#
# nfs sub-keys (under synced_fs_objects.<name>.nfs):
#   mount_options  Array   NFS mount options passed to the guest.
#                          Default: ['rw','vers=3','tcp','nolock']
#   map_uid        Mixed   UID mapping for the NFS mount.  Default: :auto
#   map_gid        Mixed   GID mapping for the NFS mount.  Default: :auto
#   udp            Boolean Use UDP transport.  Default: false
#
def configure_synced_fs_objects(
  machine,
  instance_profile,
  filesystems,
  create_instance_path_default              = true,
  group_default                             = 'root',
  mount_options_default                     = "dmode='777',fmode='777'",
  nfs_mount_options_default                 = %w[rw vers=3 tcp nolock],
  nfs_map_uid_default                       = :auto,
  nfs_map_gid_default                       = :auto,
  nfs_udp_default                           = false,
  owner_default                             = 'root',
  prepend_base_directory_default            = false,
  rsync__args_default                       = %w[--archive --copy-links --delete --safe-links],
  rsync__auto_default                       = true,
  rsync__exclude_default                    = ['.vagrant/'],
  rsync__privileged_default                 = false,
  rsync__verbose_default                    = false,
  sharedfoldersenablesymlinkscreate_default = false,
  sync_type_default                         = 'sync',
  valid_sync_types                          = %w[file nfs rsync sync]
)
  synced_fs_objects = lookup_values_yaml(filesystems, ['synced_fs_objects'])
  return false unless synced_fs_objects

  instance_name = lookup_values_yaml(instance_profile, ['name'])

  synced_fs_objects.each do |object_name, object_info|
    object_info ||= {}

    # ── Sync type ─────────────────────────────────────────────────────────────
    sync_type = [
      lookup_values_yaml(object_info, ['type']),
      lookup_values_yaml(filesystems, ['defaults', 'sync_type']),
      sync_type_default
    ].find { |v| !v.nil? }
    validate_value(sync_type, valid_sync_types)

    # ── rsync options ─────────────────────────────────────────────────────────
    # YAML key is 'options' throughout; mapped to rsync__args for Vagrant's API
    rsync__args = [
      lookup_values_yaml(object_info, ['rsync', 'options']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'options']),
      rsync__args_default
    ].find { |v| !v.nil? }

    rsync__privileged = [
      lookup_values_yaml(object_info, ['rsync', 'privileged']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'privileged']),
      rsync__privileged_default
    ].find { |v| !v.nil? }
    validate_value(rsync__privileged)

    # Append sudo rsync path argument when privileged rsync is requested
    if rsync__privileged == true && !rsync__args.include?("--rsync-path='sudo rsync'")
      rsync__args = rsync__args + ["--rsync-path='sudo rsync'"]
    end

    rsync__auto = [
      lookup_values_yaml(object_info, ['rsync', 'auto']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'auto']),
      rsync__auto_default
    ].find { |v| !v.nil? }

    rsync__verbose = [
      lookup_values_yaml(object_info, ['rsync', 'verbose']),
      lookup_values_yaml(filesystems, ['defaults', 'rsync', 'verbose']),
      rsync__verbose_default
    ].find { |v| !v.nil? }
    validate_value(rsync__verbose)

    rsync__exclude = [
      lookup_values_yaml(object_info, ['rsync', 'exclude']),
      rsync__exclude_default
    ].find { |v| !v.nil? }

    # ── NFS options ───────────────────────────────────────────────────────────
    nfs_mount_options = [
      lookup_values_yaml(object_info, ['nfs', 'mount_options']),
      lookup_values_yaml(filesystems, ['defaults', 'nfs', 'mount_options']),
      nfs_mount_options_default
    ].find { |v| !v.nil? }

    nfs_map_uid = [
      lookup_values_yaml(object_info, ['nfs', 'map_uid']),
      lookup_values_yaml(filesystems, ['defaults', 'nfs', 'map_uid']),
      nfs_map_uid_default
    ].find { |v| !v.nil? }

    nfs_map_gid = [
      lookup_values_yaml(object_info, ['nfs', 'map_gid']),
      lookup_values_yaml(filesystems, ['defaults', 'nfs', 'map_gid']),
      nfs_map_gid_default
    ].find { |v| !v.nil? }

    nfs_udp = [
      lookup_values_yaml(object_info, ['nfs', 'udp']),
      lookup_values_yaml(filesystems, ['defaults', 'nfs', 'udp']),
      nfs_udp_default
    ].find { |v| !v.nil? }
    validate_value(nfs_udp)

    # ── Shared options ────────────────────────────────────────────────────────
    prepend_base_directory = [
      lookup_values_yaml(object_info, ['prepend_base_directory']),
      lookup_values_yaml(filesystems, ['defaults', 'prepend_base_directory']),
      prepend_base_directory_default
    ].find { |v| !v.nil? }

    mount_options = [
      lookup_values_yaml(object_info, ['mount_options']),
      lookup_values_yaml(filesystems, ['defaults', 'mount_options']),
      mount_options_default
    ].find { |v| !v.nil? }

    owner = [
      lookup_values_yaml(object_info, ['owner']),
      lookup_values_yaml(filesystems, ['defaults', 'owner']),
      owner_default
    ].find { |v| !v.nil? }

    group = [
      lookup_values_yaml(object_info, ['group']),
      lookup_values_yaml(filesystems, ['defaults', 'group']),
      group_default
    ].find { |v| !v.nil? }

    create_instance_path = [
      lookup_values_yaml(object_info, ['create_instance_path']),
      lookup_values_yaml(filesystems, ['defaults', 'create_instance_path']),
      create_instance_path_default
    ].find { |v| !v.nil? }
    validate_value(create_instance_path)

    sharedfoldersenablesymlinkscreate = [
      lookup_values_yaml(object_info, ['sharedfoldersenablesymlinkscreate']),
      lookup_values_yaml(filesystems, ['defaults', 'sharedfoldersenablesymlinkscreate']),
      sharedfoldersenablesymlinkscreate_default
    ].find { |v| !v.nil? }
    validate_value(sharedfoldersenablesymlinkscreate)

    # ── Path resolution ───────────────────────────────────────────────────────
    instance_path = lookup_values_yaml(object_info, ['instance_path'])
    exit_with_message("filesystem object [#{object_name}] is missing required value 'instance_path'.") unless instance_path

    host_path = lookup_values_yaml(object_info, ['host_path']) || object_name

    case prepend_base_directory
    when true
      host_path = "#{BASE_DIR}/#{host_path}"
    when false
      # use host_path as-is
    else
      host_path = "#{prepend_base_directory}/#{host_path}"
    end

    # Auto-detect: if the resolved host_path is a regular file, switch to 'file'
    # provisioner regardless of what type was configured.
    if File.file?(host_path)
      sync_type = 'file'
    elsif !File.exist?(host_path)
      handle_message(
        "instance [#{instance_name}] filesystem object [#{object_name}] " \
        "host path [#{host_path}] not found.", 'WARNING'
      )
    end

    # ── Apply sync configuration ───────────────────────────────────────────────
    case sync_type

    when 'sync'
      # VirtualBox shared folder (vboxsf). Bi-directional, auto-mounted.
      # Requires VirtualBox Guest Additions on the guest.
      machine.vm.synced_folder host_path, instance_path.to_s,
        create:                            create_instance_path,
        mount_options:                     [mount_options.to_s],
        owner:                             owner,
        group:                             group,
        SharedFoldersEnableSymlinksCreate: sharedfoldersenablesymlinkscreate

    when 'rsync'
      # One-way host→guest rsync. Available on all providers.
      # Runs during provision; repeats on `vagrant rsync` or `vagrant rsync-auto`.
      machine.vm.synced_folder host_path, instance_path.to_s,
        create:         create_instance_path,
        type:           'rsync',
        rsync__args:    rsync__args,
        rsync__exclude: rsync__exclude,
        rsync__verbose: rsync__verbose,
        rsync__auto:    rsync__auto

    when 'nfs'
      # NFS mount from host to guest. Recommended for libvirt.
      # Host must export the path (/etc/exports or nfsd); guest needs nfs-common.
      # Vagrant manages /etc/exports on the host automatically on Linux/macOS.
      # Requires sudo on the host for exports management (Vagrant handles this).
      machine.vm.synced_folder host_path, instance_path.to_s,
        type:               'nfs',
        create:             create_instance_path,
        mount_options:      nfs_mount_options,
        nfs_udp:            nfs_udp,
        map_uid:            nfs_map_uid,
        map_gid:            nfs_map_gid,
        linux__nfs_options: nfs_mount_options

    when 'file'
      # Vagrant file provisioner. Copies a single file on provision only.
      # host_path must be a regular file (directories are not supported).
      machine.vm.provision 'file',
        source:      host_path,
        destination: instance_path.to_s if File.file?(host_path)
    end
  end
end
