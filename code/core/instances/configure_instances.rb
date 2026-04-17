#
# Dispatch to the correct provider's configure_instance() function.
# Provider code is loaded once per provider and cached across instances.
#
PROVIDERS_LOADED = {}

def configure_instances(machine, instance_profile, provider = 'virtualbox')
  return false unless lookup_values_yaml(instance_profile, ['providers', provider])

  provider_dir = "#{PROVIDERS_DIR}/#{provider}"

  unless PROVIDERS_LOADED[provider]
    if File.directory?(provider_dir)
      Find.find(provider_dir).sort.each do |f|
        require f if f =~ /\.rb$/
      end
      PROVIDERS_LOADED[provider] = true
    else
      exit_with_message("provider directory [#{provider_dir}] not found.")
    end
  end

  case provider
  when 'virtualbox'
    configure_instance_virtualbox(machine, instance_profile, provider)
  when 'libvirt'
    configure_instance_libvirt(machine, instance_profile, provider)
  when 'vmware'
    configure_instance_vmware(machine, instance_profile, provider)
  else
    exit_with_message("provider [#{provider}] is not supported.")
  end
end
