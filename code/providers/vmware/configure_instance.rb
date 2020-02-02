#
# Top-level instance configuration function for the VMware Provider. [UNIMPLEMENTED]
#
def configure_instance(
  machine,
  instance_profile,
  provider = 'vmware'
)

  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  handle_message("instance [#{name}] provider [#{provider}] not implemented.")

end
