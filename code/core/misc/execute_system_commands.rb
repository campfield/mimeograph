#
# Execute various systems commands (inline, script based) over a set number of times (always, never, once) on the guest.
#
def execute_system_commands(
  machine,
  instance_profile,
  provider,
  call_count_default = 'once',
  call_counts = [
    'always',
    'never',
    'once'
  ],
  command_method_default = 'shell',
  command_methods = ['shell'],
  command_type_default = 'inline',
  execute_location = 'instance',
  execute_locations = [
    'host',
    'instance'
  ],
  privileged_default = true
)

  commands = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'commands', 'system'])

  return unless commands

  commands.each.with_index(1) do |(command_name, command_info), index|

    command_text = [
      lookup_values_yaml(command_info, ['text']),
      command_name
    ].find { |i| !i.nil? }

    command_type = [
      lookup_values_yaml(command_info, ['type']),
      lookup_values_yaml(command_info, ['defaults', 'system', 'type']),
      command_type_default
    ].find { |i| !i.nil? }
    validate_value(command_type, ['inline', 'path'])

    privileged = [
      lookup_values_yaml(command_info, ['privileged']),
      lookup_values_yaml(command_info, ['defaults', 'system', 'privileged']),
      privileged_default
    ].find { |i| !i.nil? }
    validate_value(privileged)

    command_method = [
      lookup_values_yaml(command_info, ['method']),
      lookup_values_yaml(command_info, ['defaults', 'system', 'method']),
      command_method_default
    ].find { |i| !i.nil? }
    validate_value(command_method, command_methods)

    call_count = [
      lookup_values_yaml(command_info, ['call_count']),
      lookup_values_yaml(command_info, ['defaults', 'system', 'call_count']),
      call_count_default
    ].find { |i| !i.nil? }
    validate_value(call_count, call_counts)

    execute_location = [
      lookup_values_yaml(command_info, ['execute_location']),
      lookup_values_yaml(command_info, ['defaults', 'system', 'execute_location']),
      execute_location
    ].find { |i| !i.nil? }
    validate_value(execute_location, execute_locations)

    next if call_count == 'never'

    exit_with_message("system command run location [#{execute_location}] is not currently an implemented feature.") unless execute_location == 'instance'

    case command_type
    when 'inline'
      machine.vm.provision command_method, inline: command_text, name: "title: [#{command_name}] command: [#{command_text}] type: [#{command_type}] run: [#{call_count}]", run: call_count, privileged: privileged
    when 'path'
      machine.vm.provision command_method, path: command_text, name: "title: [#{command_name}] command: [#{command_text}] type: [#{command_type}] run: [#{call_count}]", run: call_count, privileged: privileged
    end

  end
end
