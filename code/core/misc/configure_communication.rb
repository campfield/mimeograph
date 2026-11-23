#
# Configure host-to-instance communication (GUI display, SSH settings).
#
# GUI display is handled differently per provider:
#   virtualbox  - gui flag via VirtualBox provider block
#   vmware      - gui flag via vmware_desktop provider block
#   libvirt     - no provider gui flag: the display device comes from hardware.graphics_type
#                 (configure_instance_hardware_libvirt), and display.gui opens a console
#                 viewer through Vagrant triggers (configure_console_libvirt)
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
  create_pty_default            = false,
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
  # libvirt has none; its display.gui is handled by configure_console_libvirt.
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

  machine.ssh.pty = validate_value(
    [
      lookup_values_yaml(instance_ssh, ['create_pty']),
      create_pty_default
    ].find { |v| !v.nil? }
  )

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

  insert_key = validate_value(
    [
      lookup_values_yaml(instance_ssh, ['insert_key']),
      insert_key_default
    ].find { |v| !v.nil? }
  )
  machine.ssh.insert_key = insert_key

  # Private key path — only set when explicitly configured.
  # Useful when using a pre-baked keypair (e.g. a FIPS/STIG-compatible key)
  # instead of Vagrant's well-known insecure key.
  #
  # Accepts either a single path (String) or a list of paths (Array).  A list is
  # handed to Vagrant unchanged, which lets you present a hardened key while
  # keeping the insecure key as a fallback during a transition, for example:
  #   private_key_path:
  #     - '~/.ssh/fips_vm_ed25519'
  #     - '~/.vagrant.d/insecure_private_key'
  private_key_path = lookup_values_yaml(instance_ssh, ['private_key_path'])
  if private_key_path
    unless private_key_path.is_a?(String) || private_key_path.is_a?(Array)
      exit_with_message(
        "communication.ssh.private_key_path must be a String or a list of " \
        "Strings, got [#{private_key_path.class}]."
      )
    end

    # Warn (do not abort) when a configured key file cannot be found on the host,
    # so a typo surfaces at generation time rather than at connect time.  The
    # original value is still passed to Vagrant untouched so its own path
    # resolution semantics are preserved.
    Array(private_key_path).each do |key_path|
      expanded = File.expand_path(key_path.to_s)
      unless File.exist?(expanded)
        handle_message(
          "communication.ssh.private_key_path [#{key_path}] not found on host " \
          "(resolved to [#{expanded}]).", 'WARNING'
        )
      end
    end

    machine.ssh.private_key_path = private_key_path

    # Warn when a custom key is supplied while Vagrant is still allowed to insert
    # its own generated keypair (insert_key defaults to true).  In the FIPS/STIG
    # intent this is almost always a mistake: Vagrant only performs the swap when
    # it detects the well-known insecure key, so if that key is present in the
    # list Vagrant will generate and insert a fresh key and discard the key you
    # intended (hashicorp/vagrant#5090).  A list of purely custom keys makes the
    # insertion a no-op, but the pairing is still flagged so the setting is a
    # deliberate choice.  Set insert_key: false to pin the supplied key(s).
    if insert_key
      insecure_present = Array(private_key_path).any? do |key_path|
        key_path.to_s.include?('insecure_private_key')
      end

      if insecure_present
        handle_message(
          "communication.ssh.insert_key is true while private_key_path " \
          "includes the insecure Vagrant key. Vagrant will generate and insert " \
          "a fresh key and discard the supplied key(s) (hashicorp/vagrant#5090). " \
          "Set insert_key: false to use the supplied key(s) as-is.", 'WARNING'
        )
      else
        handle_message(
          "communication.ssh.insert_key is true while a custom private_key_path " \
          "is set. Vagrant may replace the supplied key with a generated one. " \
          "Set insert_key: false to pin the supplied key(s) — recommended on " \
          "FIPS/STIG guests.", 'WARNING'
        )
      end
    end
  end

  # keys_only — only applied when explicitly configured.  Set true on hardened
  # STIG guests to forbid password-based fallback and force key authentication.
  keys_only = lookup_values_yaml(instance_ssh, ['keys_only'])
  unless keys_only.nil?
    machine.ssh.keys_only = validate_value(keys_only)
  end

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
