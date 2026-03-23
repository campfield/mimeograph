#
# Top-level networking handler for libvirt instances.
#
def configure_networking_libvirt(machine, instance_profile, provider = 'libvirt')
  instance_networking = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'networking'])
  return false unless instance_networking

  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  configure_interfaces_libvirt(machine, name, instance_networking, provider)
  configure_forwarded_ports(machine, name, instance_networking)
end

#
# Configure network interfaces for a libvirt instance.
#
# libvirt networking differs from VirtualBox in key ways:
#   - libvirt manages its own network bridge creation; no host bridge enumeration needed
#   - 'private_network' creates/uses a NAT or isolated libvirt network
#   - 'public_network' bridges directly to a host device via macvtap (no bridge required)
#   - management network (vagrant-libvirt) is always added automatically as the first NIC
#
# YAML keys per interface (under networking.interfaces.<name>):
#   zone_class        - 'private_network' (default) | 'public_network'
#   ip_addr           - static IPv4 | 'dhcp' | 'random' | 'none'
#   network_name      - libvirt network name for private_network (default: 'vagrant-libvirt')
#   netmask           - subnet mask for static addresses (default: '255.255.0.0')
#   octets_slash_24   - first three octets for random IP generation (default: '172.16.0')
#   dev               - host device name for public_network (macvtap bridge)
#   dhcp_enabled      - enable DHCP on newly created private networks (default: true)
#   forward_mode      - 'nat' (default) | 'route' | 'none' — for new private networks
#
def configure_interfaces_libvirt(
  machine,
  name,
  instance_networking,
  provider                     = 'libvirt',
  ip_addr_default              = 'random',
  mtu_ipv4_default             = '1500',
  netmask_default              = '255.255.0.0',
  octets_slash_24_default      = '172.16.0',
  zone_class_default           = 'private_network',
  valid_zone_classes           = %w[private_network public_network],
  forward_mode_default         = 'nat',
  dhcp_enabled_default         = true
)
  interfaces_instance = lookup_values_yaml(instance_networking, ['interfaces'])
  return false unless interfaces_instance

  interfaces_instance.each_with_index do |(interface_name, interface_info), idx|
    interface_info  ||= {}
    interface_index   = idx + 2   # NIC 1 is the management network

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

    # Resolve ip_addr to a concrete value
    case ip_addr
    when Resolv::IPv4::Regex
      # already a static address
    when 'random'
      random_octet = Random.new(Digest::MD5.hexdigest("#{name} #{interface_index}").to_i(16)).rand(40..252)
      ip_addr      = "#{octets_slash_24}.#{random_octet}"
    when 'dhcp', 'none'
      # handled below per zone_class
    when nil
      # no ip specified — fall through to zone_class defaults
    else
      exit_with_message("ip_addr value [#{ip_addr}] for interface [#{interface_name}] on instance [#{name}] is not valid.")
    end

    case zone_class
    when 'private_network'
      auto_config = [
        lookup_values_yaml(interface_info, ['auto_config']),
        lookup_values_yaml(instance_networking, ['defaults', 'auto_config']),
        true
      ].find { |v| !v.nil? }
      validate_value(auto_config)

      network_name = [
        lookup_values_yaml(interface_info, ['network_name']),
        lookup_values_yaml(instance_networking, ['defaults', 'network_name']),
        'vagrant-libvirt'
      ].find { |v| !v.nil? }

      forward_mode = [
        lookup_values_yaml(interface_info, ['forward_mode']),
        lookup_values_yaml(instance_networking, ['defaults', 'forward_mode']),
        forward_mode_default
      ].find { |v| !v.nil? }

      dhcp_enabled = [
        lookup_values_yaml(interface_info, ['dhcp_enabled']),
        lookup_values_yaml(instance_networking, ['defaults', 'dhcp_enabled']),
        dhcp_enabled_default
      ].find { |v| !v.nil? }

      if ip_addr == 'dhcp' || ip_addr.nil?
        machine.vm.network zone_class,
          auto_config:          auto_config,
          libvirt__network_name: network_name,
          libvirt__forward_mode: forward_mode,
          libvirt__dhcp_enabled: dhcp_enabled
      elsif ip_addr == 'none'
        # interface created but not configured — skip network call
      else
        machine.vm.network zone_class,
          ip:                    ip_addr,
          auto_config:           auto_config,
          libvirt__netmask:      netmask,
          libvirt__network_name: network_name,
          libvirt__forward_mode: forward_mode,
          libvirt__dhcp_enabled: dhcp_enabled
      end

    when 'public_network'
      # public_network on libvirt uses macvtap — requires host device name, no bridge needed.
      # Only enforce the 'dev' requirement for instances being actively managed so that
      # `vagrant up myvm` does not error on public_network config in other inactive VMs.
      dev = [
        lookup_values_yaml(interface_info, ['dev']),
        lookup_values_yaml(instance_networking, ['defaults', 'dev'])
      ].find { |v| !v.nil? }

      if dev.nil?
        if active_machine?(name)
          exit_with_message(
            "instance [#{name}] interface [#{interface_name}]: 'dev' is required for libvirt public_network interfaces."
          )
        else
          next
        end
      end

      if ip_addr == 'dhcp' || ip_addr.nil?
        machine.vm.network zone_class, dev: dev, type: 'dhcp'
      elsif ip_addr == 'none'
        # skip
      else
        machine.vm.network zone_class, dev: dev, ip: ip_addr, netmask: netmask
      end
    end

    # ── Bring up interface and set MTU on every boot ───────────────────────────
    # Skip for 'none' interfaces (not brought up by design).
    unless ip_addr == 'none'
      mtu_ipv4 = [
        lookup_values_yaml(interface_info, ['ipv4', 'mtu']),
        lookup_values_yaml(instance_networking, ['defaults', 'ipv4', 'mtu']),
        mtu_ipv4_default
      ].find { |v| !v.nil? }

      ifup_cmd = "sudo ifup #{interface_name}"
      mtu_cmd  = "sudo ip link set dev #{interface_name} mtu #{mtu_ipv4}"

      machine.vm.provision 'shell', inline: ifup_cmd, name: ifup_cmd, run: 'always'
      machine.vm.provision 'shell', inline: mtu_cmd,  name: mtu_cmd,  run: 'always'
    end
  end
end
