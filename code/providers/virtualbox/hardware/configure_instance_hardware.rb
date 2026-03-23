#
# Configure VirtualBox instance hardware: CPUs, memory, modifyvm, and setextradata.
#
# setextradata YAML structure expects flat key/value pairs:
#
#   setextradata:
#     VBoxInternal/key: value
#
def configure_instance_hardware(
  machine,
  instance_profile,
  provider       = 'virtualbox',
  cpus_default   = 2,
  memory_default = 512
)
  instance_hardware = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'hardware'])

  machine.vm.provider provider do |vbox|
    vbox.cpus = [
      lookup_values_yaml(instance_hardware, ['cpus']),
      cpus_default
    ].find { |v| !v.nil? }

    vbox.memory = [
      lookup_values_yaml(instance_hardware, ['memory']),
      memory_default
    ].find { |v| !v.nil? }

    modifyvm = lookup_values_yaml(instance_hardware, ['modifyvm'])
    if modifyvm
      modifyvm.each do |param, value|
        vbox.customize ['modifyvm', :id, param.to_s, value.to_s]
      end
    end

    # setextradata expects flat string key => string value pairs
    setextradata = lookup_values_yaml(instance_hardware, ['setextradata'])
    if setextradata
      setextradata.each do |key, value|
        unless value.is_a?(String) || value.is_a?(Numeric)
          handle_message("setextradata key [#{key}] has a non-scalar value and will be skipped.", 'WARNING')
          next
        end
        vbox.customize ['setextradata', :id, key.to_s, value.to_s]
      end
    end
  end
end
