#
# Function for managing host-to-guest forwarded ports.
#
def configure_forwarded_ports(
  machine,
  name,
  instance_networking,
  forward_port_auto_correct_default = true,
  forward_port_protocol_default = 'tcp',
  forward_port_protocols = [
    'tcp',
    'udp',
    'icmp'
  ]
)

  forwarded_ports = lookup_values_yaml(instance_networking, ['forwarded_ports'])

  return false unless forwarded_ports

  forwarded_ports.each do |forward_port_name, forward_port_info|

    instance_port = lookup_values_yaml(forward_port_info, ['instance_port'])
    exit_with_message("forward port [#{forward_port_name}] missing value [instance_port]") unless instance_port

    host_port = [
      lookup_values_yaml(forward_port_info, ['host_port']),
      Random.new(Digest::MD5.hexdigest(name).to_i(16)).rand(2000..9999)
    ].find { |i| !i.nil? }

    forward_port_protocol = [
      lookup_values_yaml(forward_port_info, ['protocol']),
      lookup_values_yaml(instance_networking, ['defaults', 'forward_ports', 'protocol']),
      forward_port_protocol_default
    ].find { |i| !i.nil? }
    validate_value(forward_port_protocol, forward_port_protocols)

    forward_port_auto_correct = [
      lookup_values_yaml(forward_port_info, ['auto_correct']),
      lookup_values_yaml(instance_networking, ['defaults', 'forward_ports', 'auto_correct']),
      forward_port_auto_correct_default
    ].find { |i| !i.nil? }
    validate_value(forward_port_auto_correct)

    machine.vm.network 'forwarded_port', id: forward_port_name, guest: instance_port.to_s, host: host_port.to_s, auto_correct: forward_port_auto_correct, protocol: forward_port_protocol

  end
end
