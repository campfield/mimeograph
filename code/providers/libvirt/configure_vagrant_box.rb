#
# Configure the Vagrant Box settings and hostname for a libvirt instance.
#
# libvirt-specific box options supported:
#   boot_timeout      - seconds to wait for boot
#   box.name          - Vagrant box name (falls back to instance name)
#   box.url           - direct URL to download box from
#   box.download_insecure - skip SSL verification
#   hostname          - guest hostname
#   driver            - hypervisor driver: 'kvm' (default) or 'qemu'
#   disk_bus          - disk device bus type: 'virtio' (default), 'scsi', 'ide', 'sata'
#   disk_cache        - disk cache mode: 'none' (default), 'writethrough', 'writeback'
#   storage_pool_name - libvirt storage pool for box images (default: 'default')
#   connect_via_ssh   - connect to remote libvirt host via SSH tunnel
#   host              - remote libvirt host (leave unset for local)
#   username          - username for remote libvirt connection
#   socket            - path to libvirt unix socket (default: system socket)
#   uri               - override full libvirt connection URI
#   qemu_use_session  - use qemu:///session instead of qemu:///system (Fedora default)
#
def configure_vagrant_box_libvirt(
  machine,
  instance_profile,
  provider                  = 'libvirt',
  boot_timeout_default      = 300,
  disk_bus_default          = 'virtio',
  disk_cache_default        = 'none',
  driver_default            = 'kvm',
  download_insecure_default = false,
  storage_pool_default      = 'default',
  qemu_use_session_default  = false
)
  name       = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))
  box_config = lookup_values_yaml(instance_profile, ['providers', provider])

  exit_with_message("instance profile is missing required 'name' key.") unless name

  machine.vm.boot_timeout = [
    lookup_values_yaml(box_config, ['instance', 'boot_timeout']),
    boot_timeout_default
  ].find { |v| !v.nil? }

  machine.vm.box = [
    lookup_values_yaml(box_config, ['instance', 'box', 'name']),
    name
  ].find { |v| !v.nil? }

  machine.vm.box_download_insecure = validate_value(
    [
      lookup_values_yaml(box_config, ['instance', 'box', 'download_insecure']),
      download_insecure_default
    ].find { |v| !v.nil? }
  )

  box_url = lookup_values_yaml(box_config, ['instance', 'box', 'url'])
  machine.vm.box_url = box_url if box_url

  machine.vm.hostname = [
    lookup_values_yaml(box_config, ['instance', 'hostname']),
    name.gsub(/[^a-z0-9\-]/i, '')
  ].find { |v| !v.nil? }

  # Explicitly set the hostname via shell provisioner to ensure it persists
  # on all distributions regardless of Vagrant's own hostname management.
  provision_hostname(machine, instance_profile, provider)

  machine.vm.provider provider do |lv|
    lv.driver = [
      lookup_values_yaml(box_config, ['instance', 'driver']),
      driver_default
    ].find { |v| !v.nil? }

    lv.storage_pool_name = [
      lookup_values_yaml(box_config, ['instance', 'storage_pool_name']),
      storage_pool_default
    ].find { |v| !v.nil? }

    lv.disk_bus = [
      lookup_values_yaml(box_config, ['instance', 'disk_bus']),
      disk_bus_default
    ].find { |v| !v.nil? }

    lv.disk_driver :cache => [
      lookup_values_yaml(box_config, ['instance', 'disk_cache']),
      disk_cache_default
    ].find { |v| !v.nil? }

    lv.qemu_use_session = validate_value(
      [
        lookup_values_yaml(box_config, ['instance', 'qemu_use_session']),
        qemu_use_session_default
      ].find { |v| !v.nil? }
    )

    # Remote libvirt connection options — only set if explicitly configured
    lv_host = lookup_values_yaml(box_config, ['instance', 'host'])
    if lv_host
      lv.host             = lv_host
      lv.connect_via_ssh  = validate_value(lookup_values_yaml(box_config, ['instance', 'connect_via_ssh']) || true)
      lv.username         = lookup_values_yaml(box_config, ['instance', 'username']) || ENV['USER']

      id_ssh_key = lookup_values_yaml(box_config, ['instance', 'id_ssh_key_file'])
      lv.id_ssh_key_file  = id_ssh_key if id_ssh_key
    end

    lv_socket = lookup_values_yaml(box_config, ['instance', 'socket'])
    lv.socket = lv_socket if lv_socket

    lv_uri = lookup_values_yaml(box_config, ['instance', 'uri'])
    lv.uri  = lv_uri if lv_uri

    # Apply base_mac — map the provider-agnostic YAML key to libvirt's
    # management network MAC.  Only set when explicit; nil lets libvirt randomise.
    base_mac = lookup_values_yaml(box_config, ['instance', 'box', 'base_mac'])
    lv.management_network_mac = base_mac.to_s if base_mac
  end
end
