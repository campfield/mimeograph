#
# Configure libvirt instance hardware: CPUs, memory, CPU topology, and display.
#
# YAML keys under providers.libvirt.instance.hardware:
#
#   cpus          - vCPU count (default: 2)
#   memory        - RAM in MB (default: 512)
#   cpu_mode      - 'host-model' (default) | 'host-passthrough' | 'custom'
#   cpu_model     - CPU model name when cpu_mode is 'custom'
#   nested        - enable nested virtualization: true | false (default: false)
#   graphics_type - 'vnc' (default) | 'spice' | 'none'
#   graphics_ip   - IP to bind the display protocol to (default: '127.0.0.1')
#   boot          - boot order: 'hd' (default) | 'network' | 'cdrom'
#
def configure_instance_hardware_libvirt(
  machine,
  instance_profile,
  provider          = 'libvirt',
  cpus_default      = 2,
  memory_default    = 512,
  cpu_mode_default  = 'host-model',
  nested_default    = false,
  graphics_default  = 'vnc',
  graphics_ip_default = '127.0.0.1',
  boot_default      = 'hd'
)
  instance_hardware = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'hardware'])

  machine.vm.provider provider do |lv|
    lv.cpus = [
      lookup_values_yaml(instance_hardware, ['cpus']),
      cpus_default
    ].find { |v| !v.nil? }

    lv.memory = [
      lookup_values_yaml(instance_hardware, ['memory']),
      memory_default
    ].find { |v| !v.nil? }

    lv.cpu_mode = [
      lookup_values_yaml(instance_hardware, ['cpu_mode']),
      cpu_mode_default
    ].find { |v| !v.nil? }

    cpu_model = lookup_values_yaml(instance_hardware, ['cpu_model'])
    lv.cpu_model = cpu_model if cpu_model

    lv.nested = validate_value(
      [
        lookup_values_yaml(instance_hardware, ['nested']),
        nested_default
      ].find { |v| !v.nil? }
    )

    lv.graphics_type = [
      lookup_values_yaml(instance_hardware, ['graphics_type']),
      graphics_default
    ].find { |v| !v.nil? }

    lv.graphics_ip = [
      lookup_values_yaml(instance_hardware, ['graphics_ip']),
      graphics_ip_default
    ].find { |v| !v.nil? }

    lv.boot = [
      lookup_values_yaml(instance_hardware, ['boot']),
      boot_default
    ].find { |v| !v.nil? }

    # Additional disks defined as a list under hardware.disks
    # Each entry: { size: '20G', type: 'qcow2', bus: 'virtio', cache: 'none' }
    additional_disks = lookup_values_yaml(instance_hardware, ['disks'])
    if additional_disks
      additional_disks.each do |disk|
        lv.storage :file,
          size:  disk['size']  || '10G',
          type:  disk['type']  || 'qcow2',
          bus:   disk['bus']   || 'virtio',
          cache: disk['cache'] || 'none'
      end
    end
  end
end
