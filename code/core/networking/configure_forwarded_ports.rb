#
# Configure host-to-guest forwarded ports.
#
def configure_forwarded_ports(
  machine,
  name,
  instance_networking,
  auto_correct_default = true,
  protocol_default     = 'tcp',
  valid_protocols      = %w[tcp udp]
)
  forwarded_ports = lookup_values_yaml(instance_networking, ['forwarded_ports'])
  return false unless forwarded_ports

  forwarded_ports.each do |port_name, port_info|
    port_info ||= {}

    instance_port = lookup_values_yaml(port_info, ['instance_port'])
    exit_with_message("forwarded_port [#{port_name}] is missing required value [instance_port].") unless instance_port

    # Generate a deterministic host port if not specified
    host_port = [
      lookup_values_yaml(port_info, ['host_port']),
      Random.new(Digest::MD5.hexdigest("#{name}-#{port_name}").to_i(16)).rand(2000..9999)
    ].find { |v| !v.nil? }

    protocol = [
      lookup_values_yaml(port_info, ['protocol']),
      lookup_values_yaml(instance_networking, ['defaults', 'forwarded_ports', 'protocol']),
      protocol_default
    ].find { |v| !v.nil? }
    validate_value(protocol, valid_protocols)

    auto_correct = [
      lookup_values_yaml(port_info, ['auto_correct']),
      lookup_values_yaml(instance_networking, ['defaults', 'forwarded_ports', 'auto_correct']),
      auto_correct_default
    ].find { |v| !v.nil? }
    validate_value(auto_correct)

    machine.vm.network 'forwarded_port',
      id:           port_name,
      guest:        instance_port.to_i,
      host:         host_port.to_i,
      auto_correct: auto_correct,
      protocol:     protocol
  end
end
