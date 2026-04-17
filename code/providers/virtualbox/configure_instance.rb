#
# Top-level instance configuration for the VirtualBox provider.
#
def configure_instance_virtualbox(machine, instance_profile, provider = 'virtualbox')
  return false unless lookup_values_yaml(instance_profile, ['providers', provider])

  configure_vagrant_box(machine, instance_profile, provider)
  configure_instance_hardware(machine, instance_profile, provider)
  configure_networking(machine, instance_profile, provider)
  configure_vagrant_dns(machine, instance_profile, provider)
  configure_communication(machine, instance_profile, provider)
  configure_filesystems(machine, instance_profile, provider)
  execute_system_commands(machine, instance_profile, provider)

  # Set the VirtualBox VM name using customize so it is applied via VBoxManage
  # after Vagrant restores any existing machine state. Using vbox.name alone is
  # insufficient because Vagrant's state restoration can override it.
  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))
  machine.vm.provider provider do |vbox|
    vbox.name = name
    vbox.customize ['modifyvm', :id, '--name', name]
  end
end
