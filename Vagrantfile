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
PLUGINS_CODE_DIR      = "#{CODE_DIR}/plugins"

CODE_LOAD_DIRS = [
  "#{CODE_DIR}/core",
  "#{CODE_DIR}/local"
]

SYSTEMS_PROGRAMS_HOST_REQUIRED = ['rsync']

#
# Load core and local Ruby source files.  code/plugins/ is deliberately not
# listed here; its directories are loaded selectively by load_plugin_code.
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
# Load per-plugin integration code from code/plugins/<plugin-name>/ and run
# its global hooks.
#
# A plugin's directory is loaded only when the plugin is ensure: present in
# plugins.yaml, the directory exists, and Vagrant reports the plugin as
# installed.  Plugin code registers hooks (code/core/plugins/plugin_hooks.rb);
# the :instance hooks run from each provider as instances are configured.
#
load_plugin_code(PLUGINS_CONFIG_FILE, PLUGINS_CODE_DIR)
run_plugin_hooks(:global)

#
# Load and process all instance profiles
#
configure_all_instances
