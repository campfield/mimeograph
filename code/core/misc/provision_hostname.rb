#
# provision_hostname.rb
#
# Injects a shell provisioner that explicitly sets the guest hostname via
# hostnamectl (systemd) with a fallback to the legacy hostname command.
#
# This supplements machine.vm.hostname — Vagrant's own hostname management
# is not always reliable on RHEL-based guests and may not persist across
# reboots on all distributions.
#
# The hostname is resolved from the instance profile in the same way as
# machine.vm.hostname: the configured 'hostname' value if present, otherwise
# the sanitised instance name (non-alphanumeric characters stripped).
#
# Controlled by the YAML key providers.<provider>.instance.set_hostname:
#   true  - provision the hostname (default)
#   false - skip; leave hostname management entirely to the guest or other tooling
#
# The provisioner runs once at provision time and is named so it is easy
# to identify in `vagrant provision --list` output.
#
def provision_hostname(machine, instance_profile, provider, set_hostname_default = true)
  box_config = lookup_values_yaml(instance_profile, ['providers', provider])
  name       = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  set_hostname = [
    lookup_values_yaml(box_config, ['instance', 'set_hostname']),
    set_hostname_default
  ].find { |v| !v.nil? }
  validate_value(set_hostname)

  return unless set_hostname

  hostname = [
    lookup_values_yaml(box_config, ['instance', 'hostname']),
    name.gsub(/[^a-z0-9\-]/i, '')
  ].find { |v| !v.nil? }

  script = <<~SHELL
    if command -v hostnamectl >/dev/null 2>&1; then
      hostnamectl set-hostname '#{hostname}'
    else
      hostname '#{hostname}'
      echo '#{hostname}' > /etc/hostname
    fi
  SHELL

  machine.vm.provision 'shell',
    name:       "set-hostname: #{hostname}",
    inline:     script,
    privileged: true,
    run:        'once'
end
