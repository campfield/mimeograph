#
# Confgure the Vagrant Box-specific notes (and hostname)
#
def configure_vagrant_box(
  machine,
  instance_profile,
  boot_timeout_default = 240,
  download_insecure_default = false,
  linked_clone_default = false,
  provider = 'virtualbox'
)

  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))
  box_config = lookup_values_yaml(instance_profile, ['providers', provider])

  if name
    machine.vm.provider 'virtualbox' do |virtualbox|
      virtualbox.name = name
    end
  else
    exit_with_message("No value for instance profile [name] provided.  If you see this message your YAML does not likely conform to the expected formatting.")
  end

  machine.vm.boot_timeout = [
    lookup_values_yaml(box_config, ['instance', 'boot_timeout']),
    boot_timeout_default
  ].find { |i| !i.nil? }

  machine.vm.box = [
    lookup_values_yaml(box_config, ['instance', 'box', 'name']),
    name
  ].find { |i| !i.nil? }

  machine.vm.box_download_insecure = validate_value([
    lookup_values_yaml(box_config, ['instance', 'box', 'download_insecure']),
    download_insecure_default
  ].find { |i| !i.nil? })

  box_url = lookup_values_yaml(box_config, ['instance', 'box', 'url'])
  machine.vm.box_url = box_url if box_url

  machine.vm.hostname = [
    lookup_values_yaml(box_config, ['instance', 'hostname']),
    name.gsub(/[^a-z0-9-]/i, '')
  ].find { |i| !i.nil? }


  machine.vm.provider provider do |virtualbox|
    virtualbox.linked_clone = [
      validate_value(lookup_values_yaml(box_config, ['instance', 'box', 'linked_clone'])),
      linked_clone_default
    ].find { |i| !i.nil? }
  end

end