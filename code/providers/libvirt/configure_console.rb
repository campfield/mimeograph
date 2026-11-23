#
# Open a graphical console for a libvirt instance when it is brought up.
#
# libvirt has no VirtualBox-style 'gui' window of its own: the console is
# whatever viewer attaches to the VM's display (hardware.graphics_type).
# Setting communication.display.gui makes mimeograph start one for you:
#
#   providers:
#     libvirt:
#       instance:
#         communication:
#           display:
#             gui: true                     # true/false, on/off, yes/no (default false)
#             viewer: 'virt-viewer'         # 'virt-viewer' | 'virt-manager'
#             uri: ~                        # libvirt URI the viewer connects to
#             wait_seconds: 300             # virt-viewer: how long to wait for the VM
#             script: 'tools/libvirt-console'  # relative to the project root, or absolute
#
# viewer
#   virt-viewer   console window only.  Started from a 'before up' trigger with
#                 --wait --reconnect, so it shows the whole boot (firmware,
#                 bootloader, kernel) and reattaches across guest reboots.
#   virt-manager  the virt-manager window on the VM's console
#                 (--show-domain-console).  The VM must exist first, so it is
#                 opened from an 'after up' trigger, once the VM has booted.
#
# uri (when not set)
#   instance uri, if set; else qemu+ssh://<username>@<host>/system when a
#   remote libvirt host is configured; else qemu:///session when
#   qemu_use_session is true; else qemu:///system.
#
# The viewer runs on the host that runs 'vagrant up', detached, so Vagrant
# never waits for the window.  tools/libvirt-console decides where a window
# can go: a local desktop session, an SSH session with X forwarding (the
# window appears on your desktop), or, for an SSH session without X
# forwarding, nothing is opened and the commands to get the console are
# printed instead.  A display problem never fails 'vagrant up'.
#
# The VM is matched by the libvirt domain UUID that vagrant-libvirt writes to
# .vagrant/machines/<name>/libvirt/id, so the domain name prefix does not
# matter.  Triggers use t.run (path + args) rather than Ruby blocks, so they
# serialize cleanly in the static Vagrantfile compiler.
#
def configure_console_libvirt(
  machine,
  instance_profile,
  provider             = 'libvirt',
  gui_default          = false,
  viewer_default       = 'virt-viewer',
  wait_seconds_default = 300,
  script_default       = 'tools/libvirt-console',
  valid_viewers        = %w[virt-viewer virt-manager]
)
  instance = lookup_values_yaml(instance_profile, ['providers', provider, 'instance'])
  display  = lookup_values_yaml(instance, ['communication', 'display'])
  return false unless display.is_a?(Hash)

  gui = [lookup_values_yaml(display, ['gui']), gui_default].find { |v| !v.nil? }
  return false unless parse_boolean(gui) == true

  name = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))

  graphics_type = lookup_values_yaml(instance, ['hardware', 'graphics_type']).to_s.strip.downcase
  if graphics_type == 'none'
    handle_message("communication.display.gui is on for [#{name}] but hardware.graphics_type is 'none': there is no display to open; set graphics_type to 'vnc' or 'spice'.", 'WARNING')
    return false
  end

  viewer = [lookup_values_yaml(display, ['viewer']), viewer_default].find { |v| !v.nil? }.to_s.strip.downcase
  unless valid_viewers.include?(viewer)
    handle_message("display viewer [#{viewer}] for [#{name}] must be one of #{valid_viewers.inspect}; using #{viewer_default}.", 'WARNING')
    viewer = viewer_default
  end

  wait_seconds = [lookup_values_yaml(display, ['wait_seconds']), wait_seconds_default].find { |v| !v.nil? }.to_s.strip
  unless wait_seconds.match?(/\A\d+\z/)
    handle_message("display wait_seconds [#{wait_seconds}] for [#{name}] must be a whole number; using #{wait_seconds_default}.", 'WARNING')
    wait_seconds = wait_seconds_default.to_s
  end

  uri = lookup_values_yaml(display, ['uri'])
  uri ||= lookup_values_yaml(instance, ['uri'])
  if uri.nil?
    lv_host = lookup_values_yaml(instance, ['host'])
    if lv_host
      user = lookup_values_yaml(instance, ['username']) || ENV['USER']
      uri  = "qemu+ssh://#{user}@#{lv_host}/system"
    elsif parse_boolean(lookup_values_yaml(instance, ['qemu_use_session'])) == true
      uri = 'qemu:///session'
    else
      uri = 'qemu:///system'
    end
  end

  # code/providers/libvirt -> project root
  project_root = File.expand_path('../../..', __dir__)

  script = [lookup_values_yaml(display, ['script']), script_default].find { |v| !v.nil? }.to_s
  script = File.expand_path(script, project_root)
  unless File.executable?(script)
    handle_message("display script [#{script}] is missing or not executable; no console will be opened for [#{name}].", 'WARNING')
    return false
  end

  dotfile_path = ENV['VAGRANT_DOTFILE_PATH'] || '.vagrant'
  id_file = File.expand_path(File.join(dotfile_path, 'machines', name, provider, 'id'), project_root)

  args = ['--id-file', id_file, '--name', name, '--uri', uri, '--viewer', viewer]

  if viewer == 'virt-viewer'
    machine.trigger.before :up, :reload, :resume do |t|
      t.name     = 'libvirt console'
      t.on_error = :continue
      t.run      = { path: script, args: args + ['--mode', 'watch', '--wait', wait_seconds] }
    end
  else
    machine.trigger.after :up, :reload, :resume do |t|
      t.name     = 'libvirt console'
      t.on_error = :continue
      t.run      = { path: script, args: args + ['--mode', 'open'] }
    end
  end

  true
end
