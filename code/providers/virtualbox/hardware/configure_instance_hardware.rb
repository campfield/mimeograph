#
# Function for managing guest VM hardware and extra options specific to VirtualBox.
#
def configure_instance_hardware(
  machine,
  instance_profile,
  cpus_default = 2,
  memory_default = 512,
  provider = 'virtualbox'
)

  instance_hardware = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'hardware'])

  machine.vm.provider provider do |virtualbox|
    virtualbox.cpus = [
      lookup_values_yaml(instance_hardware, ['cpus']),
      cpus_default
    ].find { |i| !i.nil? }

    virtualbox.memory = [
      lookup_values_yaml(instance_hardware, ['memory']),
      memory_default
    ].find { |i| !i.nil? }

    modifyvm = lookup_values_yaml(instance_hardware, ['modifyvm'])
    if modifyvm
      modifyvm.each do |parameter_name, parameter_value|
        virtualbox.customize ['modifyvm', :id, parameter_name, parameter_value]
      end
    end

    setextradata = lookup_values_yaml(instance_hardware, ['setextradata'])
    if setextradata
      setextradata.each do |parameter_name, parameter_value|
        virtualbox.customize ['setextradata', :id, parameter_name, parameter_value]
      end
    end

  end
end
