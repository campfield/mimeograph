#
# Top-level instance configuration for the VMware Desktop provider.
# Supports VMware Fusion, Workstation, and Player via the vagrant-vmware-desktop plugin.
# Provider name: 'vmware_desktop' (also accepts 'vmware_fusion', 'vmware_workstation')
#
# mimeograph uses 'vmware' as the YAML key. The Vagrant API name 'vmware_desktop'
# is defined here and referenced by all VMware provider files.
#
VMWARE_PROVIDER_NAME = 'vmware_desktop'

def configure_instance_vmware(machine, instance_profile, provider = 'vmware')
  return false unless lookup_values_yaml(instance_profile, ['providers', provider])

  configure_vagrant_box_vmware(machine, instance_profile, provider)
  configure_instance_hardware_vmware(machine, instance_profile, provider)
  configure_networking_vmware(machine, instance_profile, provider)
  configure_vagrant_dns(machine, instance_profile, provider)
  configure_communication(machine, instance_profile, provider)
  configure_filesystems(machine, instance_profile, provider)
  execute_system_commands(machine, instance_profile, provider)

  # Set the VMware display name from the instance name unless the user has
  # already provided a displayname via the hardware.vmx hash.
  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))
  user_vmx = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'hardware', 'vmx']) || {}
  unless user_vmx.key?('displayname') || user_vmx.key?('displayName')
    machine.vm.provider VMWARE_PROVIDER_NAME do |vmw|
      vmw.vmx['displayname'] = name
    end
  end
end
