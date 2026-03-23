# mimeograph — Changes

This document describes all changes between the original mimeograph codebase and the current version. Changes are organised into four sections: architecture and design changes, new features, bug fixes, and documentation.

---

## Architecture

### Sub-class system removed

The original architecture required three artefacts to define an environment: a `.vf` Ruby sub-class file in `config/classes/`, a profile YAML in `config/profiles/`, and optionally a defaults YAML in `config/defaults/`. Every `.vf` file was a near-identical copy of `defaults.vf` — a function that loaded profiles, merged defaults, resolved providers, and called `Vagrant.configure`. Adding a new environment meant creating or symlinking a new `.vf` file and understanding Ruby control flow.

The sub-class system has been replaced with automatic profile discovery. The Vagrantfile now calls `configure_all_instances`, which globs every `*.yaml` file in `config/profiles/`, performs the default merge and provider resolution internally, and hands each instance to Vagrant. Adding a new environment requires only a YAML file. No Ruby files need to be created, copied, or modified.

**Removed:** `config/classes/` directory and all `.vf` files.

### Deep merge order corrected and gem dependency removed

The original used the `deep_merge` gem (`require 'deep_merge'`) and merged in the wrong direction: `instance_profile.deep_merge(default_settings)`, which meant default values silently overwrote instance-specific settings on conflict. The intended behaviour — instance values winning — was never achieved.

A native `Hash#deep_merge` implementation is now provided in `code/core/misc/deep_merge.rb`. The merge call is corrected to `default_settings.deep_merge(instance_profile)` so that instance values take precedence. The external gem dependency has been removed; mimeograph now requires only Ruby stdlib.

### Hierarchical defaults with group-level layering

The original `load_profile_defaults` returned the first defaults file it found — either the group-specific file or the global file, but never both. This meant a group defaults file had to duplicate every global setting it wanted to preserve.

Defaults are now loaded in layers: `config/defaults/defaults.yaml` is always loaded as the base, and if a group-specific file exists (e.g. `config/defaults/bob.yaml`) it is deep-merged on top. Group files only need to contain values that differ from the global defaults.

### Provider code loading changed from `load` to `require`

The original used Ruby's `load` to execute provider files on every invocation, guarded by a `$provider_loaded_last` global variable to avoid redundant reloads. This was fragile — the guard only tracked the most recent provider, so alternating providers across instances would reload files unnecessarily.

Provider files are now loaded with `require`, which is cached by the Ruby runtime after first load. The `$provider_loaded_last` global variable has been removed.

### Provider function name collision resolved

All three providers (VirtualBox, libvirt, VMware) defined a function named `configure_instance` at the global Ruby scope. Since Ruby's `require` caches file loading but function redefinition still occurs on first load, whichever provider was loaded last owned the function name. In a mixed-provider environment, the VirtualBox name-setting code — which was the only provider that set the VM display name — would be silently overwritten.

Provider entry points are now uniquely named: `configure_instance_virtualbox`, `configure_instance_libvirt`, and `configure_instance_vmware`. The dispatcher in `configure_instances.rb` calls the correct function via an explicit `case` statement.

### Plugin system simplified

The original plugin system consisted of three files: `configure_plugins.rb` (top-level handler), `configure_plugins_state.rb` (install/uninstall with threading), and `plugins_code_load.rb` (a `send()`-based dispatch system that loaded per-plugin Ruby files from `code/plugins/` and called conventionally-named functions). The configuration file used a nested structure under `default_settings.vagrant.plugins.managed_plugins` with `install_state` values of `installed`, `uninstalled`, and `ignore`.

The plugin system has been reduced to a single `configure_plugins.rb` that reads a flat `config/plugins/plugins.yaml` file. The `ensure` values are `present`, `absent`, and `ignore` (matching Puppet/Ansible conventions). Install and uninstall are plain `system()` calls with error handling. Threading has been removed. The `code/plugins/` directory and the `send()`-based dispatch system have been removed entirely. Plugin-specific configuration should use Vagrant's native plugin config mechanisms.

**Removed:** `code/core/plugins/configure_plugins_state.rb`, `code/core/plugins/plugins_code_load.rb`, `code/plugins/` directory and all per-plugin Ruby files, `config/plugins/defaults.yaml` (replaced by `config/plugins/plugins.yaml`).

### Box catalogue management removed

The original included a `config/boxes/` directory with a `defaults.yaml` and two handler functions (`configure_vagrant_boxes`, `configure_vagrant_boxes_state`) intended for managing global Vagrant box install state. The state function was a placeholder that returned immediately after loading the YAML. No box management was ever performed.

**Removed:** `config/boxes/` directory, `code/core/boxes/configure_vagrant_boxes.rb`, `code/core/boxes/configure_vagrant_boxes_state.rb`.

