#
# A better developer would have commented this code.
#
def configure_instance(
  machine,
  instance_profile,
  provider = 'virtualbox'
)


  return false unless lookup_values_yaml(instance_profile, ['providers', provider])

  configure_vagrant_box(machine, instance_profile)

  configure_instance_hardware(machine, instance_profile)

  configure_networking(machine, instance_profile)

  configure_communication(machine, instance_profile)

  configure_filesystems(machine, instance_profile, provider)

  execute_system_commands(machine, instance_profile, provider)

end
