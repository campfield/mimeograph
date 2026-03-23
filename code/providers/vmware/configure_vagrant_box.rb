#
# Configure Vagrant Box settings and hostname for a VMware Desktop instance.
#
# The VMware Desktop provider uses 'vmware_desktop' as the Vagrant provider name.
# mimeograph uses 'vmware' as the YAML key; VMWARE_PROVIDER_NAME is defined in
# configure_instance.rb and available to all files in this provider directory.
#
# VMware-specific box options:
#   boot_timeout        - seconds to wait for boot (default: 300)
#   box.name            - Vagrant box name (falls back to instance name)
#   box.url             - direct URL to download box from
#   box.download_insecure - skip SSL verification (default: false)
#   box.linked_clone    - use linked clones (default: false)
#   hostname            - guest hostname
#   clone_directory     - path for VMware clone storage (default: ./.vagrant)
#   verify_vmnet        - verify vmnet device health before use (default: true)
#   nat_device          - host vmnet device for NAT (default: auto-detected, fallback vmnet8)
#
VMWARE_PROVIDER_NAME = 'vmware_desktop' unless defined?(VMWARE_PROVIDER_NAME)

def configure_vagrant_box_vmware(
  machine,
  instance_profile,
  provider                  = 'vmware',
  boot_timeout_default      = 300,
  download_insecure_default = false,
  linked_clone_default      = false,
  verify_vmnet_default      = true
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

  machine.vm.provider VMWARE_PROVIDER_NAME do |vmw|
    vmw.linked_clone = validate_value(
      [
        lookup_values_yaml(box_config, ['instance', 'box', 'linked_clone']),
        linked_clone_default
      ].find { |v| !v.nil? }
    )

    vmw.verify_vmnet = validate_value(
      [
        lookup_values_yaml(box_config, ['instance', 'verify_vmnet']),
        verify_vmnet_default
      ].find { |v| !v.nil? }
    )

    clone_dir = lookup_values_yaml(box_config, ['instance', 'clone_directory'])
    vmw.clone_directory = clone_dir if clone_dir

    nat_device = lookup_values_yaml(box_config, ['instance', 'nat_device'])
    vmw.nat_device = nat_device if nat_device

    # Apply base_mac — map the provider-agnostic YAML key to VMware's VMX entries.
    # Only set when an explicit MAC is provided; nil (default) lets VMware randomise.
    base_mac = lookup_values_yaml(box_config, ['instance', 'box', 'base_mac'])
    if base_mac
      vmw.vmx['ethernet0.addressType'] = 'static'
      vmw.vmx['ethernet0.address']     = base_mac.to_s
    end
  end
end
