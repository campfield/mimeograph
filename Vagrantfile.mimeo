#
# mimeograph - Vagrant configuration engine
# Top-level Vagrantfile: loads code, manages plugins, and processes instance profiles.
#

require 'digest'
require 'find'
require 'resolv'
require 'yaml'

VAGRANT_VERSION = '2'
Vagrant.require_version ">= #{VAGRANT_VERSION}"

BASE_DIR      = File.dirname(__FILE__)
CODE_DIR      = "#{BASE_DIR}/code"
CONFIG_DIR    = "#{BASE_DIR}/config"

INSTANCE_DEFAULTS_DIR = "#{CONFIG_DIR}/defaults"
INSTANCE_PROFILES_DIR = "#{CONFIG_DIR}/profiles"
PLUGINS_CONFIG_FILE   = "#{CONFIG_DIR}/plugins/plugins.yaml"
PROVIDERS_DIR         = "#{CODE_DIR}/providers"

CODE_LOAD_DIRS = [
  "#{CODE_DIR}/core",
  "#{CODE_DIR}/local"
]

SYSTEMS_PROGRAMS_HOST_REQUIRED = ['rsync']

#
# Load core and local Ruby source files
#
CODE_LOAD_DIRS.each do |code_dir|
  next unless File.directory?(code_dir)
  Find.find(code_dir) do |f|
    require f if f =~ /\.rb$/
  end
end

#
# Verify required host programs are present
#
SYSTEMS_PROGRAMS_HOST_REQUIRED.each do |prog|
  exit_with_message("required host program [#{prog}] not found.") unless system("which #{prog} > /dev/null 2>&1")
end

#
# Manage Vagrant plugin install state from plugins.yaml
#
configure_plugins(PLUGINS_CONFIG_FILE)
#
# Configure the vagrant-dns resolver daemon TLD.
#
# The TLD controls which suffix the OS resolver delegates to the vagrant-dns
# daemon (via /etc/resolver/<tld> on macOS, systemd-resolved on Linux).
# Individual instance patterns are registered per-machine in
# configure_vagrant_dns.rb using the hostname already resolved by
# configure_vagrant_box — no extra YAML is needed for basic operation.
#
# Change this to match your lab's hostname suffix if it differs from 'local'.
# For example: 'test', 'vagrant', or 'lab'.
#
if Vagrant.has_plugin?('vagrant-dns')
  Vagrant.configure(VAGRANT_VERSION) do |config|
    config.dns.tld = collect_vagrant_dns_tld
  end
end


#
# Load and process all instance profiles
#
configure_all_instances
