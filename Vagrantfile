#
# Top-level Vagrant file which handles function loading
#   Plugin management, and all subsequent code parsing
#   and mimeograph execution steps.
#
require 'deep_merge'
require 'find'
require 'resolv'
require 'rubygems'
require 'yaml'

VAGRANT_VERSION = '2'
Vagrant.require_version ">= #{VAGRANT_VERSION}"

BASE_DIR = File.dirname(__FILE__)
BOXES_CONFIG_DIR = "#{BASE_DIR}/config/boxes"
CODE_DIR = "#{BASE_DIR}/code"
CODE_DIRS = [
  "#{CODE_DIR}/core",
  "#{CODE_DIR}/local",
  "#{CODE_DIR}/upstream"
]
CONFIG_DIR = "#{BASE_DIR}/config"
INSTANCE_CLASSES_DIR = "#{CONFIG_DIR}/classes"
INSTANCE_DEFAULTS_DIR = "#{CONFIG_DIR}/defaults"
INSTANCE_PROFILES_DIR = "#{CONFIG_DIR}/profiles"
PLUGINS_CONFIG_DIR = "#{BASE_DIR}/config/plugins"
PLUGINS_DIR = "#{CODE_DIR}/plugins"
$plugins_managed_state = []
# This array avoids profile name collision
$profile_names_loaded = []
# If a provider's code was the last loaded do not
#  reload the same code again.
$provider_loaded_last = ''
PROVIDERS_DIR = "#{CODE_DIR}/providers"
RUBY_FILES_LOADED = []
SYSTEMS_PROGRAMS_HOST_REQUIRED = [
  'rsync'
]

#
# Load our various Ruby code files
#
CODE_DIRS.each do | code_dir |
  if File.directory?(code_dir)
    ruby_files = Find.find(code_dir)
    ruby_files and ruby_files.each do |ruby_file|
      require ruby_file if ruby_file=~/\.rb/
    end
  end
end

SYSTEMS_PROGRAMS_HOST_REQUIRED.each do | system_program_host |
  exit_with_message("required host executable [#{system_program_host}] not found.") unless system("which #{system_program_host} > /dev/null 2>&1")
end

configure_plugins("#{PLUGINS_CONFIG_DIR}/defaults.yaml")
configure_vagrant_boxes("#{BOXES_CONFIG_DIR}/defaults.yaml")

if File.directory?(INSTANCE_CLASSES_DIR)
  instance_classes = Dir.glob("#{INSTANCE_CLASSES_DIR}/*.vf")
  instance_classes.each do |instance_class|
    load instance_class
  end
else
  handle_message("no Vagrant sub-class files (SVF) found in [#{INSTANCE_CLASSES_DIR}].", "WARN")
end
