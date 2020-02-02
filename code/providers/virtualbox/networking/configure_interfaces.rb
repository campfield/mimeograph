#
# Configure network interfaces for VirtualBox.
#
def configure_interfaces(
  machine,
  name,
  instance_networking,
  auto_config_default = true,
  bootproto_default = 'static',
  bridge_auto_correct_default = false,
  bridge_interfaces_default = [],
  ip_addr_ipv4_default = 'random',
  mtu_ipv4_default = '1500',
  netmask_ipv4_default = '255.255.0.0',
  network_name_default = nil,
  nic_type_default = 'virtio',
  octets_slash_24_ipv4_default = '172.16.0',
  promiscuous_mode_default = false,
  provider = 'virtualbox',
  virtualbox__intnet_default = true,
  zone_class_default = 'private_network',
  zone_classes = [
    'private_network',
    'public_network'
  ]
)

  base_address = [
    lookup_values_yaml(instance_networking, ['base_address']),
    lookup_values_yaml(instance_networking, ['defaults', 'base_address'])
  ].find { |i| !i.nil? }

  machine.vm.base_address = base_address if base_address

  interfaces_instance = lookup_values_yaml(instance_networking, ['interfaces'])

  return false unless interfaces_instance

  interfaces_instance.each.with_index(1) do |(interface_name, interface_info), index|

    interface_index = index + 1

    nic_type = [
      lookup_values_yaml(interface_info, ['nic_type']),
      lookup_values_yaml(instance_networking, ['defaults', 'nic_type']),
      nic_type_default
    ].find { |i| !i.nil? }

    mtu_ipv4 = [
      lookup_values_yaml(interface_info, ['ipv4', 'mtu']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'mtu']),
      mtu_ipv4_default
    ].find { |i| !i.nil? }

    mac_addr_ipv4 = lookup_values_yaml(interface_info, ['ipv4', 'mac_addr'])
    if mac_addr_ipv4
      machine.vm.provider provider do |vbox|
        vbox.customize ['modifyvm', :id, "--macaddress#{interface_index}", mac_addr_ipv4]
      end
    end

    promiscuous_mode = [
      lookup_values_yaml(interface_info, ['promiscuous_mode']),
      lookup_values_yaml(instance_networking, ['defaults', 'promiscuous_mode']),
      promiscuous_mode_default
    ].find { |i| !i.nil? }
    validate_value(promiscuous_mode)

    if promiscuous_mode
      machine.vm.provider provider do |vbox|
        vbox.customize ['modifyvm', :id, "--nicpromisc#{interface_index}", 'allow-all']
      end
    end

    octets_slash_24_ipv4 = [
      lookup_values_yaml(interface_info, ['ipv4', 'octets_slash_24']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'octets_slash_24']),
      octets_slash_24_ipv4_default
    ].find { |i| !i.nil? }

    ip_addr_ipv4 = [
      lookup_values_yaml(interface_info, ['ipv4', 'ip_addr']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'ip_addr']),
      ip_addr_ipv4_default
    ].find { |i| !i.nil? }

    auto_config = [
      lookup_values_yaml(interface_info, ['auto_config']),
      lookup_values_yaml(instance_networking, ['defaults', 'auto_config']),
      auto_config_default
    ].find { |i| !i.nil? }
    validate_value(auto_config)

    zone_class = [
      lookup_values_yaml(interface_info, ['zone_class']),
      lookup_values_yaml(instance_networking, ['defaults', 'zone_class']),
      zone_class_default
    ].find { |i| !i.nil? }
    validate_value(zone_class, zone_classes)

    virtualbox__intnet = [
      lookup_values_yaml(interface_info, ['virtualbox__intnet']),
      lookup_values_yaml(instance_networking, ['defaults', 'virtualbox__intnet']),
      virtualbox__intnet_default
    ].find { |i| !i.nil? }

    netmask_ipv4 = [
      lookup_values_yaml(interface_info, ['ipv4', 'netmask']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'netmask']),
      netmask_ipv4_default
    ].find { |i| !i.nil? }

    bootproto = [
      lookup_values_yaml(interface_info, ['ipv4', 'bootproto']),
      lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'bootproto']),
      bootproto_default
    ].find { |i| !i.nil? }

    network_name = [
      lookup_values_yaml(interface_info, ['network_name']),
      lookup_values_yaml(instance_networking, ['defaults', 'network_name']),
      virtualbox__intnet
    ].find { |i| !i.nil? }

    if ip_addr_ipv4
      case ip_addr_ipv4
      when Resolv::IPv4::Regex
        # do nothing
      when 'random'
        name_hash = Random.new(Digest::MD5.hexdigest("#{name} #{interface_index}").to_i(16)).rand(40..252)
        ip_addr_ipv4 = "#{octets_slash_24_ipv4}." + name_hash.to_s
      when 'dhcp'
        bootproto = 'dhcp'
      when 'none'
        bootproto = 'none'
        name_hash = Random.new(Digest::MD5.hexdigest("#{name} #{interface_index}").to_i(16)).rand(40..252)
        ip_addr_ipv4 = '127.0.0.' + name_hash.to_s
      else
        exit_with_message("ip_addr_ipv4 [#{ip_addr_ipv4}] value invalid.")
      end
    elsif interface_info.nil? || interface_info.empty?
      bootproto = bootproto_default
      zone_class = zone_class_default
    end

    case zone_class
    when 'public_network'
      interfaces_host = `ip link sh`.scan(/^\d+: (.*):/).flatten.select.sort
      interfaces_host.delete('lo')

      bridge_interfaces = [
        lookup_values_yaml(interface_info, ['bridging', 'interfaces']),
        lookup_values_yaml(instance_networking, ['defaults', 'bridging', 'interfaces']),
        bridge_interfaces_default
      ].find { |i| !i.nil? }

      bridge_auto_correct = [
        lookup_values_yaml(interface_info, ['bridging', 'auto_correct']),
        lookup_values_yaml(instance_networking, ['defaults', 'bridging', 'auto_correct']),
        bridge_auto_correct_default
      ].find { |i| !i.nil? }
      validate_value(bridge_auto_correct)

      if !bridge_interfaces.include?(interfaces_host)
        bridge_interfaces_joined = bridge_interfaces.join(', ')
        if bridge_interfaces.empty? or bridge_interfaces.nil?
          bridge_interfaces_joined = "NOT_DEFINED"
        end

        if bridge_auto_correct == true
          interfaces_host_joined = interfaces_host.join(', ')
          handle_message("instance [#{name}] no host bridge interface matching specified [#{bridge_interfaces_joined}] interface [#{interface_name}], autocorrecting to use host interfaces [#{interfaces_host_joined}].", "WARNING")
          bridge_interfaces = interfaces_host
        else
          if bridge_interfaces_joined
            exit_with_message("instance [#{name}] no host bridge interface(s) matching specified [#{bridge_interfaces_joined}] were specified for interface [#{interface_name}].  Setting bridges to auto_correct to 'true' will attempt to utilize system interfaces.")
          else
            exit_with_message("instance [#{name}] no host bridge interface(s) were specified interface [#{interface_name}].  Setting bridges to auto_correct to 'true' will attempt to utilize system interfaces.")
          end
        end
      end

      case bootproto
      when 'dhcp'
        machine.vm.network zone_class, auto_config: auto_config, nic_type: nic_type, type: bootproto, bridge: bridge_interfaces
      when 'static'
        machine.vm.network zone_class, ip: ip_addr_ipv4, auto_config: auto_config, nic_type: nic_type, netmask: netmask_ipv4, bridge: bridge_interfaces
      when 'none'
        machine.vm.network zone_class, auto_config: false, nic_type: nic_type, type: static, bridge: bridge_interfaces
      end
    when 'private_network'
      case bootproto
      when 'dhcp'
        machine.vm.network zone_class, auto_config: auto_config, virtualbox__intnet: virtualbox__intnet, nic_type: nic_type, type: bootproto, name: network_name
      when 'static'
        machine.vm.network zone_class, ip: ip_addr_ipv4, auto_config: auto_config, nic_type: nic_type, virtualbox__intnet: virtualbox__intnet, netmask: netmask_ipv4
      when 'none'
        machine.vm.network zone_class, auto_config: false, nic_type: nic_type, virtualbox__intnet: virtualbox__intnet, netmask: netmask_ipv4
      end
    else
      exit_with_message("zone_class [#{zone_class}] value invalid.")
    end

    if bootproto != 'none'
      $interface_ifup_command = "sudo ifup #{interface_name}"
      machine.vm.provision 'shell', inline: $interface_ifup_command, name: $interface_ifup_command, run: 'always'

      $interface_mtu_set_command = "sudo ip link set dev #{interface_name} mtu #{mtu_ipv4}"
      machine.vm.provision 'shell', inline: $interface_mtu_set_command, name: $interface_mtu_set_command, run: 'always'
    end

  end
end
