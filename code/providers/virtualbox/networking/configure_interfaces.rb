#
# Configure network interfaces for a VirtualBox instance.
#
# Fixes applied vs original:
#   - bare `static` constant replaced with the string 'static'
#   - bridge interface intersection check corrected (& operator)
#   - `ip link` parsing cleaned up; .select no-op removed
#   - interface provisioner name variables made local (were globals)
#
def configure_interfaces(
  machine,
  name,
  instance_networking,
  auto_config_default          = true,
  bootproto_default            = 'static',
  bridge_auto_correct_default  = false,
  bridge_interfaces_default    = [],
  ip_addr_ipv4_default         = 'random',
  mtu_ipv4_default             = '1500',
  netmask_ipv4_default         = '255.255.0.0',
  nic_type_default             = 'virtio',
  octets_slash_24_ipv4_default = '172.16.0',
  promiscuous_mode_default     = false,
  provider                     = 'virtualbox',
  virtualbox__intnet_default   = true,
  zone_class_default           = 'private_network',
  valid_zone_classes           = %w[private_network public_network]
)
  base_address = [
    lookup_values_yaml(instance_networking, ['base_address']),
    lookup_values_yaml(instance_networking, ['defaults', 'base_address'])
  ].find { |v| !v.nil? }
  machine.vm.base_address = base_address if base_address

  interfaces_instance = lookup_values_yaml(instance_networking, ['interfaces'])
  return false unless interfaces_instance

  interfaces_instance.each_with_index do |(interface_name, interface_info), idx|
    interface_info  ||= {}
    interface_index   = idx + 2   # NIC index in VirtualBox is 1-based; NIC1 is the NAT adapter

    # ── MAC address ────────────────────────────────────────────────────────────
    # Assign a deterministic MAC address to every additional NIC.  If an
    # explicit mac_addr is set in the YAML, use it.  Otherwise generate one
    # from the instance name and interface index using the VirtualBox OUI
    # (08:00:27).  The same name + index always produces the same MAC,
    # stabilising DHCP leases and NetworkManager connection profiles.
    mac_addr = lookup_values_yaml(interface_info, ['ipv4', 'mac_addr'])

    unless mac_addr
      mac_hash = Digest::MD5.hexdigest("#{name}-mac-#{interface_index}").upcase
      mac_addr = "080027#{mac_hash[0..5]}"
    end

    machine.vm.provider provider do |vbox|
      vbox.customize ['modifyvm', :id, "--macaddress#{interface_index}", mac_addr]
    end

    # ── Promiscuous mode ───────────────────────────────────────────────────────
    promiscuous_mode = [
      lookup_values_yaml(interface_info, ['promiscuous_mode']),
      lookup_values_yaml(instance_networking, ['defaults', 'promiscuous_mode']),
      promiscuous_mode_default
    ].find { |v| !v.nil? }
    validate_value(promiscuous_mode)

    if promiscuous_mode
      machine.vm.provider provider do |vbox|
        vbox.customize ['modifyvm', :id, "--nicpromisc#{interface_index}", 'allow-all']
      end
    end

    # ── Per-interface resolved values ──────────────────────────────────────────
    nic_type = [
      lookup_values_yaml(interface_info, ['nic_type']),
      lookup_values_yaml(instance_networking, ['defaults', 'nic_type']),
      nic_type_default
    ].find { |v| !v.nil? }

    mtu_ipv4 = [
      lookup_values_yaml(interface_info, ['ipv4', 'mtu']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'mtu']),
      mtu_ipv4_default
    ].find { |v| !v.nil? }

    octets_slash_24 = [
      lookup_values_yaml(interface_info, ['ipv4', 'octets_slash_24']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'octets_slash_24']),
      octets_slash_24_ipv4_default
    ].find { |v| !v.nil? }

    ip_addr = [
      lookup_values_yaml(interface_info, ['ipv4', 'ip_addr']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'ip_addr']),
      ip_addr_ipv4_default
    ].find { |v| !v.nil? }

    netmask = [
      lookup_values_yaml(interface_info, ['ipv4', 'netmask']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'netmask']),
      netmask_ipv4_default
    ].find { |v| !v.nil? }

    bootproto = [
      lookup_values_yaml(interface_info, ['ipv4', 'bootproto']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'bootproto']),
      bootproto_default
    ].find { |v| !v.nil? }

    auto_config = [
      lookup_values_yaml(interface_info, ['auto_config']),
      lookup_values_yaml(instance_networking, ['defaults', 'auto_config']),
      auto_config_default
    ].find { |v| !v.nil? }
    validate_value(auto_config)

    zone_class = [
      lookup_values_yaml(interface_info, ['zone_class']),
      lookup_values_yaml(instance_networking, ['defaults', 'zone_class']),
      zone_class_default
    ].find { |v| !v.nil? }
    validate_value(zone_class, valid_zone_classes)

    virtualbox__intnet = [
      lookup_values_yaml(interface_info, ['virtualbox__intnet']),
      lookup_values_yaml(instance_networking, ['defaults', 'virtualbox__intnet']),
      virtualbox__intnet_default
    ].find { |v| !v.nil? }

    network_name = [
      lookup_values_yaml(interface_info, ['network_name']),
      lookup_values_yaml(instance_networking, ['defaults', 'network_name']),
      virtualbox__intnet
    ].find { |v| !v.nil? }

    # ── Resolve ip_addr to a concrete address or mode ─────────────────────────
    case ip_addr
    when Resolv::IPv4::Regex
      # already a static address, nothing to do
    when 'random'
      random_octet = Random.new(Digest::MD5.hexdigest("#{name} #{interface_index}").to_i(16)).rand(40..252)
      ip_addr      = "#{octets_slash_24}.#{random_octet}"
    when 'dhcp'
      bootproto = 'dhcp'
    when 'none'
      bootproto = 'none'
      random_octet = Random.new(Digest::MD5.hexdigest("#{name} #{interface_index}").to_i(16)).rand(40..252)
      ip_addr      = "127.0.0.#{random_octet}"
    when nil
      if interface_info.nil? || interface_info.empty?
        bootproto = bootproto_default
        zone_class = zone_class_default
      end
    else
      exit_with_message("ip_addr value [#{ip_addr}] for interface [#{interface_name}] on instance [#{name}] is not valid.")
    end

    # ── Add the network to Vagrant ─────────────────────────────────────────────
    case zone_class
    when 'public_network'
      # Enumerate host interfaces, excluding loopback
      interfaces_host = `ip -o link show`.scan(/^\d+: ([^:@\s]+)/).flatten.sort
      interfaces_host.delete('lo')

      bridge_interfaces = [
        lookup_values_yaml(interface_info, ['bridging', 'interfaces']),
        lookup_values_yaml(instance_networking, ['defaults', 'bridging', 'interfaces']),
        bridge_interfaces_default
      ].find { |v| !v.nil? }

      bridge_auto_correct = [
        lookup_values_yaml(interface_info, ['bridging', 'auto_correct']),
        lookup_values_yaml(instance_networking, ['defaults', 'bridging', 'auto_correct']),
        bridge_auto_correct_default
      ].find { |v| !v.nil? }
      validate_value(bridge_auto_correct)

      # Check whether any of the specified bridge interfaces exist on the host.
      # Only enforce this for instances that are actively being managed in the
      # current Vagrant invocation — skip silently for inactive instances so
      # that `vagrant up myvm` does not error on bridge config belonging to
      # other VMs that are not being started.
      matching_interfaces = bridge_interfaces & interfaces_host

      if matching_interfaces.empty? && active_machine?(name)
        listed = bridge_interfaces.empty? ? 'NOT_DEFINED' : bridge_interfaces.join(', ')

        if bridge_auto_correct
          handle_message(
            "instance [#{name}] interface [#{interface_name}]: no matching bridge interface " \
            "from [#{listed}] found on host. Auto-correcting to use host interfaces [#{interfaces_host.join(', ')}].",
            'WARNING'
          )
          bridge_interfaces = interfaces_host
        else
          exit_with_message(
            "instance [#{name}] interface [#{interface_name}]: no host bridge interface " \
            "matching [#{listed}] was found. Set auto_correct: true to use all host interfaces automatically."
          )
        end
      end

      case bootproto
      when 'dhcp'
        machine.vm.network zone_class,
          auto_config: auto_config, nic_type: nic_type,
          type: 'dhcp', bridge: bridge_interfaces
      when 'static'
        machine.vm.network zone_class,
          ip: ip_addr, auto_config: auto_config, nic_type: nic_type,
          netmask: netmask, bridge: bridge_interfaces
      when 'none'
        machine.vm.network zone_class,
          auto_config: false, nic_type: nic_type,
          type: 'static', bridge: bridge_interfaces
      end

    when 'private_network'
      case bootproto
      when 'dhcp'
        machine.vm.network zone_class,
          auto_config: auto_config, nic_type: nic_type,
          type: 'dhcp', virtualbox__intnet: virtualbox__intnet, name: network_name
      when 'static'
        machine.vm.network zone_class,
          ip: ip_addr, auto_config: auto_config, nic_type: nic_type,
          virtualbox__intnet: virtualbox__intnet, netmask: netmask, name: network_name
      when 'none'
        machine.vm.network zone_class,
          auto_config: false, nic_type: nic_type,
          virtualbox__intnet: virtualbox__intnet, netmask: netmask, name: network_name
      end
    end

    # ── Bring up interface and set MTU on every boot ───────────────────────────
    # Use 'ip link set up' instead of 'ifup' to avoid triggering NetworkManager
    # to reconfigure all interfaces.  'ifup' is deprecated on RHEL 8, missing
    # on minimal RHEL 9 installs, and will not be present on RHEL 10+.
    if bootproto != 'none'
      link_up_cmd = "sudo ip link set dev #{interface_name} up"
      mtu_cmd     = "sudo ip link set dev #{interface_name} mtu #{mtu_ipv4}"

      machine.vm.provision 'shell', inline: link_up_cmd, name: link_up_cmd, run: 'always'
      machine.vm.provision 'shell', inline: mtu_cmd,     name: mtu_cmd,     run: 'always'
    end
  end
end
