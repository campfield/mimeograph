# mimeograph

mimeograph is a configuration engine for efficiently managing complex and diverse [HashiCorp Vagrant](https://www.vagrantup.com/) environments.

It allows large portions of Vagrant and instance configuration (VMs, hardware, networking, storage, provisioning) to be managed in YAML, removing the need for detailed knowledge of Vagrant's Ruby DSL. A hierarchical default system minimises repetition across large numbers of instances.

---

## Features

- All instance configuration managed in YAML — no Vagrant or Ruby knowledge required for day-to-day use
- Hierarchical defaults with deep merging: global defaults, per-profile-group defaults, and per-instance overrides
- Multiple profile groups, each with independent instances and default settings
- Simple Vagrant plugin ensure state management via a single YAML file
- Optional per-plugin integration code under `code/plugins/<plugin-name>/`, loaded only for plugins that are present
- Deterministic pseudo-random IP address assignment stable across reprovisions
- Automatic network interface bring-up and MTU provisioning on every boot
- Bridge interface auto-correction when specified host interfaces are not found
- Automatic `file` provisioner selection when a synced path resolves to a regular file
- `prepend_base_directory` path management for portable filesystem sync configurations
- Provider abstraction for VirtualBox, libvirt, and VMware Desktop
- Four filesystem sync types: VirtualBox shared folders, rsync, NFS, and file provisioner
- Automatic vagrant-dns hostname registration with per-instance CNAME and TLD support

---

## Minimum Requirements

- [HashiCorp Vagrant](https://www.vagrantup.com/)
- [VirtualBox](https://www.virtualbox.org/)
- Ruby 2+ (no external gems required — all dependencies are Ruby stdlib or implemented natively)
- `rsync`

---

## Directory Structure

```
mimeograph/
├── Vagrantfile                   # Entry point — loads code, manages plugins, runs profiles
├── Gemfile                       # No external dependencies; retained for tooling compatibility
├── code/
│   ├── core/                     # Core Ruby source — loaded automatically on every run
│   │   ├── filesystems/          # Synced folder and file provisioner management
│   │   ├── instances/            # Profile loading, instance dispatch, collision detection
│   │   ├── logging/              # handle_message, exit_with_message
│   │   ├── misc/                 # lookup_values_yaml, validate_value, helpers
│   │   ├── networking/           # Forwarded port configuration
│   │   ├── plugins/              # Plugin ensure state, plugin code loader, hook registry
│   │   └── profiles/             # YAML profile and defaults loading
│   ├── local/                    # Site-local Ruby code — loaded automatically
│   ├── plugins/                  # Per-plugin integration code, loaded only when present
│   │   └── vagrant-dns/          # vagrant-dns TLD, hostname patterns, daemon output
│   └── providers/                # Provider-specific code loaded on demand
│       ├── virtualbox/           # VirtualBox provider (implemented)
│       ├── libvirt/              # libvirt provider (implemented; console viewer)
│       └── vmware/               # VMware stub
├── config/
│   ├── defaults/                 # Default settings YAML files
│   │   └── defaults.yaml         # Global defaults applied to all profile groups
│   ├── plugins/
│   │   └── plugins.yaml          # Vagrant plugin ensure state
│   └── profiles/                 # Instance profile YAML files
└── files/
    └── scripts/                  # Host-side scripts for provisioning
└── tools/
    ├── compile_vagrantfile.rb    # Static Vagrantfile compiler
    └── libvirt-console           # Opens virt-viewer/virt-manager on a libvirt VM's console
```

---

## How It Works

On each `vagrant` command:

1. All Ruby files under `code/core/` and `code/local/` are loaded.
2. Required host programs (currently `rsync`) are verified.
3. `config/plugins/plugins.yaml` is read and plugin ensure states are enforced.
4. For every plugin that is `present`, installed, and has a `code/plugins/<plugin-name>/` directory, that directory's Ruby files are loaded and its global hooks run (for example, the vagrant-dns resolver TLD).
5. Every `*.yaml` file in `config/profiles/` is processed as a profile group.
6. For each profile group, `config/defaults/defaults.yaml` is loaded as the base. If a matching group-specific file exists (`config/defaults/<group_name>.yaml`), it is deep-merged on top — so group files only need to contain values that differ from the global defaults.
7. Each instance in the group is deep-merged with the defaults (defaults as the base, instance values win on conflict) and handed to Vagrant's configuration API. Plugin instance hooks (such as vagrant-dns hostname registration) run as part of each provider's configuration.

---

## Adding a New Environment

Create a profile YAML file in `config/profiles/`:

```
config/profiles/my_project.yaml
```

Optionally create a matching defaults file for project-specific defaults:

```
config/defaults/my_project.yaml
```

If no group-specific defaults file exists, the global `config/defaults/defaults.yaml` is used on its own. If a group file does exist, it is layered on top of the global defaults — not used instead of them. This means `bob.yaml` only needs to contain the values specific to that group; all other settings are inherited from `defaults.yaml` automatically.

That is all that is required. No Ruby files need to be created or modified.

---

## Instance Default Hierarchy

Settings are resolved in this order, with later entries winning on conflict:

1. Hardcoded Ruby function defaults
2. Global `config/defaults/defaults.yaml`
3. Profile-group-specific `config/defaults/<group_name>.yaml` (if present, deep-merged on top of global defaults — group values win, absent keys are inherited)
4. Per-instance settings in the profile YAML

The merge between defaults and instance is a deep merge: nested stanzas are combined additively. Only directly conflicting scalar values are resolved by the instance value taking precedence.

---

## Minimal Instance Configuration

Seven lines of YAML is sufficient to boot a named instance:

```yaml
---
- name: moe
  providers:
    virtualbox:
      instance:
        box:
          name: generic/ubuntu1804
```

All other settings come from `defaults.yaml`.

---

## Plugin Management

Edit `config/plugins/plugins.yaml`. The available `ensure` values are:

- `present` — ensure the plugin is installed; install if missing (default)
- `absent` — ensure the plugin is removed; uninstall if present
- `ignore` — take no action regardless of current state

```yaml
plugins:
  vagrant-vbguest:
    ensure: present
    version: '0.29.0'   # optional; omit for latest
  vagrant-cachier:
    ensure: absent
  vagrant-hostmanager:
    ensure: ignore
```

### Plugin integration code

mimeograph-side code for a plugin lives in `code/plugins/<plugin-name>/`, where the directory name is exactly the plugin name. That directory is loaded only when **all** of these hold:

1. the plugin is `ensure: present` in `plugins.yaml` (plugins set to `absent` or `ignore` are never loaded, even if installed);
2. `code/plugins/<plugin-name>/` exists — plugins without a directory are simply installed or removed;
3. Vagrant reports the plugin as installed in this run. On the run that first installs a plugin, Vagrant has not loaded it yet, so its code is skipped with a warning and used from the next `vagrant` command on.

Every `*.rb` file under the directory is required, in sorted path order. The files define functions and register hooks; core and provider code never call plugin functions by name. The hook phases (see `code/core/plugins/plugin_hooks.rb`) are:

| Phase | Runs | Block arguments |
|-------|------|-----------------|
| `:global` | once, from the Vagrantfile, before instances are processed | `settings` |
| `:instance` | once per instance, from each provider (after networking) | `machine, instance_profile, provider, settings` |
| `:compile` | only in `tools/compile_vagrantfile.rb`; returns Ruby source lines to embed verbatim | `settings` |

```ruby
# code/plugins/vagrant-foo/hooks.rb
register_plugin_hook('vagrant-foo', :instance) do |machine, instance_profile, provider, settings|
  configure_vagrant_foo(machine, instance_profile, provider)
end
```

A plugin entry may carry an optional `settings` hash, which is passed to its hooks as `settings`. Each plugin's `hooks.rb` documents the keys it accepts.

```yaml
plugins:
  vagrant-dns:
    ensure: present
    settings:
      daemon_output: false
```

**Version changes:** changing `version` will not auto-update an already-installed plugin. Set the plugin to `absent`, run `vagrant`, then set the new version and `install` back to `present`.

---

## Networking

### IP Address Assignment

The `ip_addr` setting under a networking interface accepts:

| Value | Behaviour |
|-------|-----------|
| A static IPv4 address | Used directly |
| `random` | 4th octet generated deterministically from instance name and interface index — stable across reprovisions |
| `dhcp` | Interface configured for DHCP |
| `none` | Interface created but not brought up on boot |

### Bridge Interface Auto-Correction

When `zone_class: public_network` is used and none of the specified bridge `interfaces` exist on the host:

- `auto_correct: true` — logs a warning and substitutes all non-`lo` host interfaces
- `auto_correct: false` (default) — exits with an error listing the missing interfaces

### Forwarded Ports

If `host_port` is omitted, a deterministic port in the range 2000–9999 is generated from the instance name and port name, remaining stable across reprovisions.

---

## Storage / Filesystem Sync

Filesystem sync objects are defined under `storage.filesystems.synced_fs_objects`. Four sync types are supported:

| Type | Behaviour |
|------|-----------|
| `sync` | Standard Vagrant synced folder (VirtualBox shared folder) |
| `rsync` | rsync-based one-way sync; runs on provision and optionally on each boot |
| `nfs` | NFS mount from host to guest; recommended for libvirt and VMware |
| `file` | Vagrant file provisioner; runs on provision only |

If the resolved `host_path` is a regular file (not a directory), the sync type is automatically set to `file` regardless of the configured value.

The `prepend_base_directory` setting controls host path resolution:

| Value | Behaviour |
|-------|-----------|
| `true` | Prepends mimeograph's own root directory to `host_path` |
| `false` | Uses `host_path` as-is |
| A string | Prepends that string to `host_path` |

### NFS Synced Folders

NFS provides better performance than rsync for frequently accessed, bidirectional data and is the recommended sync type for libvirt and VMware providers (VirtualBox users may also use NFS but typically use the native `sync` type).

**Host requirements:** a running NFS server (`nfs-kernel-server` on Debian/Ubuntu, `nfs-utils` on RHEL/CentOS). Vagrant manages `/etc/exports` on the host automatically and will prompt for `sudo` when needed.

**Guest requirements:** `nfs-common` (Debian/Ubuntu) or `nfs-utils` (RHEL/CentOS).

NFS-specific keys are placed under the `nfs` sub-key of each synced filesystem object:

| Key | Description | Default |
|-----|-------------|---------|
| `nfs.mount_options` | Array of NFS mount options passed to the guest | `['rw', 'vers=3', 'tcp', 'nolock']` |
| `nfs.map_uid` | UID mapping for the NFS export. `0` maps to root; `:auto` uses Vagrant's default. | `:auto` |
| `nfs.map_gid` | GID mapping for the NFS export. `0` maps to root; `:auto` uses Vagrant's default. | `:auto` |
| `nfs.udp` | Use UDP transport instead of TCP. | `false` |

Example — NFS synced folder for a libvirt instance:

```yaml
storage:
  filesystems:
    synced_fs_objects:
      '/srv/project':
        host_path: '/home/bob/project'
        instance_path: /srv/project
        type: nfs
        nfs:
          mount_options:
            - 'rw'
            - 'vers=3'
            - 'tcp'
            - 'nolock'
          map_uid: 0
          map_gid: 0
          udp: false
```

NFS defaults can also be set at the filesystem defaults level so individual objects inherit them:

```yaml
storage:
  filesystems:
    defaults:
      sync_type: nfs
      nfs:
        mount_options:
          - 'rw'
          - 'vers=3'
          - 'tcp'
          - 'nolock'
        map_uid: 0
        map_gid: 0
        udp: false
    synced_fs_objects:
      '/srv/project':
        host_path: '/home/bob/project'
        instance_path: /srv/project
      '/srv/data':
        host_path: '/data/shared'
        instance_path: /srv/data
```

---

## DNS / vagrant-dns

mimeograph automatically registers each instance with the [vagrant-dns](https://github.com/BerlinVagrant/vagrant-dns) plugin when it is installed. No additional YAML is required for basic operation — the hostname already set by `configure_vagrant_box` (from the `hostname` key, or the sanitised instance name as fallback) is used directly.

### Setup

Ensure `vagrant-dns` is set to `present` in `config/plugins/plugins.yaml` (it is by default). After `vagrant up`, start the DNS daemon and install the OS resolver entry:

```bash
vagrant dns --install   # writes /etc/resolver/<tld> on macOS or equivalent on Linux
vagrant dns --start     # starts the daemon; use --restart if already running
```

Verify registration:

```bash
vagrant dns --list                          # shows hostname → IP mappings
dig myhost.local @127.0.0.1 -p 5300        # query the daemon directly
```

### TLD

The TLD controls which DNS suffix the daemon intercepts at the OS level. It is resolved using the standard mimeograph priority order — later levels override earlier ones:

| Level | Where to set it | Key |
|-------|-----------------|-----|
| 1 (lowest) | Hardcoded fallback | — (`'local'`) |
| 2 | `config/defaults/defaults.yaml` | `default_settings.dns.tld` |
| 3 | `config/defaults/<group>.yaml` | `default_settings.dns.tld` |
| 4 (highest) | Per-instance profile | `providers.<provider>.instance.dns.tld` |

Changing the TLD in `defaults.yaml` affects all instances. A group defaults file overrides it for that group. A per-instance `dns.tld` overrides it for that instance only.

### Per-instance DNS options

All keys live under `providers.<provider>.instance.dns`:

| Key | Description | Default |
|-----|-------------|---------|
| `tld` | Override the TLD for this instance | Inherited from defaults |
| `cnames` | Array of additional hostnames that resolve to this instance. TLD is appended automatically if no dot is present. | — |
| `patterns` | Array of raw regexp strings or plain strings for advanced matching. Built and passed directly to `machine.dns.patterns`. | — |
| `enabled` | Set to `false` to disable vagrant-dns registration for this instance entirely. | `true` |

### hostname and DNS

`hostname` is a sibling of `dns`, not nested inside it. It drives both guest OS hostname configuration (`machine.vm.hostname`, the `hostnamectl` provisioner) and the primary DNS entry. `dns.*` keys are host-side resolver settings only.

```yaml
providers:
  virtualbox:
    instance:
      hostname: myhost.local   # guest OS hostname AND primary DNS name
      dns:
        tld: local
        cnames:
          - web.local
          - api.local
```

### Bare hostnames

When no `hostname` key is set, the sanitised instance name is used (e.g. `myvm`). mimeograph automatically appends the resolved TLD to form the FQDN used for pattern registration (`myvm.local`), since the OS resolver appends the TLD before querying the daemon and a bare-name pattern would never match.

### vagrant-dns log and load issues

vagrant-dns starts its daemon with output logging hard-coded on, so every passthrough query and the RubyDNS/async console log are appended without limit to `~/.vagrant.d/tmp/dns/daemon/vagrant-dns.output`. The plugin has no option to turn this off — `VagrantDNS::Config.logger`, which its README still shows, is never read by the plugin.

mimeograph controls this from `config/plugins/plugins.yaml`:

```yaml
  vagrant-dns:
    ensure: present
    settings:
      passthrough: true      # true | false | unknown
      daemon_output: false   # false: daemon stdout/stderr to /dev/null; true: vagrant-dns default .output file
      log_level: fatal       # debug | info | warn | error | fatal (quietest)
      block_aaaa: true       # answer every AAAA query locally with "no IPv6 address"
```

The values shown are the defaults. `daemon_output: false` wraps vagrant-dns's daemon options so the daemon's stdout and stderr are reopened on `/dev/null`. `log_level` sets `CONSOLE_LEVEL`, which the daemon's logger reads at startup. The code is in `code/plugins/vagrant-dns/daemon_output.rb`.

Both settings apply the next time the daemon starts (`vagrant dns --start` or `--restart`, `vagrant up`, `vagrant reload`); a daemon that is already running keeps writing to its old output until restarted. An existing `vagrant-dns.output` file is left in place and can be deleted once the daemon has been restarted.

### AAAA (IPv6) queries

vagrant-dns only serves A records, but resolvers ask for both A and AAAA for nearly every name. Without intervention, the daemon forwards each AAAA query for a VM name to the upstream resolver (with `passthrough: true`), or fails it with NOTIMP (with `passthrough: false`). Forwarding is slow, and when the TLD is a real domain it sends VM names upstream; the upstream answer is usually NXDOMAIN even though the name exists.

With `block_aaaa: true` (the default), the daemon answers every AAAA query itself with an empty NOERROR response (NODATA: the name has no IPv6 address), before any vagrant-dns rule runs. AAAA queries are never forwarded. A records, and passthrough for other record types, are unaffected. NODATA rather than NXDOMAIN is deliberate: NXDOMAIN would say the name does not exist, which some resolvers then apply to its A record too.

The daemon only receives queries for the vagrant-dns TLD(s), so this does not change IPv6 resolution for anything else on the host. The filter is installed when the daemon starts (code in `code/plugins/vagrant-dns/block_aaaa.rb`), so restart the daemon after changing the setting.

---

## Providers

Three providers are implemented. Each has its own subdirectory under `code/providers/` and is loaded on demand.

### VirtualBox

The default provider. Requires [VirtualBox](https://www.virtualbox.org/) installed on the host. No additional Vagrant plugin is needed.

Provider name in YAML: `virtualbox`

### libvirt (KVM/QEMU)

Requires the `vagrant-libvirt` plugin and a working libvirt/KVM installation on the host.

Provider name in YAML: `libvirt`

Key libvirt-specific YAML options under `providers.libvirt.instance`:

| Key | Description | Default |
|-----|-------------|---------|
| `driver` | Hypervisor driver: `kvm` or `qemu` | `kvm` |
| `disk_bus` | Disk device bus: `virtio`, `scsi`, `ide`, `sata` | `virtio` |
| `disk_cache` | Disk cache mode: `none`, `writethrough`, `writeback` | `none` |
| `storage_pool_name` | libvirt storage pool for box images | `default` |
| `qemu_use_session` | Use `qemu:///session` instead of `qemu:///system` | `false` |
| `host` | Remote libvirt host (local if omitted) | — |
| `connect_via_ssh` | SSH tunnel for remote libvirt (auto-enabled when `host` is set) | `true` |
| `uri` | Override full libvirt connection URI | — |
| `hardware.cpu_mode` | `host-model`, `host-passthrough`, or `custom` | `host-model` |
| `hardware.nested` | Enable nested virtualization | `false` |
| `hardware.graphics_type` | Display protocol: `vnc`, `spice`, `none` | `vnc` |
| `hardware.graphics_ip` | Address the VNC/SPICE socket listens on | `127.0.0.1` |
| `hardware.disks` | List of additional disk definitions (size, type, bus, cache) | — |
| `communication.display.gui` | Open a console viewer when the instance is brought up | `false` |
| `communication.display.viewer` | `virt-viewer` or `virt-manager` | `virt-viewer` |

A working example of every option is the `example_libvirt` group: `config/defaults/example_libvirt.yaml` (group defaults) and `config/profiles/example_libvirt.yaml` (one small Rocky 9.8 VM with the console on): `vagrant up example-libvirt-rocky9`.

For `public_network` interfaces with libvirt, a `dev` key specifying the host device name is required (libvirt uses macvtap rather than a traditional bridge):

```yaml
networking:
  interfaces:
    eth1:
      zone_class: 'public_network'
      dev: 'enp3s0'
      ipv4:
        ip_addr: dhcp
```

#### libvirt console window

libvirt has no VirtualBox-style `gui` flag: every libvirt VM already has a display (`hardware.graphics_type`, VNC on 127.0.0.1 by default), so it appears in virt-manager and Cockpit (cockpit-machines) like any other VM. Setting `communication.display.gui: true` makes mimeograph open a viewer on it for you:

```yaml
providers:
  libvirt:
    instance:
      communication:
        display:
          gui: true                       # default false
          viewer: 'virt-viewer'           # or 'virt-manager'
          # uri: 'qemu:///system'         # default: worked out from the instance (below)
          wait_seconds: 300               # virt-viewer: how long to wait for the VM to be created
          script: 'tools/libvirt-console' # relative to the project root, or absolute
```

| Viewer | When it opens | What you see |
|--------|---------------|--------------|
| `virt-viewer` | before `vagrant up`/`reload`/`resume`, waiting (`--wait --reconnect`) for the VM | the whole boot (firmware, bootloader, kernel); stays attached across guest reboots |
| `virt-manager` | after `vagrant up`/`reload`/`resume` | the virt-manager window on that VM's console (`--show-domain-console`) |

The viewer is started detached by `tools/libvirt-console`, so `vagrant up` never waits for the window and a display problem never fails it. The VM is found by the domain UUID vagrant-libvirt writes to `.vagrant/machines/<name>/libvirt/id`. If a viewer for that VM is already open, a second one is not started. The background watcher logs to `$XDG_RUNTIME_DIR/libvirt-console.log` (override with `LIBVIRT_CONSOLE_LOG`).

The connection URI, when `display.uri` is not set, is the instance `uri`; else `qemu+ssh://<username>@<host>/system` when a remote `host` is set; else `qemu:///session` when `qemu_use_session` is true; else `qemu:///system`.

Where the window appears is decided at run time:

| How you are logged in to the host running `vagrant` | Result |
|-----------------------------------------------------|--------|
| Desktop session (`DISPLAY` or `WAYLAND_DISPLAY` set) | the window opens there |
| SSH with X forwarding (`ssh -X`, or `ForwardX11 yes` in `~/.ssh/config`) | the window opens on your desktop through the forwarding |
| SSH without X forwarding | nothing is opened; it prints the `ssh -X` command and the `virt-viewer --connect qemu+ssh://you@host/system …` command to run on your desktop instead |
| SSH with a `DISPLAY` that does not work (no `xauth` on the host, `X11Forwarding no` in its sshd) | nothing is opened; the reason is printed |

X forwarding cannot be switched on from the host side: it is requested by your ssh client when you connect. The host needs `xauth` and `X11Forwarding yes` (the default on most distributions), plus `virt-viewer` and/or `virt-manager` installed. With `qemu:///system` the user also needs access to libvirt (usually membership of the `libvirt` group).

The helper can be run by hand, for example after reconnecting with `ssh -X`:

```bash
tools/libvirt-console --id-file .vagrant/machines/example-libvirt-rocky9/libvirt/id --mode open
tools/libvirt-console --help
```

### VMware Desktop

Supports VMware Fusion, Workstation, and Player via the official `vagrant-vmware-desktop` plugin. The plugin requires the [Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/docs/providers/vmware/installation) service to be installed separately.

Provider name in YAML: `vmware`

Key VMware-specific YAML options under `providers.vmware.instance`:

| Key | Description | Default |
|-----|-------------|---------|
| `box.linked_clone` | Use VMware linked clone. The VirtualBox linked clone naming issue does not apply to VMware. | `false` |
| `clone_directory` | Path for VMware clone storage | `./.vagrant` |
| `nat_device` | Host vmnet device for NAT interface | auto-detected |
| `verify_vmnet` | Verify vmnet devices before use | `true` |
| `hardware.vmx` | Hash of VMX key/value pairs for fine-grained customization | — |

VMX customization example — set display name and enable 3D acceleration:

```yaml
hardware:
  cpus: 4
  memory: 4096
  vmx:
    displayname: "My Dev VM"
    mks.enable3d: "TRUE"
    vhv.enable: "TRUE"
```

Setting a VMX key to `null` removes it from the `.vmx` file entirely.

### Selecting a Provider

To specify which provider an instance uses:

```yaml
- name: my_instance
  providers:
    defaults:
      providers:
        enabled:
          - 'virtualbox'   # or 'libvirt' or 'vmware'
```

The default if unspecified is `virtualbox`. Only one provider per instance name is supported (a Vagrant limitation).

---

## Configuration Reference

### Top-level instance keys

| Key | Description |
|-----|-------------|
| `name` | Required. Instance name. Spaces, slashes, underscores converted to hyphens. |
| `providers` | Contains provider-specific configuration and the `enabled` / `defaults` stanzas. |

### providers.virtualbox.instance keys

| Key | Description |
|-----|-------------|
| `autostart` | Whether `vagrant up` (no name) starts this instance. Default: `false` |
| `boot_timeout` | Seconds to wait for boot. Default: `240` |
| `box.name` | Vagrant Box name. Falls back to instance name if omitted. |
| `box.url` | Direct URL to download the Box from. |
| `box.download_insecure` | Skip SSL verification on Box download. Default: `false` |
| `box.linked_clone` | Use VirtualBox linked clone. Default: `false`. **Note:** linked clones prevent `vbox.name` from taking effect — set to `false` if correct VM naming in the VirtualBox GUI is required. |
| `box.base_mac` | MAC address for the first (NAT) NIC. 12 hex digits, no separators. Default: `nil` (randomised). |
| `hostname` | Guest hostname. Defaults to instance name with non-alphanumeric characters stripped. |
| `set_hostname` | When `true` (default), injects a shell provisioner that sets the guest hostname via `hostnamectl` (with fallback to legacy `hostname` command). Set to `false` to skip and leave hostname management to the guest OS or other tooling. |
| `dns.tld` | Override the vagrant-dns TLD for this instance. Inherits from group/global defaults if unset. |
| `dns.cnames` | Array of additional hostnames to register with vagrant-dns. TLD appended automatically if no dot present. |
| `dns.patterns` | Array of raw regexp or string patterns passed directly to `machine.dns.patterns`. |
| `dns.enabled` | Set to `false` to disable vagrant-dns registration for this instance. Default: `true` |
| `communication.display.gui` | Start VirtualBox GUI on boot. Default: `false` |
| `communication.ssh.auth_method` | `keypair` or `password`. Default: `keypair` |
| `communication.ssh.username` | SSH username on the guest. Default: `vagrant` |
| `communication.ssh.password` | SSH password. Only used when auth_method is `password`. Default: `vagrant` |
| `communication.ssh.insert_key` | Replace the insecure Vagrant keypair with a generated one. Default: `true` |
| `communication.ssh.private_key_path` | Path to a private key file, or a YAML list of paths. Only set when using a pre-baked keypair (e.g. a FIPS/STIG-compatible key) instead of Vagrant's insecure key. Pair with `insert_key: false` on hardened guests. A missing file is reported as a warning. |
| `communication.ssh.keys_only` | Only authenticate with the configured key(s); forbid password fallback. Only applied when set. Recommended `true` on STIG guests. |
| `communication.ssh.forward_agent` | Forward SSH agent from host into guest. Default: `false` |
| `communication.ssh.forward_x11` | Forward X11 display from guest to host. Default: `false` |
| `hardware.cpus` | vCPU count. Default: `2` |
| `hardware.memory` | RAM in MB. Default: `512` |
| `hardware.modifyvm` | Hash of `vboxmanage modifyvm` parameter/value pairs. |
| `hardware.setextradata` | Hash of flat string key/value pairs for `vboxmanage setextradata`. |
| `networking.*` | See Networking section. |
| `commands.system.*` | Provisioning commands. See Commands section. |
| `storage.filesystems.*` | Synced filesystem objects. See Storage section. |

### providers.libvirt.instance keys

| Key | Description |
|-----|-------------|
| `autostart` | Whether `vagrant up` (no name) starts this instance. Default: `false` |
| `boot_timeout` | Seconds to wait for boot. Default: `300` |
| `box.name` | Vagrant Box name. Falls back to instance name if omitted. |
| `box.url` | Direct URL to download the Box from. |
| `box.download_insecure` | Skip SSL verification on Box download. Default: `false` |
| `box.base_mac` | MAC address for the management network NIC. Default: `nil` (randomised). |
| `hostname` | Guest hostname. Defaults to instance name with non-alphanumeric characters stripped. |
| `set_hostname` | Inject a shell provisioner to set the guest hostname. Default: `true` |
| `driver` | Hypervisor driver: `kvm` or `qemu`. Default: `kvm` |
| `disk_bus` | Disk device bus: `virtio`, `scsi`, `ide`, `sata`. Default: `virtio` |
| `disk_cache` | Disk cache mode: `none`, `writethrough`, `writeback`, `directsync`, `unsafe`. Default: `none` |
| `storage_pool_name` | libvirt storage pool for box images. Default: `default` |
| `qemu_use_session` | Use `qemu:///session` instead of `qemu:///system`. Default: `false` |
| `host` | Remote libvirt host. Omit for local connections. |
| `connect_via_ssh` | SSH tunnel for remote libvirt. Auto-enabled when `host` is set. Default: `true` |
| `username` | Username for remote libvirt connection. Default: current user. |
| `id_ssh_key_file` | Path to SSH key for remote libvirt connection. |
| `socket` | Path to libvirt unix socket. |
| `uri` | Override full libvirt connection URI. |
| `communication.ssh.auth_method` | `keypair` or `password`. Default: `keypair` |
| `communication.ssh.username` | SSH username. Default: `vagrant` |
| `communication.ssh.password` | SSH password. Default: `vagrant` |
| `communication.ssh.insert_key` | Replace insecure keypair. Default: `true` |
| `communication.ssh.private_key_path` | Path to a private key file for SSH authentication, or a YAML list of paths. Pair with `insert_key: false` on FIPS/STIG guests. A missing file is reported as a warning. |
| `communication.ssh.keys_only` | Only authenticate with the configured key(s); forbid password fallback. Only applied when set. Recommended `true` on STIG guests. |
| `communication.ssh.forward_agent` | Forward SSH agent. Default: `false` |
| `communication.ssh.forward_x11` | Forward X11. Default: `false` |
| `communication.display.gui` | Open a console viewer on `vagrant up`/`reload`/`resume` (see [libvirt console window](#libvirt-console-window)). Default: `false` |
| `communication.display.viewer` | `virt-viewer` (opened before up, shows the whole boot) or `virt-manager` (opened after up). Default: `virt-viewer` |
| `communication.display.uri` | libvirt URI the viewer connects to. Default: instance `uri`, else `qemu+ssh://<username>@<host>/system` for a remote `host`, else `qemu:///session` if `qemu_use_session`, else `qemu:///system` |
| `communication.display.wait_seconds` | virt-viewer only: seconds the background watcher waits for the VM to be created. Default: `300` |
| `communication.display.script` | Helper that opens the viewer, relative to the project root or absolute. Default: `tools/libvirt-console` |
| `hardware.cpus` | vCPU count. Default: `2` |
| `hardware.memory` | RAM in MB. Default: `512` |
| `hardware.cpu_mode` | `host-model`, `host-passthrough`, or `custom`. Default: `host-model` |
| `hardware.cpu_model` | CPU model name when cpu_mode is `custom`. |
| `hardware.nested` | Enable nested virtualization. Default: `false` |
| `hardware.graphics_type` | Display protocol: `vnc`, `spice`, `none` (no display, and no console viewer). Default: `vnc` |
| `hardware.graphics_ip` | IP the graphics socket binds to. Default: `127.0.0.1` |
| `hardware.boot` | Boot order: `hd`, `network`, `cdrom`. Default: `hd` |
| `hardware.disks` | List of additional disk definitions (`size`, `type`, `bus`, `cache`). |
| `networking.*` | See Networking section. |
| `commands.system.*` | Provisioning commands. See Commands section. |
| `storage.filesystems.*` | Synced filesystem objects. See Storage section. |

### providers.vmware.instance keys

| Key | Description |
|-----|-------------|
| `autostart` | Whether `vagrant up` (no name) starts this instance. Default: `false` |
| `boot_timeout` | Seconds to wait for boot. Default: `300` |
| `box.name` | Vagrant Box name. Falls back to instance name if omitted. |
| `box.url` | Direct URL to download the Box from. |
| `box.download_insecure` | Skip SSL verification on Box download. Default: `false` |
| `box.linked_clone` | Use VMware linked clone. Default: `false` |
| `box.base_mac` | MAC address for the first (NAT) NIC. Applied via VMX `ethernet0.address`. Default: `nil` (randomised). |
| `hostname` | Guest hostname. Defaults to instance name with non-alphanumeric characters stripped. |
| `set_hostname` | Inject a shell provisioner to set the guest hostname. Default: `true` |
| `verify_vmnet` | Verify vmnet device health before booting. Default: `true` |
| `clone_directory` | Path for VMware clone storage. Default: `./.vagrant` |
| `nat_device` | Host vmnet device for NAT interface. Default: auto-detected. |
| `communication.display.gui` | Open VMware GUI on boot. Default: `false` |
| `communication.ssh.auth_method` | `keypair` or `password`. Default: `keypair` |
| `communication.ssh.username` | SSH username. Default: `vagrant` |
| `communication.ssh.password` | SSH password. Default: `vagrant` |
| `communication.ssh.insert_key` | Replace insecure keypair. Default: `true` |
| `communication.ssh.private_key_path` | Path to a private key file for SSH authentication, or a YAML list of paths. Pair with `insert_key: false` on FIPS/STIG guests. A missing file is reported as a warning. |
| `communication.ssh.keys_only` | Only authenticate with the configured key(s); forbid password fallback. Only applied when set. Recommended `true` on STIG guests. |
| `communication.ssh.forward_agent` | Forward SSH agent. Default: `false` |
| `communication.ssh.forward_x11` | Forward X11. Default: `false` |
| `hardware.cpus` | vCPU count. Default: `2` |
| `hardware.memory` | RAM in MB. Default: `512` |
| `hardware.vmx` | Hash of VMX key/value pairs for fine-grained customization. |
| `networking.*` | See Networking section. |
| `commands.system.*` | Provisioning commands. See Commands section. |
| `storage.filesystems.*` | Synced filesystem objects. See Storage section. |

### Commands

```yaml
commands:
  defaults:
    system:
      call_count: once    # once | always | never
      privileged: true
      type: path          # path | inline
  system:
    my_script:
      text: files/scripts/my_script.sh
      type: path
      call_count: once
    my_inline_cmd:
      text: "echo hello"
      type: inline
      call_count: always
      privileged: false
```

---

## Real-ish World Scenario

### **Today**

Caroline, Bob's manager, has instructed Bob to test his Puppet code in a private environment instead of repeatedly doing it on the customers' production systems. Bob started to set up a Puppet testbed using Vagrant and searched to see if Vagrantfiles and scripts existed which he could modify to fit his needs. This would let him be more agile [methodology namedrop #1] and in turn he could have longer ~~lunches at the pub~~ team building exercises.

The first customer's environment required two instances of CentOS running PostgreSQL and HTTPD, one instance running the customer's specialized Microsoft Windows Server image, and one instance with a GUI-enabled Puppet server running on [Xubuntu](https://xubuntu.org/) [ed. note: the superior Ubuntu].

After downloading mimeograph, he began to read the documentation in preparation of configuring his first environment. As he progressed through the real world scenario, he was forced to question the fundamental nature of reality and his own fragile existence. Shaken by the realization that the scenario was describing himself, including the current act of reading the real-ish world scenario, Bob quickly closed the README.md file. You however continue to read.

Finished with the documentation, Bob created an instance profile YAML named `interocitor_corp.yaml`, added the four required VM definitions, and optionally dropped a `interocitor_corp.yaml` defaults file alongside it for any shared settings. No Ruby. No symlinks. No `.vf` files to copy or explain to a colleague.

Using CentOS Boxes found on [Vagrant Cloud](https://app.vagrantup.com/), he added their identifiers to the CentOS profile stanzas along with host paths to his local PostgreSQL and HTTPD configuration scripts. He pointed the Microsoft instance's Box source URL to the company's internal artifact repository, while the instance name of the Xubuntu instance matched a preexisting VirtualBox image in his local Box inventory.

He executed a `vagrant up` and continued to work, while plummeting towards an existential crisis.

### **The Next Monday**

On Monday another co-worker Alice requested Bob to perform security testing on a twelve VM solution she had designed for a customer. Already using mimeograph to create DevOps workflows [methodology namedrop #2], she sent him an archive file containing her profile, defaults, and local code files.

Her mimeograph configuration consumed a total of 223 lines of unique YAML. Bob copied the files into `config/profiles/` and `config/defaults/`. That was it. Vagrant found them automatically.

Since Bob didn't have a license for VMware workstation on his testbed system, he only needed to alter two lines of her defaults: one to utilize VirtualBox and a second to specify the alternate Box URL. Setting her instances to autostart, Bob issued a `vagrant up` and went to fetch a ~~quick pint~~ soda while Alice's twelve VM environment was provisioned.

### **That Evening and the Next Morning**

At the end of the day, good work was accomplished. The team building exercise ended up being four hours and six rounds at the pub, with significant discussion on the concept of free will and how books, movies, and television portrayed the dire consequences of people who tinkered with fate.

Bob woke up the next morning with the single winning ticket to that night's national lottery on his nightstand, along with a warm feeling resulting from the serum of eternal youth the time traveler had just injected into Bob's arm. Before peacefully returning to his own time, the traveler said "You committed example configurations to the upstream project so other people could reference them." Oh, and nothing even remotely resembling some form of cursed monkey paw or Twilight Zone-style wish corruption nonsense or actually any negative side effects **ever** happened to anybody either. Oh, and nobody edited my story in any meaningful way in mimeograph's "Real-ish World Scenario."

---

## A Note on Major Rewrites, or: What Happens When You Hand Your Code to an AI at the Pub

Some time after the events described above — specifically after Bob had spent several years blissfully unaware that his deep merge was backwards — the mimeograph source code was uploaded to a large language model and subjected to a thorough code review.

The AI, which had no stake in the matter and no feelings to spare for the `.vf` symlink workflow, promptly identified thirteen bugs and a plugin dispatch system that was, in its words, "solving a problem that doesn't exist yet in a way that's already causing bugs." It detailed code and text duplication issues, issues with the network bridging that were so embarrassing it just told Bob the issue was REDACTED for his state of mind.

Bob told it to fix the issues and the AI promptly refactored a large part of the project, with the grace and accuracy of a bull in a China shop.  Bob then decided the correct course of action was to put in his best of Rush mix-tape, head to the chipper, and then [Danny Dunn and the Homework Machine](https://en.wikipedia.org/wiki/Danny_Dunn_and_the_Homework_Machine) the entire bug fixing, refactoring, and general improvement of the project.

The AI, for its part, did not claim credit in the git log, did not ask for a pint, and did not editorialize about the `elsif instance_profile` logic branch that could never, under any circumstances, have been reached.

The real-ish world scenario has been updated to reflect the program's structure. The time traveler will be consulted last week.

---

## Changes from Previous Version

**Providers**
- libvirt provider fully implemented: box/hostname configuration, hardware (CPUs, memory, CPU mode, nested virt, graphics, additional disks), private and public (macvtap) networking, remote libvirt connection options.
- libvirt console viewer: `communication.display.gui: true` opens virt-viewer (or virt-manager) on the VM's console when it is brought up, locally or through SSH X forwarding, and prints instructions when no window can be opened. `example_libvirt` is now a complete, bootable example group.
- VMware Desktop provider fully implemented: box/hostname configuration, hardware with VMX key/value customization, private and public (bridged) networking. Supports Fusion, Workstation, and Player via `vagrant-vmware-desktop`.

**Architecture**
- The `config/classes/` directory and all `.vf` sub-class files have been removed. Environment grouping is now handled automatically by placing profile YAML files in `config/profiles/`. No Ruby files need to be created or symlinked to add a new environment.
- `code/upstream/` and `config/boxes/` placeholder directories have been removed.
- Provider code is now loaded with Ruby's `require` (cached after first load) rather than `load`, eliminating the need for the `$provider_loaded_last` guard variable.
- The `deep_merge` external gem dependency has been removed. A native implementation is provided in `code/core/misc/deep_merge.rb` and loaded automatically with the rest of the core code. mimeograph now has no external gem dependencies — all dependencies are Ruby stdlib.

**Plugin management**
- `config/plugins/defaults.yaml` has been replaced by `config/plugins/plugins.yaml` with a simpler flat structure.
- The plugin handler dispatch system (`code_load`, per-plugin Ruby files under `code/plugins/`, `send()`-based function dispatch) has been removed entirely. Per-plugin code has since returned in a narrower form: `code/plugins/<plugin-name>/` directories loaded only for present plugins, attached through a fixed set of hook phases instead of name-based dispatch (see [Plugin integration code](#plugin-integration-code)).
- Plugin install and uninstall operations are now plain `system()` calls. Threading has been removed.

**Bug fixes applied**
- Deep merge order corrected: instance profile values now correctly take precedence over defaults.
- `forwarded_ports` YAML key lookup corrected (was `forward_ports`).
- Bare Ruby constant `static` in the `public_network`/`none` interface branch replaced with the string `'static'`.
- Bridge interface existence check corrected from an inverted `include?` call to a proper array intersection (`&`).
- `ip link` host interface parsing cleaned up; redundant `.select` no-op removed.
- rsync YAML key `options` now correctly maps to the `rsync__args` Vagrant API parameter (was looking up a non-existent `args` key).
- `setextradata` entries are now validated as scalar values before being passed to `vboxmanage`.
- `lookup_values_yaml` now guards against calling `.empty?` on non-collection types.
- Interface bring-up and MTU provisioner name variables are now local (were unintentionally global).
- Unreachable `elsif` branch in sub-class instance loop removed.

---

## Known Limitations

- **VirtualBox linked clones and VM naming:** When `box.linked_clone: true` is set for a VirtualBox instance, Vagrant assigns the VM's display name in VirtualBox at clone creation time using its own default scheme (`directory_machinename_timestamp_random`). The `vbox.name` setting and any `vboxmanage modifyvm --name` customisation commands run in a later phase and do not reliably override the name that was committed during the clone operation. If correct VM naming in the VirtualBox GUI is important, set `box.linked_clone: false` in the instance or group defaults. Full clones take slightly longer to provision and use more disk space, but the instance name is honoured correctly.
- libvirt remote connection flow (`connect_via_ssh`, `proxy_command`) is implemented but not extensively tested across all distributions.
- VMware VMX key behavior may vary between Fusion, Workstation, and Player — test VMX customizations against your specific product.
- Plugin version changes require a manual uninstall cycle.
- The O(n) Vagrant catalog compilation slowdown for large instance counts is a Vagrant internals issue and is not addressed here.
- The `set_hostname` provisioner uses `hostnamectl` with a fallback to the legacy `hostname` command. On guests that manage hostname through cloud-init or other mechanisms, set `set_hostname: false` to avoid conflicts.
- `ifup` interface bring-up commands assume a Linux guest with `ifupdown` or compatible tooling. systemd-networkd and NetworkManager guests may require different provisioning commands.
