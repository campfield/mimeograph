# To Do

- Plugin version change handling: detect installed version mismatch and update automatically.
- Add `host` as a system command execution target (currently only `instance` is supported).
- Investigate Vagrant catalog compilation O(n) slowdown for large instance counts; evaluate parallelism options.
- Replace `ifup` interface bring-up with a more portable solution compatible with systemd-networkd and NetworkManager guests.
- Auth-by-password has stopped working in Vagrant for certain operations — investigate and document workaround or remove the option.
- libvirt: add support for additional storage configuration options (snapshots, snapshot_pool_name, PCI passthrough).
- libvirt: test and validate remote libvirt connection flow (connect_via_ssh, proxy_command).
- VMware: validate VMX key behavior across Fusion, Workstation, and Player — behavior may differ between products.
- VMware: add support for base_mac / base_address DHCP reservation options.
