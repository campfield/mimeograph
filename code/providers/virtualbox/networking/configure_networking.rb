#
# Top-level handler function for dealing with Vagrant networking.
#
def configure_networking(
  machine,
  instance_profile,
  provider = 'virtualbox'
)

  instance_networking = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'networking'])

  return false unless instance_networking

  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  configure_interfaces(machine, name, instance_networking)

  configure_forwarded_ports(machine, name, instance_networking)

end
