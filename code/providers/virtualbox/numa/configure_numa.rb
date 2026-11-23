#
# Pin a VirtualBox instance's VM process to a host NUMA node.
#
# host_numa is a host-side placement setting: it controls where the VM process
# runs on the host, not the NUMA topology the guest sees. It resolves through
# the normal hierarchy (hardcoded fallback -> global defaults -> group
# defaults -> instance), so it can be enabled globally and overridden per
# group or per instance.
#
#   providers:
#     virtualbox:
#       instance:
#         host_numa:
#           enabled: true                  # true/false, on/off, yes/no
#           node: auto                     # auto | <node number>
#           policy: balanced               # balanced | memory
#           reserve_mb: 4096               # RAM kept free per node for the host
#           script: tools/vbox-numa-bind   # relative to the project root, or absolute
#
# Two host-side triggers are added to the machine:
#   before up/reload/resume  - starts a background watcher that pins the VM
#                              process as soon as it appears, before the guest
#                              allocates its RAM (this is what places memory)
#   after  up/reload/resume  - confirms the placement once the VM is running
#
# The VM is matched by the UUID in Vagrant's machine id file, so VirtualBox
# display naming and linked clones don't affect matching. Triggers use
# t.run (path + args) rather than Ruby blocks, so they serialize cleanly in
# the static Vagrantfile compiler.
#
def configure_numa(
  machine,
  instance_profile,
  provider           = 'virtualbox',
  enabled_default    = false,
  node_default       = 'auto',
  policy_default     = 'balanced',
  reserve_mb_default = 4096,
  script_default     = 'tools/vbox-numa-bind'
)

  host_numa = lookup_values_yaml(instance_profile, ['providers', provider, 'instance', 'host_numa'])
  return false unless host_numa.is_a?(Hash)

  enabled = [lookup_values_yaml(host_numa, ['enabled']), enabled_default].find { |v| !v.nil? }
  return false unless parse_boolean(enabled) == true
  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  node = [lookup_values_yaml(host_numa, ['node']), node_default].find { |v| !v.nil? }.to_s.strip.downcase
  unless node == 'auto' || node.match?(/\A\d+\z/)
    handle_message("host_numa node [#{node}] for [#{name}] must be 'auto' or a node number; using auto.", 'WARNING')
    node = 'auto'
  end

  policy = [lookup_values_yaml(host_numa, ['policy']), policy_default].find { |v| !v.nil? }.to_s.strip.downcase
  unless %w[balanced memory].include?(policy)
    handle_message("host_numa policy [#{policy}] for [#{name}] must be 'balanced' or 'memory'; using #{policy_default}.", 'WARNING')
    policy = policy_default
  end

  reserve_mb = [lookup_values_yaml(host_numa, ['reserve_mb']), reserve_mb_default].find { |v| !v.nil? }.to_s.strip
  unless reserve_mb.match?(/\A\d+\z/)
    handle_message("host_numa reserve_mb [#{reserve_mb}] for [#{name}] must be a whole number; using #{reserve_mb_default}.", 'WARNING')
    reserve_mb = reserve_mb_default.to_s
  end

  # code/providers/virtualbox/numa -> project root
  project_root = File.expand_path('../../../..', __dir__)

  script = [lookup_values_yaml(host_numa, ['script']), script_default].find { |v| !v.nil? }.to_s
  script = File.expand_path(script, project_root)
  unless File.executable?(script)
    handle_message("host_numa script [#{script}] is missing or not executable; [#{name}] will not be pinned.", 'WARNING')
    return false
  end

  # Vagrant writes the VirtualBox UUID here after import. On a first 'vagrant up'
  # the file doesn't exist yet when the before trigger fires; the script waits.
  dotfile_path = ENV['VAGRANT_DOTFILE_PATH'] || '.vagrant'
  id_file = File.expand_path(File.join(dotfile_path, 'machines', name, provider, 'id'), project_root)

  args = ['--id-file', id_file, '--policy', policy, '--reserve-mb', reserve_mb]
  args += ['--node', node] unless node == 'auto'

  machine.trigger.before :up, :reload, :resume do |t|
    t.name     = 'host NUMA watch'
    t.on_error = :continue
    t.run      = { path: script, args: ['--watch'] + args }
  end

  machine.trigger.after :up, :reload, :resume do |t|
    t.name     = 'host NUMA bind'
    t.on_error = :continue
    t.run      = { path: script, args: args }
  end

  true
end