### Communication handler moved to core

The original `configure_communication` was located under the VirtualBox provider directory (`code/providers/virtualbox/communications/`), hard-coded to the VirtualBox provider, and unavailable to libvirt or VMware instances. It has been moved to `code/core/misc/configure_communication.rb` and made provider-aware: it resolves the correct Vagrant provider API name (including `vmware` → `vmware_desktop` mapping), applies GUI settings for providers that support them, and skips the GUI flag for libvirt (which manages display via `graphics_type`).

### Instance name collision detection moved to core

The original used a global array (`$profile_names_loaded`) inside `configure_instances` to detect duplicate instance names. This is now handled in `configure_all_instances` using a local `profile_names_seen` array, eliminating the global variable.

### Miscellaneous removals

**Removed:** `code/upstream/` placeholder directory. `code/local/format_json.rb` and `code/local/populate_hash_synced_fs_objects.rb` (unused helper functions). `require 'rubygems'` from the Vagrantfile (unnecessary on Ruby 1.9+).

---

## New Features

### libvirt provider fully implemented

The original libvirt provider was a stub that logged "not implemented" and returned. It is now a complete implementation across four files:

`configure_vagrant_box_libvirt` — box identity, hostname, `set_hostname` provisioner, hypervisor driver (`kvm`/`qemu`), disk bus, disk cache, storage pool, `qemu_use_session`, remote connection options (`host`, `connect_via_ssh`, `username`, `id_ssh_key_file`, `socket`, `uri`), and `base_mac` (mapped to `management_network_mac`).

`configure_instance_hardware_libvirt` — CPUs, memory, CPU mode (`host-model`/`host-passthrough`/`custom`), CPU model, nested virtualisation, graphics type and IP, boot order, and additional disk definitions.

`configure_networking_libvirt` — private networks with `libvirt__network_name`, `libvirt__forward_mode`, `libvirt__dhcp_enabled`, and `auto_config`; public networks via macvtap with required `dev` key and `active_machine?` guard; static, random, DHCP, and none IP modes; interface bring-up and MTU provisioning on every boot; forwarded ports.

### VMware Desktop provider fully implemented

The original VMware provider was a stub. It is now a complete implementation across four files:

`configure_vagrant_box_vmware` — box identity, hostname, `set_hostname` provisioner, linked clone, `verify_vmnet`, `clone_directory`, `nat_device`, and `base_mac` (mapped to VMX `ethernet0.addressType` and `ethernet0.address`).

`configure_instance_hardware_vmware` — CPUs, memory (set via VMX `numvcpus`/`memsize`), and arbitrary VMX key/value pairs with `null` removal support.

`configure_networking_vmware` — private and public (bridged) networks with `auto_config`; static, random, DHCP, and none IP modes; per-interface bridge device selection; interface bring-up and MTU provisioning on every boot; forwarded ports.

`configure_instance_vmware` — automatic `displayname` VMX injection from the instance name unless overridden by a user-supplied `displayname` in the `hardware.vmx` hash.

### NFS filesystem sync support

The original `configure_synced_fs_objects` supported three sync types: `sync`, `rsync`, and `file`. NFS has been added as a fourth type with full YAML configurability: `mount_options`, `map_uid`, `map_gid`, `udp`, and `linux__nfs_options`. NFS defaults are configurable at the filesystem defaults level for inheritance across objects.

### Hostname provisioner

A new `provision_hostname` function injects a shell provisioner that sets the guest hostname via `hostnamectl` (with fallback to the legacy `hostname` command). This supplements Vagrant's own hostname management, which is not reliable on all distributions. Controlled by the YAML key `set_hostname` (default: `true`). Used by all three providers.

### Active machine detection

A new `active_machine?` helper determines whether an instance is being targeted in the current Vagrant invocation by parsing `ARGV`. This allows expensive or host-dependent checks (bridge interface presence, libvirt `dev` requirement) to be skipped for instances that are not being acted upon, preventing `vagrant up myvm` from erroring on config belonging to other VMs.

### VirtualBox VM naming

The VirtualBox provider now sets the VM display name in three places: `vbox.name` for Vagrant's SetName action, and `vboxmanage modifyvm --name` as a post-configuration reinforcement in `configure_instance_virtualbox`. A previous `pre-import` customization that used incorrect Vagrant API syntax (`event:` keyword argument instead of positional) has been removed.

### SSH `private_key_path` support

`configure_communication` now reads and applies `communication.ssh.private_key_path` when explicitly configured, allowing users with custom keypairs to specify the path in YAML.

### VirtualBox `setextradata` support

`configure_instance_hardware` now supports a `setextradata` hash under hardware configuration, allowing arbitrary `vboxmanage setextradata` key/value pairs. Values are validated as scalars before being passed to VBoxManage.

