#
# Load and configure all instance profiles found in config/profiles/.
#
# Each YAML file in config/profiles/ is a profile group.  Its name is used to
# look up a matching defaults file in config/defaults/.  Each instance in the
# group is deep-merged with those defaults (defaults as base, instance on top)
# and then handed to Vagrant's configure block.
#
# Profile name collision across groups is detected and treated as a fatal error.
#
def configure_all_instances
  profile_files = Dir.glob("#{INSTANCE_PROFILES_DIR}/*.yaml").sort

  if profile_files.empty?
    handle_message("no profile files found in [#{INSTANCE_PROFILES_DIR}].", 'WARNING')
    return
  end

  profile_names_seen = []

  profile_files.each do |profile_file|
    profile_group = file_basename(profile_file)
    instances     = load_profiles(profile_group)
    next unless instances

    default_settings = load_profile_defaults(profile_group)

    instances.each do |instance_profile|
      # Merge: defaults are the base, instance values win on conflict
      merged = default_settings.empty? ? instance_profile : default_settings.deep_merge(instance_profile)

      instance_name = replace_characters_string(merged['name'])
      exit_with_message("instance profile missing required 'name' key in [#{profile_file}].") unless instance_name

      providers = [
        lookup_values_yaml(merged, ['providers', 'enabled']),
        lookup_values_yaml(merged, ['providers', 'defaults', 'providers', 'enabled']),
        ['virtualbox']
      ].find { |v| !v.nil? }

      if providers.length > 1
        exit_with_message("instance [#{instance_name}] has #{providers.length} enabled providers. " \
                          "Vagrant does not support multiple providers for the same instance name.")
      end

      providers.each do |provider|
        collision_key = "#{instance_name}-#{provider}"
        if profile_names_seen.include?(collision_key)
          exit_with_message("instance [#{instance_name}] with provider [#{provider}] is defined more than once.")
        end
        profile_names_seen << collision_key

        autostart = [
          lookup_values_yaml(merged, ['providers', provider, 'instance', 'autostart']),
          lookup_values_yaml(merged, ['providers', 'defaults', 'providers', 'autostart']),
          false
        ].find { |v| !v.nil? }

        Vagrant.configure(VAGRANT_VERSION) do |config|
          config.vm.define instance_name, autostart: autostart do |machine|
            configure_instances(machine, merged, provider)
          end
        end
      end
    end
  end
end
