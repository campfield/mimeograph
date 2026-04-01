#
# configure_vagrant_box.rb
#
# Configures the Vagrant Box identity, boot settings, and hostname for a
# VirtualBox instance.  This runs first in the provider pipeline, establishing
# the box source before hardware or networking is configured.
#
# YAML path: providers.virtualbox.instance
#
# Supported keys:
#   boot_timeout          Integer  Seconds to wait for the VM to boot.
#                                  Default: 240
#   box.name              String   Vagrant Cloud name or local catalog name.
#                                  Falls back to the sanitised instance name
#                                  if omitted, so a local box with the same
#                                  name as the instance will be used.
#   box.url               String   Direct URL to download the Box from.
#                                  If box.name is also set it is used as the
#                                  local catalog key; otherwise the instance
#                                  name is used.
#   box.download_insecure Boolean  Skip SSL certificate verification when
#                                  downloading the Box.  Useful behind
#                                  corporate proxies with self-signed certs.
#                                  Default: false
#   box.linked_clone      Boolean  Create a VirtualBox linked clone rather
#                                  than a full copy.  Faster provisioning and
#                                  lower disk usage.  Default: false
#   box.base_mac          String   MAC address for the first (NAT) NIC.
#                                  Format: 12 hex digits, no separators
#                                  e.g. '080027AABBCC'.
#                                  Default: nil (VirtualBox randomises the MAC)
#   hostname              String   Guest OS hostname.  Defaults to the
#                                  instance name with non-alphanumeric
#                                  characters stripped.
#
def configure_vagrant_box(
  machine,
  instance_profile,
  provider                  = 'virtualbox',
  boot_timeout_default      = 240,
  download_insecure_default = false,
  linked_clone_default      = false,
  base_mac_default          = nil
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

  machine.vm.provider provider do |vbox|
    # Set vbox.name for Vagrant's SetName action.  The post-configuration
    # modifyvm --name in configure_instance_virtualbox.rb reinforces this
    # after Vagrant restores any existing machine state.
    vbox.name = name

    vbox.linked_clone = validate_value(
      [
        lookup_values_yaml(box_config, ['instance', 'box', 'linked_clone']),
        linked_clone_default
      ].find { |v| !v.nil? }
    )

    base_mac = [
      lookup_values_yaml(box_config, ['instance', 'box', 'base_mac']),
      base_mac_default
    ].find { |v| !v.nil? }

    # Generate a deterministic MAC for NIC1 (the NAT adapter) if none is set.
    # Uses the VirtualBox OUI (08:00:27) and a hash of the instance name +
    # interface index, so the same instance always gets the same MAC.
    # This stabilises DHCP leases and NetworkManager connection profiles
    # across vagrant destroy/up cycles.
    unless base_mac
      mac_hash = Digest::MD5.hexdigest("#{name}-mac-1").upcase
      base_mac = "080027#{mac_hash[0..5]}"
    end

    vbox.customize ['modifyvm', :id, '--macaddress1', base_mac]
  end
end
