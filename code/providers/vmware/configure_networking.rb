#
# Top-level networking handler for VMware Desktop instances.
#
def configure_networking_vmware(machine, instance_profile, provider = 'vmware')
  instance_networking = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'networking'])
  return false unless instance_networking

  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  configure_interfaces_vmware(machine, name, instance_networking)
  configure_forwarded_ports(machine, name, instance_networking)
end

#
# Configure network interfaces for a VMware Desktop instance.
#
# VMware networking notes:
#   - The first NIC is always the NAT adapter managed by Vagrant/VMware; it is not configured here.
#   - 'private_network' maps to a host-only VMnet adapter.
#   - 'public_network' maps to a bridged adapter.
#   - VMware does not use VirtualBox-specific options (intnet, nic_type, etc.).
#   - Random and static IP assignment work identically to the VirtualBox provider.
#
def configure_interfaces_vmware(
  machine,
  name,
  instance_networking,
  ip_addr_default         = 'random',
  netmask_default         = '255.255.0.0',
  octets_slash_24_default = '172.16.0',
  zone_class_default      = 'private_network',
  valid_zone_classes      = %w[private_network public_network]
)
  interfaces_instance = lookup_values_yaml(instance_networking, ['interfaces'])
  return false unless interfaces_instance

  interfaces_instance.each_with_index do |(interface_name, interface_info), idx|
    interface_info  ||= {}
    interface_index   = idx + 2

    zone_class = [
      lookup_values_yaml(interface_info, ['zone_class']),
      lookup_values_yaml(instance_networking, ['defaults', 'zone_class']),
      zone_class_default
    ].find { |v| !v.nil? }
    validate_value(zone_class, valid_zone_classes)

    octets_slash_24 = [
      lookup_values_yaml(interface_info, ['ipv4', 'octets_slash_24']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'octets_slash_24']),
      octets_slash_24_default
    ].find { |v| !v.nil? }

    ip_addr = [
      lookup_values_yaml(interface_info, ['ipv4', 'ip_addr']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'ip_addr']),
      ip_addr_default
    ].find { |v| !v.nil? }

    netmask = [
      lookup_values_yaml(interface_info, ['ipv4', 'netmask']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'netmask']),
      netmask_default
    ].find { |v| !v.nil? }

    # Resolve ip_addr
    case ip_addr
    when Resolv::IPv4::Regex
      # static address, use as-is
    when 'random'
      random_octet = Random.new(Digest::MD5.hexdigest("#{name} #{interface_index}").to_i(16)).rand(40..252)
      ip_addr      = "#{octets_slash_24}.#{random_octet}"
    when 'dhcp'
      ip_addr = nil   # Vagrant uses type: 'dhcp' rather than an IP
    when 'none'
      next            # skip this interface entirely
    when nil
      # no ip — fall through
    else
      exit_with_message("ip_addr value [#{ip_addr}] for interface [#{interface_name}] on instance [#{name}] is not valid.")
    end

    auto_config = [
      lookup_values_yaml(interface_info, ['auto_config']),
      lookup_values_yaml(instance_networking, ['defaults', 'auto_config']),
      true
    ].find { |v| !v.nil? }
    validate_value(auto_config)

    case zone_class
    when 'private_network'
      if ip_addr
        machine.vm.network zone_class, ip: ip_addr, netmask: netmask, auto_config: auto_config
      else
        machine.vm.network zone_class, type: 'dhcp', auto_config: auto_config
      end

    when 'public_network'
      # Bridged adapter — VMware auto-selects bridge device unless specified
      bridge = lookup_values_yaml(interface_info, ['bridge'])
      if ip_addr
        opts = { ip: ip_addr, netmask: netmask, auto_config: auto_config }
        opts[:bridge] = bridge if bridge
        machine.vm.network zone_class, **opts
      else
        opts = { type: 'dhcp', auto_config: auto_config }
        opts[:bridge] = bridge if bridge
        machine.vm.network zone_class, **opts
      end
    end

    # Bring up interface and set MTU on every boot.
    # Use 'ip link set up' instead of 'ifup' to avoid triggering NetworkManager
    # to reconfigure all interfaces.  'ifup' is deprecated on RHEL 8, missing
    # on minimal RHEL 9 installs, and will not be present on RHEL 10+.
    link_up_cmd = "sudo ip link set dev #{interface_name} up"
    mtu_ipv4 = lookup_values_yaml(interface_info, ['ipv4', 'mtu']) ||
               lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'mtu']) ||
               '1500'
    mtu_cmd = "sudo ip link set dev #{interface_name} mtu #{mtu_ipv4}"

    machine.vm.provision 'shell', inline: link_up_cmd, name: link_up_cmd, run: 'always'
    machine.vm.provision 'shell', inline: mtu_cmd,     name: mtu_cmd,     run: 'always'
  end
end
