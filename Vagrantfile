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
# Configure vagrant-hostmanager to auto-populate /etc/hosts across all guests
#
if Vagrant.has_plugin?('vagrant-hostmanager')
  Vagrant.configure(VAGRANT_VERSION) do |config|
    config.hostmanager.enabled       = true
    config.hostmanager.manage_guest  = true
    config.hostmanager.manage_host   = false
    config.hostmanager.include_offline = false
    config.hostmanager.ip_resolver = proc do |vm, resolving_vm|
      read_ip = `vagrant ssh #{vm.name} -c "hostname -I" 2>/dev/null`
      read_ip.split.find { |ip| ip.start_with?("192.168.56") }
    end

  end
end

#
# Load and process all instance profiles
#
configure_all_instances
