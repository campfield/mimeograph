# mimeograph
mimeograph is an over engineered and poorly documented configuration engine for efficiently managing complex and diverse [HashiCorp](https://www.hashicorp.com/) [Vagrant](https://www.vagrantup.com/) environments.

At its core mimeograph allows for large portions of Vagrant and instance configurations (e.g., VMs and containers) to be managed in YAML.  Additionally, items such as default values for multiple instances, Vagrant Providers, and Plugins can be similarity managed.

mimeograph configurations are easy to understand, quick to deploy, provide for encapsulated environments, and remove the requirements for detailed understanding of Vagrant configuration files or the Ruby programming language.

* [mimeograph](#mimeograph)
  * [Features](#features)
  * [Minimum Requirements](#minimum-requirements)
  * [Important Notes](#important-notes)
  * [Example very minimal instance configuration](#example-very-minimal-instance-configuration)
  * [Terse details on the execution process](#terse-details-on-the-execution-process)
  * [Directory organization](#directory-organization)
  * [General notes on configuration](#general-notes-on-configuration)
  * [Instance default hierarchy](#instance-default-hierarchy)
    + [Notes](#notes-)
  * [Specifying Vagrant Boxes](#specifying-vagrant-boxes)
  * [Networking](#networking)
  * [Plugins](#plugins)
    + [Install state management](#install-state-management)
    + [Code loading](#code-loading)
    + [Notes](#notes)
  * [Storage](#storage)
    + [Notes](#notes)
  * [Basic configuration walkthrough](#basic-configuration-walkthrough)
    + [Example Plugin management configuration](#example-plugin-management-configuration)
    + [Basic instance profile: **moe**](#basic-instance-profile----moe--)
    + [Intermediate instance profile: **larry**](#intermediate-instance-profile----larry--)
    + [Complex instance profile: **shemp**](#complex-instance-profile----shemp--)
  * [Real-ish world scenario](#real-ish-world-scenario)
    + [**Today**](#--today--)
    + [**The next Monday**](#--the-next-monday--)
    + [**That evening and the next morning**](#--that-evening-and-the-next-morning--)

## Features
  * Transference of a significant amount of configuration data from Vagrantfiles into YAML-formatted data structures.  This includes hardware, host-to-instance filesystem synchronization, communication methods, GUI management, and script and program execution.
  * No requirement to know Vagrant configuration stanzas or the Ruby programming language in order to apply Vagrant to many tasks across multiple hypervisors.
  * A series of applicable default settings in YAML and code that minimize repetition in configuration, allow for quick reconfiguration, and hypervisor and project-specific settings.
  * Simple configuration of complex networking and network devices including the ability to set static, randomized, and DHCP IP addresses on multiple interfaces, adapters, subnets, and network types.
  * Creation of additional sub-classes (i.e., Vagrantfiles that encapsulate and isolate groups of instances) each of which can possess its own independent instances, default settings, Ruby source code, and Vagrant directives.  No requirement to know Vagrantfile configuration is required when using the provided default configurations.  A simple copy/symlink of the defaults.vf sub-class file to the new sub-class name creates a unique environment.
  * Management of upstream Vagrant [Plugins](https://www.vagrantup.com/docs/plugins/) and the ability to write Ruby function-based handlers that interface with those Plugins.
  * Multiple providers, such as VirtualBox, Hyper-V, vSphere, and VMware can be utilized with individualized configurations, rapidly switched between, or mix and matched with single line changes in YAML.
  * The source code and YAML structure is designed so that additional Providers, local and upstream code, and settings can be added with minimal modification of the source code or additions to YAML.

## Minimum Requirements
  * [HashiCorp](https://www.hashicorp.com/) [Vagrant](https://www.vagrantup.com/)
  * [VirtualBox](https://www.virtualbox.org/) virtualization hypervisor
  * Ruby 2+ and the Ruby Gems listed in the included Gemfile
  * [rsync](https://en.wikipedia.org/wiki/Rsync)


## Important Notes
  * Currently the [VirtualBox](https://www.virtualbox.org/) virtualization hypervisor is the only hypervisor that can be enabled.  The YAML and code structures are in place for adding additional hypervisors with VMware as the next scheduled hypervisor.
  * There is a slowdown in Vagrant's execution (after mimeograph creates the catalog) dependent on the number of instances that are added to the catalog during the parsing process (approximately order O(n) during testing up to 30 instances).

## Example: Very Minimal Instance Configuration

The following configuration defines a VirtualBox instance 'moe' which, upon a 'vagrant up', downloads the generic/ubuntu1804 Box from [Vagrant Cloud](https://app.vagrantup.com/) and boots the instance with the source code's default settings for VirtualBox VMs and the hostname 'moe'.  At then end of the provisioning process a new VM is instantiated and running requiring only 7 lines of user-created YAML.

```
---
- name: moe
  providers:
    virtualbox:
      instance:
        box:
          name: generic/ubuntu1804
```

## Terse Details on the Execution Process
mimeograph's execution, using the shipped default.vf Vagrantfile sub-class file, proceeds as follows:
  - A Vagrant command is issued from the shell (e.g., 'vagrant up' or 'vagrant destroy').
  - The primary Vagrantfile loads Ruby code from under the code/ directory.
  - The config/plugins/defaults.yaml file is parsed and manages the install state of Plugins and executes any specialized functions written for them.
  - A loop begins over files in config/classes/ directory that end in .vf (sub-class files).
  - Each sub-class file attempts to load one of the YAML files under the config/defaults/ directory which contains default settings for that sub-class' instances.
  - The sub-class file then loads an instance profile configuration file from config/profiles/ named the same name as the sub-class file but with a .yaml extension.
  - Each instance definition in the instance profile's YAML configuration is looped over and its configuration data deep merged with any default settings previously imported from the file in config/defaults/.  This data is then passed to the configure_instances() function that begins parsing the data and configuring the instance using Ruby and Vagrant's configuration syntax loaded previously.
  - The process repeats for every sub-class file after which Vagrant uses the compiled state descriptions to fulfill the command sequence specified via the CLI.

## Directory Organization

| directory      | description |
| ----------- | ----------- |
| config/  | Location of configuration data (defaults, instance profiles, Plugins, classes, etc) |
| config/boxes/  | Placeholder for future use for direct management of the local Vagrant Box catalog |
| config/classes/  | Vagrant sub-classes |
| config/defaults/  | Default configuration options for sub-classes (vf files) |
| config/plugins/  | File(s) for configuring Vagrant Plugins install state, Ruby code loading |
| config/profiles/  | File(s) containing the configuration of instances and any of their specific settings |
| code/core/   |  Source code required for basic program functionality |
| code/local/   |  Locally developed or modified upstream source code not required for basic mimeograph functionality |
| code/plugins/   | Plugin-specific source code that is optionally loaded when the configuration for Plugins is handled |
| code/providers/   |  Source code used to configure and manage each provider (e.g., VirtualBox, VMware, Hyper-V, libvirt) |
| code/upstream/  | Source code from upstream sources (e.g., GitHub) |

## General Notes on Configuration
  * In most cases the YAML hierarchy and variable names remain identical to those employed in standard Vagrantfiles Provider configurations.  This is to reduce the amount of retooling required (e.g., the YAML **communication: -> ssh: -> insert_key:** setting functionally maps to the Vagrantfile **config.ssh.insert_key** setting).
  * Available configuration items for the initial VirtualBox provider do not yet have all options implemented in the normal configuration stanzas.  However, by using the setextradata and modifyvm stanza types several unimplemented options can be utilized (e.g., the configuration of VirtualBox system 'Video Memory' via modifyvm option --vram).
  * **site_settings**: The site_settings stanza is the (suggested) location where settings that are not required for mimeograph's core functionality should be located (e.g., package manager settings and network proxy settings).  Values set here will generally be the types referenced in sub-class files and functions under the code/local/ and code/upstream/ directories.
  * Instance profile YAML configuration files can have any number of instance profiles defined within them and all are associated to their Vagrant sub-class and the imported defaults.  All actions specific to that sub-class file or any defaults imported will only be applied to those instance profiles.
  * For ease of reading the documentation, and when structure is clear, higher level YAML structures names are trimmed (e.g., **providers: -> virtualbox: -> instance: -> box: -> name:** is referenced as **box: -> name:**).

## Instance Default Hierarchy

mimeograph allows setting of default values that can be specified across all instances, by sub-class, and within instance-specific defaults.

Defaults files are configured in the same way, with the same structure and stanzas, as a (single) standard instance profile.  The only difference is that instead of the '- name: ' identifier 'default_settings:' is used.

During operation, each sub-class file attempts to load one of a series of YAML files containing default settings present under the config/defaults/ directory.  The defaults loading function first attempts to read a file with the same name as the sub-class file with the .vf extension replaced with .yaml.  If that file is not present the loading function attempts to read the common defaults file named defaults.yaml within the same directory.

This configuration allows for a global set of defaults across all sub-classes and the ability to specify defaults particular to only one sub-class.

### Notes
  * During a sub-class' execution loop any data loaded from a defaults file is deep merged (an additive hash merge) with each of the instance profiles' settings.  If directly conflicting **individual values** within any level of YAML settings are present the instance profile's setting for that value takes precidence.  Entire stanzas do not replace conflicting stanzas but are merged.
  * Only values from one defaults file are read and included in the subsequent deep merge with the instance profile's data.  The sub-class specific defaults are not merged with the contents of the general defaults.yaml.


## Specifying Vagrant Boxes
Vagrant Boxes can be specified by a number of sources that match Vagrant's normal settings.
  - The instance profile has a value for **box: -> name:** and matching box name exists in the local inventory or in Vagrant Cloud.
  - A box name exists in the local inventory that matches the instance profile's 'name' value.
  - If the **box: -> url:** value is defined.
    - If the **box: -> name:** is defined the box from the above URL is downloaded added to the inventory as **box: -> name:** else it is saved to the global catalog as the instance's name.
  - Vagrant will attempt to import a local Box file named the same as the instance profile's name.
  - As with other items Box names and source URLs can be specified with default values.


## Networking
Along with the normal network settings there are additional configuration items to note.
  * **bootproto:** When the value of the networking stanza's bootproto is 'none' then the interface will be created but will not be brought up upon boot nor will any performance modifications to the device, such as MTU, be set by mimeograph.
  * **ipv4: -> ip_addr:** When this entry's value is set to 'random' a pseudo-random value for the fourth octet of the IP address will be deterministically set based upon the instance name and the interface's index in the list.  This address will remain the same value even after system re-provisioning as long as those the instance name and index remain the same.
  * **network bridging:** Due to the fact that the catalog of all instances is compiled during mimeograph's execution, any network bridging stanzas for all instances are evaluated.  If a bridging stanza interface list does not contain at least one adapter matching an adapter available on the host, mimeograph will exit with error.  Similar to the forward_ports auto_correct setting,if the same stanza's boolean 'auto_correct' setting is set to **true** then mimeograph will not exit with error and instead populate the bridge interface list with all of the host system's non-'lo' adapters.
  * **octets_slash_24:** Setting a value for 'octets_slash_24' will use that value as the first three octets in the IP address instead of the in-code defaults (e.g., "octets_slash_24: '10.0.99'").

## Plugins
mimeograph's Plugin management is specified in config/plugins/defaults.yaml and is confirmed/managed each time the environment is utilized (e.g., 'vagrant up' or 'vagrant destroy').

### Install State Management
Plugins managed by mimeograph are defined in config/plugins/defaults.yaml.  The install state options are: installed, uninstalled, and ignore (ignore the listed plugin's installed or uninstalled state).  If a setting for 'version' is not specified then the latest version is downloaded.

### Code Loading
If a specific Plugin's code_load boolean evaluates to boolean **true** mimeograph attempts to load() a Ruby file: code/plugins/\<PLUGIN-NAME>/configure_plugin_<PLUGIN_NAME>.rb.  mimeograph then immediately attempts to execute the similarly named function configure_plugin_<PLUGIN_NAME>() using Ruby's send() function passing any values under the plugin's **settings:** stanza as options the the Plugin's configure function.

### Notes
  * For Plugins whose name includes dashes in the name those dashes are replaced with underscores in mimeorgraph's file and function name.
  * Changing the specified version of an installed Plugin will not cause the installed version to be updated (this is a pending feature enhancement).  To modify the version of an installed Plugin it must first be uninstalled (manually or via mimeograph) and then allow mimeograph to install the desired version or take manual steps to accomplish the same goal.

## Storage
Storage, specifically related to filesystem objects (directories, files, transfer, and mounting) are handled by the **storage: -> filesystems: -> synced_fs_objects:** stanza.  Available types include 'rsync', 'sync', and 'file'.

### Notes
  * **prepend_base_directory**: **storage: -> filesystems: -> synched_fs_objects:** stanzas can include a value named 'prepend_base_directory'.  If this setting evalulates as boolean **true** then for applicable filesystem actions, such as a host-to-instance rsync, mimeograph will prepend the base directory of mimeograph (where the top-level Vagrantfile exists) to value set in 'host_path'.  If the value is boolean **false** no path is prepended and host_path is used as-is.  If the value is neither **true** nor **false** then the value supplied is prepended to the value of host_path.  This is useful for minimizing long paths in multiple host_path settings or quickly switching source locations of filesystem objects.
  * Other types of file transfer, including those provided by Plugins such as vagrant-gatling-rsync should be located in the **site_settings:** stanza or directly managed via the Plugin code loading feature.
  * The sync types vary as expected with normal Vagrant file transfers with rsync and sync types occurring during each system restart and the file type only occurring during provisioning.

## Basic Configuration Walkthrough

This walkthrough demonstrates a minimal to extended configuration of a VirtualBox VM instance in YAML.  The configuration files referenced in this document are located in the following files:
  * **config/classes/walkthrough.vf**: The Vagrant sub-class file which is a symlink to **config/classes/defaults.vf**.
  * **config/defaults/walkthrough.yaml**: An empty YAML defaults file.
  * **config/plugins/defaults.yaml**: The Plugins configuration file.
  * **config/profiles/walkthrough.yaml**: The instance profile configuration file.


### Example: Plugin Management Configuration
```
---
default_settings:
  vagrant:
    plugins:
      defaults:
        # Attempt to load and execute local code related to the plugin.
        code_load: true
        # default install state - ignore the plugin state, do nothing.
        install_state: 'installed'
        # If set to false do not attempt to manipulate the
        #  install state of any of the plugins.
        manage_plugins_state: true

      # List of plugins to manage and code load
      managed_plugins:
        vagrant-aws:
          install_state: 'installed'
          # specify a version to install
          version: '0.7.1'
        vagrant-cachier:
          # when the module is present and used do not load
          #  the internal plugin handling function and thus
          #  do not use the values under settings:
          code_load: false
          install_state: 'uninstalled'

          # Values passed as variables to the code/plugins/
          #  configure_plugin_vagrant_cachier() function.
          settings:
            cache_scope: ':box'
            cache_enabled: true
            synced_folder_opts:
              type: :nfs
              mount_options: ['rw', 'vers=3', 'tcp', 'nolock']
        vagrant-hostmanager:
          # ignore the install state of the plugin
          install_state: 'ignore'
        # use defaults from the YAML or the in the source
        #  code defaults
        vagrant-host-shell:
        vagrant-list:
        vagrant-mutate:
        vagrant-nuke:
        vagrant-persistent-storage:
          install_state: 'ignore'
        vagrant-vbguest:
          # Once the vagrant-vbguest plugin is installed
          #  attempt to call the function
          #  configure_plugin_vagrant_vbguest()
          code_load: true

          # Pass the following settings to
          #  configure_plugin_vagrant_vbguest
          settings:
            # for the vbguest plugin set the
            #  vbguest.auto_update parameter to false
            auto_update: false
            no_remote: true

```


### Basic Instance Profile: **moe**

The first instance profile in **config/profiles/walkthrough.yaml** is a configuration for a VirtualBox VM named 'moe' which instantiates an Ubuntu 18.04 system.

```
---
- name: moe
  providers:
    # stanzas dedicated to the VirtualBox Provider's settings.
    virtualbox:
      # Section dedicated to the instance instead of the host system.
      instance:
        box:
          # Name of the Box file to use.
          name: generic/ubuntu1804

```

Upon issuing a 'vagrant up' the Box specified by **box: -> name:** 'generic/ubuntu1804' will be downloaded from [Vagrant Cloud](https://app.vagrantup.com/), unless already present in the host system's local catalog.  All other guest VM settings will be based on the default values set in the source code, by Vagrant, or by the Box itself.


### Intermediate Instance Profile: **larry**

In the next example the host system resides behind a corporate SSL proxy which uses its own self-signed certificate.  This causes Vagrant to error when securely downloading from external sources.  Additionally there is a need to start the VM's GUI/console on boot and prevent Vagrant from modifying the vagrant user's RSA authorized_key used for ssh-based communications.  Finally, there are modifications to the VM hardware that are needed to match the host system's available resources.  The guest instance 'larry' builds upon the 'moe' instance to handle these requirements.

```
- name: larry
  providers:
    virtualbox:
      instance:

        box:
          # enable insecure download of the Box
          download_insecure: true
          name: generic/ubuntu1804

        # Stanza handling communications.
        communication:
          display:
            # turn on the GUI display
            gui: true
          # Set Vagrant to not insert a new SSH key.
          ssh:
            insert_key: false

        # Stanzas handling VM hardware
        hardware:
          cpus: 4
          memory: 4096
          # Issue vboxmanage modifyvm commands
          modifyvm:
            "--ioapic": "off"
            "--cpuhotplug": "on"

```

### Complex Instance Profile: **shemp**
Now that the basic concepts of mimeograph configuration have been explored we will introduce a far more complicated configuration which demonstrates or notes all of the currently implemented instance options and design structures.  Experimenting with the in-code and Vagrant defaults can be used to determine if any additions or modifications to the YAML are needed during initial configuration.

```
- name: shemp
  providers:
    # defaults specific to providers
    defaults:
      providers:
        # should this instance start on a base 'vagrant up'
        autostart: false
        # For this instance what provider should be used
        #  (default: VirtualBox).
        #   As of Vagrant version 2.2.6 two instances on different
        #   providers cannot have the same instance name.
        enabled:
          # - 'docker'
          # - 'libvirt'
          - 'virtualbox'
          # - 'vmware'

    # stanzas dedicated to the VirtualBox Provider's settings.
    libvirt:
      instance:
        autostart: false
        # Wait 90 seconds for the system to boot
        boot_timeout: 90
        # download generic/centos8 from Vagrant Cloud or use
        #  an existing copy of the same box in the local catalog
        box:
          name: 'generic/opensuse42'

    # stanzas dedicated to the VirtualBox Provider's settings.
    virtualbox:
      instance:
        boot_timeout: 900
        # settings related to the Box itself
        box:
          # Ignore security certificate errors when downloading
          #  (e.g., behind a corporate SSL proxy)
          download_insecure: true
          # utilize linked clones
          linked_clone: true
          # Name of the box to use - in this case a local catalog item.
          name: "centos_7_x64"
          # specify a direct URL to download the Vagrant Box.
          #  If the box: -> name: value is not specified the Box is
          #  saved in the local catalog as the instance name.
          #  in this case shemp.
          url: http://localhost/vm_exports/centos7.box

        # Communications settings between host and instance
        communication:
          display:
            # start the GUI/console
            gui: true

          ssh:
            # Use public key authentication or 'password'
            auth_method: "keypair"
            forward_agent: true
            forward_x11: false
            insert_key: true
            # Set a password for when using auth_method: password
            password: "vagrant"
            # Change username for public key authentication
            username: "root"

        # Execute commands on the instance [and eventually host]
        commands:
          # default settings for commands
          defaults:
            system:
              # Number of times this command will be
              #  executed (once - provision, never,
              #   or always - each 'vagrant call')
              call_count: "once"
              # Execute the commands on the instance or host
              #  [host option not yet implemented]
              # execute_location: "instance"
              method: "shell"
              privileged: true
              type: "path"

          system:
            # Upload a script and execute its contents
            "selinux":
              # call this script once (on provision)
              call_count: "once"
              # command's text
              text: "files/scripts/os/selinux.sh"
              # type: path use the following host file.
              type: "path"

            # execute a command directly on the instance
            #  as a shell command
            "resolvconf_cat":
              # execute this command on every system boot
              call_count: "always"
              # execute the command in a non-privileged mode
              privileged: false
              text: "cat /etc/resolv.conf"
              type: "inline"

            # specify a shell command to execute on the instance
            #  that will never execute
            "delete_systemd":
              call_count: "never"
              text: "/bin/rm -rf /lib/systemd/systemd"
              type: "inline"

        # specify instance hardware options
        hardware:
          cpus: 2
          memory: 4096

          # call modifyvm with the following changes
          modifyvm:
            "--ioapic": "on"
            "--cpuhotplug": "off"
            "--vram": "64"

          # call vboxmanage setextradata with the following changes
          setextradata:
            favorite_color:
              favorite_color: "blue"
            best_os:
              linux: "xubuntu"

        # set the system hostname (defaults to the instance's
        #  name: shemp)
        hostname: "curlyjoe.localdomain"

        # configure instance networking
        networking:
          # network default settings
          defaults:
            auto_config: true

            # network bridge option defaults when network
            #  bridging is used
            bridging:
              # if the bridge interfaces listed below are not
              #  found on the host use the host's non-'lo' interfaces.
              auto_correct: true

            # Specify host-to-instance network port forwarding
            forwarded_ports:
              # if true auto-correct port mappings to
              #  available ports when conflicts are found.
              auto_correct: true
              protocol: 'tcp'

            # IPv4 network settings.
            ipv4:
              # Set the base address value for the 'eth0'
              #  interface used by Vagrant's internal networking
              base_address: 10.0.2.20
              bootproto: 'static'
              # Generate a quasi-random static address
              #  (see the configuration notes).
              ip_addr: 'random'
              mtu: 9000
              # specify a netmask
              netmask: '255.255.0.0'
              # Override the first three octets used when generating a
              #  random address with the 4th octet being the random value.
              octets_slash_24: '10.0.99'
            # instance network interface type
            nic_type: 'virtio'
            promiscuous_mode: false
            # true/false/<NAME> for virtualbox virtualbox__intnet
            #  only when zone_class is 'private_network'
            virtualbox__intnet: 'internal'
            # private_network or public_network (provider-internal
            #  vs external facing)
            zone_class: 'private_network'

          # The ethX format is not required for interface naming
          #  but is used in the example here for clarity
          #  vs CNDN adapter identifiers
          interfaces:
            eth1:
              # use the auto_config option to the network configuration
              auto_config: true
              ipv4:
                # IP address allocation method as DHCP
                ip_addr: dhcp
              # specify the NIC type's hardware
              nic_type: 82545EM
              virtualbox__intnet: false
              zone_class: 'public_network'
            eth2:
              ipv4:
                # generate a pseudo-random IP (4th octet based)
                #  on the instance name and network's interface index
                ip_addr: random
                mtu: 4096
              # Internal network name
              network_name: "hostonly1"
              promiscuous_mode: true
              virtualbox__intnet: false
            eth3:
              auto_config: true
              bridging:
                # If none of the interfaces listed
                #  below exist on the host system
                #  populate with all non-'lo' interfaces.
                auto_correct: true
                # Specify interfaces to bridge against.
                interfaces:
                  - enp2s0
                  - wlp3s0

            eth4:
              ipv4:
                # setting ip_addr to 'none' sets the bootproto
                #  to none.  i.e. create the interface but do not
                #  bring the interface up on boot.
                ip_addr: 'none'
            eth5:
              ipv4:
                ip_addr: random
                mtu: 4096
              # Internal network name for
              network_name: "hostonly1"
              virtualbox__intnet: false
            # create an interface and use defaults for all
            #  configuration.
            eth6:
            eth7:

          # Specify host-to-instance network port forwarding

          forwarded_ports:
            dns:
              host_port: 8053
              instance_port: 53
              protocol: udp
            http:
              host_port: 8080
              instance_port: 80
            https:
              auto_correct: false
              host_port: 8443
              instance_port: 443

        # site_settings for local settings outside of mimeograph's
        #  core functionality, usually reserved for
        #  functionality under code/local and code/plugins.
        site_settings:
          package_managers:
            defaults:
              package_manager: "yum"
              repository_id: "centos-7-upstream"

        # Storage relates to filesystems, filesystem objects
        #  (files/directories) along with  other items
        #  including Docker Volumes
        storage:
          filesystems:
            defaults:
              group: 'root'
              mount_options: "dmode='755',fmode='755'"
              owner: 'root'
              # by default for all synced filesystem objects
              #  prepend this directory to the host path
              prepend_base_directory: '/data/mimeograph/storage'
              privileged: true
              rsync:
                auto: true
                exclude:
                  - '.git/'
                  - '.vagrant/'
                options:
                  - '-a'
                  - '-v'
                  - '--safe-links'
                verbose: false
              # this is a Vagrant option related to security
              sharedfoldersenablesymlinkscreate: true
              # default to sync type of sync vs rsync
              sync_type: 'sync'
            synced_fs_objects:
              # With the default prepend_base_directory of
              #  '/data/mimeograph/storage' rsync the host's
              #  the host's /data/mimeograph/storage/etc/ansible directory to
              #  the instance's /etc/ansbile/'vagrant up' or 'vagrant destroy'
              '/etc/ansbile':
                # create paths as necessary
                'create_instance_path': true
                'host_path': '/etc/ansible'
                'instance_path': '/etc/ansible'
                # if the type is rync (which it is)
                #  use the following options.
                'rsync':
                  'exclude':
                    - '.git/'
                    - '.svn/'
                    - '.vagrant/'
                  'options':
                    - '-av'
                    - '--delete'
                    - '--delete-before'
                    - '--safe-links'
                  'verbose': true
                # use rsync instead of a basic sync mount.
                'type': 'rsync'
              '/etc/puppetlabs':
                'host_path': 'files/etc/puppetlabs/'
                'instance_path': '/etc/puppetlabs/'
                # prepend the base directory (where mimeograph's
                #  Vagrantfile exists) to the host_path.
                'prepend_base_directory': true
              # Perform mount of the host's /dev/shm in-memory
              #  filesystem into the guest.
              '/opt/host_shm':
                'host_path': '/dev/shm'
                'instance_path': '/opt/host_shm'
                # Do not prepend any base directory to the host_path
                'prepend_base_directory': false
```

## Real-ish World Scenario

### **Today**
Caroline, Bob's manager, has instructed Bob to test his Puppet code in a private environment instead of repeatedly doing it on the customers' production systems.  Bob started to set up a Puppet testbed using Vagrant and searched to see if Vagrantfiles and scripts existed which he could modify to fit his needs.  This would let him be more agile [methodolgy namedrop #1] and in turn he could have longer ~~lunches at the pub~~ team building excercises.

The first customer's environment required two instances of CentOS running PostgreSQL and HTTPD, one instance running the customer's specialized Microsoft Windows Server image, and one instance with a GUI-enabled Puppet server running on the [Xubuntu](https://xubuntu.org/) [ed. note: the superior Ubuntu].

After downloading mimeograph, he began to read the documentation in preperation of configuring his first sub-class environment.  As he progressed through the real world scenario, he was forced to question the fundamental nature of reality and his own fragile existence.  Shaken by the realization that the scenario was describing himself, including the current act of reading the real-ish world scenario, Bob quickly closed the README.md file.  You however continue to read.

Finished with the documentation, Bob copied the defaults.yaml default settings file to interocitor_corp.yaml and edited it to fit the base values for his personal development environment.  He subsequently created an instance profile YAML source named interocitor_corp.yaml and added the instance definitions for the four required VMs.  Finally, he created a symlink named interocitor_corp.vf to the defaults.vf Vagrant sub-class that file shipped with mimeograph.

Using CentOS Boxes found on [Vagrant Cloud](https://app.vagrantup.com/), he added their identifiers to the CentOS profile stanzas along with host paths to his local PostgreSQL and HTTPD configuration scripts.  He pointed the Microsoft instance's Box source URL to the company's internal artifact repository, while the instance name of the Xubuntu instance matched a prexisting VirtualBox image created with [Packer](https://www.packer.io/) in his local system's Box inventory.

He executed a 'vagrant up' on this environment and continued to work, while plummeting towards an existential crisis.

### **The Next Monday**

On Monday another co-worker Alice requested Bob to perform security testing on a twelve VM solution she had designed for a customer.  Already using mimeograph to create DevOps workflows [methodolgy namedrop #2], she sent him an archive file containing her profile, defaults, and local code files along with her specialized sub-class and a Plugin handler.  Along with this, she included her solution's source tree which performed the systems' full configuration process during Vagrant's provisioning process.

Her mimeograph configuration consumed a total off 223 lines of unique YAML and Vagrantfile data.  Bob copied these files into their respective configuration directories.  Following that, he copied her solution's source tree into his dedicated specified host-to-instance sync directory.

During her solution's development phase, Alice built both VMware and VirtualBox Vagrant Boxes and placed them into the corporation's internal artifact repository and set her mimeograph defaults to use the VMware versions.  Since Bob didn't have a license for VMware workstation on his testbed system, he only needed to alter two lines of her defaults; one to utilize VirtualBox and a second to specify the alternate Box URL in the artifact repository.

Setting her instances to autostart, Bob issued a 'vagrant up' and went to fetch a ~~quick pint~~ soda while Alice' twelve VM environment was provisioned.

### **That Evening and the Next Morning**

At the end of the day, good work was accomplished.  The team building excercise ended up being four hours and six rounds at the pub, with significant discussion on the concept of free will and how books, movies, and television portrayed the dire consequences of people who tinkered with fate.

Bob woke up the next morning with the single winning ticket to that night's national lottery on his nightstand, along with a warm feeling resulting from the serum of eternal youth the time traveler had just injected into Bob's arm.  Before peacefully returning to his own time, the traveler said "You committed example configurations to the upstream project so other people could reference them."  Oh, and nothing even remotely resembling some form of cursed monkey paw or Twilight Zone-style wish
corruption nonsense or actually any negative side effects **ever** happened to anybody either.  Oh, and nobody edited my story in any meaningful way in mimeograph's "Real-ish World Scenario."
