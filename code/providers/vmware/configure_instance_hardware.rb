#
# Configure VMware Desktop instance hardware: CPUs, memory, and VMX settings.
#
# VMX customization is applied as the final step before the VM boots.
# Keys and values are passed directly as a hash under hardware.vmx.
# Common VMX keys:
#   memsize        - RAM in MB (as string, e.g. "2048")
#   numvcpus       - vCPU count (as string, e.g. "4")
#   displayname    - VM display name in the VMware UI
#   cpuid.coresPerSocket - cores per socket
#
# Note: mimeograph sets cpus and memory via the provider API first, then applies
# any additional vmx overrides. If both are set, vmx takes precedence for the
# underlying .vmx file values.
#
def configure_instance_hardware_vmware(
  machine,
  instance_profile,
  provider       = 'vmware',
  cpus_default   = 2,
  memory_default = 512
)
  instance_hardware = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'hardware'])

  machine.vm.provider VMWARE_PROVIDER_NAME do |vmw|
    cpus = [
      lookup_values_yaml(instance_hardware, ['cpus']),
      cpus_default
    ].find { |v| !v.nil? }

    memory = [
      lookup_values_yaml(instance_hardware, ['memory']),
      memory_default
    ].find { |v| !v.nil? }

    # Set via VMX — this is the canonical way for vagrant-vmware-desktop
    vmw.vmx['numvcpus'] = cpus.to_s
    vmw.vmx['memsize']  = memory.to_s

    # Additional VMX key/value pairs from YAML
    vmx_extra = lookup_values_yaml(instance_hardware, ['vmx'])
    if vmx_extra
      vmx_extra.each do |key, value|
        if value.nil?
          # nil removes the key from the VMX file
          vmw.vmx.delete(key.to_s)
        else
          vmw.vmx[key.to_s] = value.to_s
        end
      end
    end
  end
end
