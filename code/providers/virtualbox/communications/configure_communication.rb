#
# Configure host-to-box communications methods.
#
def configure_communication(
  machine,
  instance_profile,
  auth_method_default = 'keypair',
  forward_agent_default = false,
  forward_x11_default = false,
  gui_default = false,
  insert_key_default = true,
  password_default = 'vagrant',
  provider = 'virtualbox',
  username_default = 'vagrant'
)

  instance_communication = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'communication'])

  machine.vm.provider provider do |virtualbox|
    virtualbox.gui = [
      validate_value(lookup_values_yaml(instance_communication, ['display', 'gui'])),
      gui_default
    ].find { |i| !i.nil? }
  end

  instance_ssh = lookup_values_yaml(instance_communication, ['ssh'])

  if instance_ssh

    machine.ssh.forward_agent = [
      validate_value(lookup_values_yaml(instance_ssh, ['forward_agent'])),
      forward_agent_default
    ].find { |i| !i.nil? }

    machine.ssh.forward_x11 = [
      validate_value(lookup_values_yaml(instance_ssh, ['forward_x11'])),
      forward_x11_default
    ].find { |i| !i.nil? }

    machine.ssh.username = [
      lookup_values_yaml(instance_ssh, ['username']),
      username_default
    ].find { |i| !i.nil? }

    machine.ssh.insert_key = [
      validate_value(lookup_values_yaml(instance_ssh, ['insert_key'])),
      insert_key_default
    ].find { |i| !i.nil? }

    auth_method = [
      lookup_values_yaml(instance_ssh, ['auth_method']),
      auth_method_default
    ].find { |i| !i.nil? }
    validate_value(auth_method, ['keypair', 'password'])

    if auth_method == 'password'
      machine.ssh.password = [
        lookup_values_yaml(instance_ssh, ['password']),
        password_default
      ].find { |i| !i.nil? }
    elsif auth_method == 'keypair'
      # Private key is the default option for connections in Vagrant so no setting required here.
    end

  end

end