### VirtualBox `base_mac` support

The VirtualBox provider reads `box.base_mac` and applies it via `vboxmanage modifyvm --macaddress1`, allowing users to set a fixed MAC address for the first (NAT) NIC for DHCP reservation or network policy purposes.

### Comprehensive example profiles

Three new reference profiles demonstrate every supported option for each provider: `example_virtualbox.yaml`, `example_libvirt.yaml`, and `example_vmware.yaml`. Each includes minimal, typical, and full-option instance definitions with inline documentation. Matching example defaults files are provided.

### rsync privileged mode

The `rsync` sync type now supports a `privileged` key. When `true`, the argument `--rsync-path='sudo rsync'` is appended to rsync options automatically, enabling rsync to write to root-owned directories on the guest.

---

## Bug Fixes

### Deep merge order (critical)

`instance_profile.deep_merge(default_settings)` → `default_settings.deep_merge(instance_profile)`. The original merge used the instance profile as the base and defaults as the overlay, meaning defaults silently overwrote instance-specific values on every conflicting key.

### Forwarded ports YAML key

The original looked up `['defaults', 'forward_ports', 'protocol']` but the YAML key was `forwarded_ports`. Corrected to `['defaults', 'forwarded_ports', 'protocol']`.

### rsync options YAML key

The original looked up `['rsync', 'args']` to map to Vagrant's `rsync__args` parameter, but the YAML key was `options`. Corrected to `['rsync', 'options']`.

### Bare Ruby constant `static`

In the VirtualBox interface `public_network`/`none` branch, the original used the bare constant `static` (an undefined Ruby constant) instead of the string `'static'`. This would raise a `NameError` at runtime whenever a public network interface was set to `bootproto: none`.

### Bridge interface existence check

The original used `!bridge_interfaces.include?(interfaces_host)`, which checks whether the array of host interfaces is an element of the bridge interfaces array — always false. Corrected to use array intersection (`bridge_interfaces & interfaces_host`) to find matching interfaces.

### `ip link` host interface parsing

The original used `ip link sh` with a regex and a trailing `.select` with no block (a no-op that returns an enumerator, not an array). Corrected to `ip -o link show` with a proper regex and direct `.flatten.sort`.

### Interface provisioner name variables

The original used global variables `$interface_ifup_command` and `$interface_mtu_set_command` for the interface bring-up and MTU provisioner names. These are now local variables, preventing unintended cross-instance leakage.

### `lookup_values_yaml` guard against non-collection types

The original called `.empty?` unconditionally on the source value, which would raise `NoMethodError` on integers, booleans, and other non-collection types. The updated version guards with `respond_to?(:empty?)`.

### VirtualBox `private_network` static/none missing `name:` parameter

The `dhcp` case passed `name: network_name` to place the interface on the correct host-only network, but the `static` and `none` cases did not. All three cases now pass `name: network_name` consistently.

### Forwarded port valid protocols

The original included `icmp` in the valid protocols list, but Vagrant's `forwarded_port` only supports `tcp` and `udp`. Removed `icmp`.

### Forwarded port deterministic hash

The original generated the deterministic host port from `Digest::MD5.hexdigest(name)` alone, meaning all ports for the same instance would hash to the same value. The updated version includes the port name in the hash: `Digest::MD5.hexdigest("#{name}-#{port_name}")`.

### NFS `map_uid` and `map_gid` not passed to Vagrant

The NFS branch of `configure_synced_fs_objects` resolved `nfs_map_uid` and `nfs_map_gid` from the YAML hierarchy but never passed them to Vagrant's `synced_folder` call. Added `map_uid:` and `map_gid:` to the call.

### VMware `base_mac` silently ignored

The YAML key `box.base_mac` existed in VMware defaults and examples but was never read by `configure_vagrant_box_vmware`. Now reads the key and maps it to VMX entries `ethernet0.addressType: static` and `ethernet0.address`.

### VMware MTU provisioner skipped for DHCP interfaces

The MTU provisioner block was gated by `next if ip_addr.nil?`, but the DHCP case set `ip_addr = nil`. DHCP interfaces never had their MTU set. Removed the nil guard; the `none` case already exits early via `next`.

### Plugin install error handling and argument order

Plugin `system()` calls had no error handling — a failed install or uninstall was silently ignored. Both calls now check the return value and call `exit_with_message` on failure. The install command argument order was also corrected to place the plugin name before the version flag.

### `linked_clone` defaulted to `true`

The Ruby function defaults, YAML global defaults, and all example profiles defaulted `linked_clone` to `true` for both VirtualBox and VMware. For VirtualBox, this prevented `vbox.name` from taking effect because Vagrant assigns the VM display name at clone creation time using its own generated scheme. All levels now default to `false`. The VMware provider is unaffected by the naming issue but was changed for consistency.

