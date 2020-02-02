#
# Top-level handler function responsible for calling the various provider instantiation and configuration code.
#
def configure_instances(
  machine,
  instance_profile,
  provider = 'virtualbox'
)

  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  if $profile_names_loaded.include?("#{name}-#{provider}")
    exit_with_message("profile name [#{name}] with provider [#{provider}] is already defined in another location.")
  else
    $profile_names_loaded.push("#{name}-#{provider}")
  end

  provider_dir = "#{PROVIDERS_DIR}/#{provider}"

  if $provider_loaded_last != provider
    if File.directory?(provider_dir)
      ruby_files = Find.find(provider_dir)
      ruby_files and ruby_files.each do |ruby_file|
        load ruby_file if ruby_file=~/\.rb/
      end
    else
      handle_message("failed to load provider directory [#{provider_dir}].")
    end

    $provider_loaded_last = provider
  end

  case provider
  when 'libvirt'
    configure_instance(machine, instance_profile)
  when 'virtualbox'
    configure_instance(machine, instance_profile)
  when 'vmware'
    configure_instance(machine, instance_profile)
  else
    exit_with_message("instance provider [#{provider}] for instance [#{name}] is not supported.")
  end
end



