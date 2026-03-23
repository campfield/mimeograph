#
# Top-level instance configuration for the libvirt provider.
# Requires the vagrant-libvirt plugin to be installed.
#
def configure_instance_libvirt(machine, instance_profile, provider = 'libvirt')
  return false unless lookup_values_yaml(instance_profile, ['providers', provider])

  configure_vagrant_box_libvirt(machine, instance_profile, provider)
  configure_instance_hardware_libvirt(machine, instance_profile, provider)
  configure_networking_libvirt(machine, instance_profile, provider)
  configure_communication(machine, instance_profile, provider)
  configure_filesystems(machine, instance_profile, provider)
  execute_system_commands(machine, instance_profile, provider)
end