### Broken VirtualBox `pre-import` customization

The VirtualBox box configuration included `vbox.customize(['--vsys', '0', '--vmname', name], event: 'pre-import')`. Vagrant's `customize` method does not accept `event:` as a keyword argument — it expects the event as a positional first argument. Vagrant silently treated the command as a `pre-boot` customization, causing `VBoxManage --vsys 0 --vmname <name>` to run as a standalone command on every boot, which failed because `--vsys` is only valid during `VBoxManage import`. Removed the call entirely; VM naming is handled by `vbox.name` and the `modifyvm --name` customization.

### Unreachable `elsif` branch

The original sub-class `.vf` file contained `if instance_profile ... elsif instance_profile` — the second branch tested the same condition as the first and could never be reached. Removed along with the sub-class system.

---

## Documentation

### README rewritten

The README has been rewritten to reflect the new architecture. Key additions: directory structure diagram, "How It Works" walkthrough of the boot sequence, "Adding a New Environment" guide, instance default hierarchy explanation, minimal instance configuration example, plugin management reference, networking reference (IP assignment modes, bridge auto-correction, forwarded ports), storage/filesystem sync reference including NFS with examples, full provider documentation for VirtualBox, libvirt, and VMware with option tables, configuration reference tables for all three providers covering every supported YAML key, and a Known Limitations section.

### YAML defaults fully documented

`config/defaults/defaults.yaml` now contains every supported option for all three providers with inline comments explaining each key, its valid values, and its default. The file serves as both a functional defaults file and a configuration reference.

### `setextradata` validation documented

The `setextradata` hash validates that values are scalar (String or Numeric) before passing them to `vboxmanage setextradata`, logging a warning and skipping non-scalar values.

---

## File Inventory

### Removed

```
config/boxes/                                          Box catalogue directory
config/boxes/defaults.yaml                             Box catalogue defaults
config/classes/                                        Sub-class directory
config/classes/defaults.vf                             Default sub-class file
config/classes/interocitor_corp.vf                     Interocitor Corp sub-class
config/classes/kabukiman_nypd.vf                       Kabukiman NYPD sub-class
config/plugins/defaults.yaml                           Old plugin config (replaced)
code/core/boxes/configure_vagrant_boxes.rb             Box catalogue handler
code/core/boxes/configure_vagrant_boxes_state.rb       Box state placeholder
code/core/plugins/configure_plugins_state.rb           Plugin state with threading
code/core/plugins/plugins_code_load.rb                 Plugin send() dispatch
code/plugins/                                          Per-plugin code directory
code/plugins/vagrant-cachier/                          vagrant-cachier plugin code
code/plugins/vagrant-vbguest/                          vagrant-vbguest plugin code
code/providers/virtualbox/communications/              VirtualBox-only comms dir
code/upstream/                                         Upstream placeholder directory
code/local/format_json.rb                              Unused JSON formatter
code/local/populate_hash_synced_fs_objects.rb          Unused fs object helper
```

### Added

```
code/core/instances/configure_all_instances.rb         Profile discovery and dispatch
code/core/misc/active_machine.rb                       ARGV-based target detection
code/core/misc/configure_communication.rb              Provider-aware SSH/GUI config
code/core/misc/deep_merge.rb                           Native Hash#deep_merge
code/core/misc/provision_hostname.rb                   hostnamectl provisioner
code/providers/libvirt/configure_vagrant_box.rb         libvirt box/hostname/connection
code/providers/libvirt/configure_instance_hardware.rb   libvirt hardware/disks/display
code/providers/libvirt/configure_networking.rb           libvirt networking/macvtap
code/providers/vmware/configure_vagrant_box.rb          VMware box/hostname/vmnet
code/providers/vmware/configure_instance_hardware.rb    VMware hardware/VMX
code/providers/vmware/configure_networking.rb            VMware networking/bridging
config/plugins/plugins.yaml                             Simplified plugin config
config/defaults/example_libvirt.yaml                    libvirt example defaults
config/defaults/example_virtualbox.yaml                 VirtualBox example defaults
config/defaults/example_vmware.yaml                     VMware example defaults
config/defaults/puppet.yaml                               puppet group defaults
config/profiles/example_libvirt.yaml                    libvirt reference profile
config/profiles/example_virtualbox.yaml                 VirtualBox reference profile
config/profiles/example_vmware.yaml                     VMware reference profile
config/profiles/puppet.yaml                               puppet profile
```

### Renamed or relocated

```
code/providers/virtualbox/communications/configure_communication.rb
  → code/core/misc/configure_communication.rb           Moved to core, made provider-aware

config/plugins/defaults.yaml
  → config/plugins/plugins.yaml                          Restructured flat format
```
