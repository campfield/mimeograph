#
# Provision guest commands defined under providers.<provider>.instance.commands.system.
#
# Each command entry supports:
#   text:       the inline command string or path to a host-side script
#   type:       inline | path  (default: inline)
#   call_count: once | always | never  (default: once)
#   privileged: true | false  (default: true)
#   method:     shell  (only supported value; reserved for future provisioner types)
#
def execute_system_commands(
  machine,
  instance_profile,
  provider,
  call_count_default  = 'once',
  call_counts         = %w[always never once],
  command_type_default = 'inline',
  privileged_default  = true
)
  commands = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'commands', 'system'])
  return unless commands

  commands.each do |command_name, command_info|
    command_info ||= {}

    command_text = [
      lookup_values_yaml(command_info, ['text']),
      command_name
    ].find { |v| !v.nil? }

    command_type = [
      lookup_values_yaml(command_info, ['type']),
      lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'commands', 'defaults', 'system', 'type']),
      command_type_default
    ].find { |v| !v.nil? }
    validate_value(command_type, %w[inline path])

    privileged = [
      lookup_values_yaml(command_info, ['privileged']),
      lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'commands', 'defaults', 'system', 'privileged']),
      privileged_default
    ].find { |v| !v.nil? }
    validate_value(privileged)

    call_count = [
      lookup_values_yaml(command_info, ['call_count']),
      lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'commands', 'defaults', 'system', 'call_count']),
      call_count_default
    ].find { |v| !v.nil? }
    validate_value(call_count, call_counts)

    next if call_count == 'never'

    provision_name = "[#{command_name}] type:[#{command_type}] run:[#{call_count}]"

    case command_type
    when 'inline'
      machine.vm.provision 'shell',
        inline:     command_text,
        name:       provision_name,
        run:        call_count,
        privileged: privileged
    when 'path'
      machine.vm.provision 'shell',
        path:       command_text,
        name:       provision_name,
        run:        call_count,
        privileged: privileged
    end
  end
end
