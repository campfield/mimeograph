#
# Configure host-to-instance communication (GUI display, SSH settings).
#
# GUI display is handled differently per provider:
#   virtualbox  - gui flag via VirtualBox provider block
#   vmware      - gui flag via vmware_desktop provider block
#   libvirt     - display managed via graphics_type in configure_vagrant_box_libvirt; no gui flag here
#
# The Vagrant provider API name differs from mimeograph's YAML key for VMware:
#   YAML key 'vmware' -> Vagrant provider name 'vmware_desktop'
#
def configure_communication(
  machine,
  instance_profile,
  provider               = 'virtualbox',
  auth_method_default    = 'keypair',
  forward_agent_default  = false,
  forward_x11_default    = false,
  gui_default            = false,
  insert_key_default     = true,
  password_default       = 'vagrant',
  username_default       = 'vagrant'
)
  instance_communication = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'communication'])

  # Resolve the Vagrant provider API name — VMware uses 'vmware_desktop' not 'vmware'
  vagrant_provider_name = provider == 'vmware' ? 'vmware_desktop' : provider

  # Apply GUI setting for providers that support a gui flag.
  # libvirt manages display via graphics_type in its own box config block; skip it here.
  unless provider == 'libvirt'
    machine.vm.provider vagrant_provider_name do |prov|
      prov.gui = validate_value(
        [
          lookup_values_yaml(instance_communication, ['display', 'gui']),
          gui_default
        ].find { |v| !v.nil? }
      )
    end
  end

  instance_ssh = lookup_values_yaml(instance_communication, ['ssh'])
  return unless instance_ssh

  machine.ssh.forward_agent = validate_value(
    [
      lookup_values_yaml(instance_ssh, ['forward_agent']),
      forward_agent_default
    ].find { |v| !v.nil? }
  )

  machine.ssh.forward_x11 = validate_value(
    [
      lookup_values_yaml(instance_ssh, ['forward_x11']),
      forward_x11_default
    ].find { |v| !v.nil? }
  )

  machine.ssh.username = [
    lookup_values_yaml(instance_ssh, ['username']),
    username_default
  ].find { |v| !v.nil? }

  machine.ssh.insert_key = validate_value(
    [
      lookup_values_yaml(instance_ssh, ['insert_key']),
      insert_key_default
    ].find { |v| !v.nil? }
  )

  # Private key path — only set when explicitly configured.
  # Useful when using a pre-baked keypair instead of Vagrant's insecure key.
  private_key_path = lookup_values_yaml(instance_ssh, ['private_key_path'])
  machine.ssh.private_key_path = private_key_path if private_key_path

  auth_method = [
    lookup_values_yaml(instance_ssh, ['auth_method']),
    auth_method_default
  ].find { |v| !v.nil? }
  validate_value(auth_method, %w[keypair password])

  if auth_method == 'password'
    machine.ssh.password = [
      lookup_values_yaml(instance_ssh, ['password']),
      password_default
    ].find { |v| !v.nil? }
  end
end
