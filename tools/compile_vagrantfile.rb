#!/usr/bin/env ruby
#
# compile_vagrantfile.rb — Compile mimeograph YAML into a static Vagrantfile
#
# Usage:
#   cd /path/to/mimeograph
#   ruby tools/compile_vagrantfile.rb > Vagrantfile.compiled
#
# What it does:
#   1. Mocks the Vagrant Ruby API with recording proxy objects
#   2. Loads all mimeograph code (YAML merging, provider config, etc.)
#   3. Runs configure_all_instances and resolves plugin state from plugins.yaml
#   4. Serializes every recorded Vagrant API call into a static Vagrantfile
#
# The compiled Vagrantfile has zero YAML parsing, zero file I/O for config,
# zero deep merging — just direct Vagrant API calls with literal values.
#
# The compiled file carries the same top-level steps as the real Vagrantfile,
# in the same order:
#   - Vagrant.require_version
#   - required host program checks
#   - plugin install/uninstall management (states baked in from plugins.yaml)
#   - vagrant-dns TLD registration and VagrantDNS::Config settings
#   - verbatim Ruby from plugin :compile hooks (code/plugins/<plugin-name>/)
#   - instance definitions
#
# Plugin integration code is loaded with the same rules as the real
# Vagrantfile (load_plugin_code): only for plugins that are ensure: present in
# plugins.yaml and have a code/plugins/<plugin-name>/ directory.
#
# Messages (including warnings such as the large-pages / nested-paging
# correction) are written to stderr at compile time, not into the output.
#

require 'digest'
require 'find'
require 'resolv'
require 'yaml'

# ============================================================================
# Recording proxy — captures all method calls for later serialisation
# ============================================================================

class ConfigProxy
  attr_reader :_log, :_name

  def initialize(name = 'root')
    @_name = name
    @_log  = []   # ordered list of every operation
    @_subs = {}   # cached sub-object proxies (e.g. .vm, .ssh, .dns)
  end

  def method_missing(name, *args, &block)
    name_s = name.to_s

    if block
      child = ConfigProxy.new(name_s)
      block.call(child)
      @_log << { type: :block, method: name, args: args, child: child }
      child
    elsif !args.empty? || name_s.end_with?('=')
      @_log << { type: :call, method: name, args: args }
      args.length == 1 ? args[0] : nil
    else
      # Sub-accessor (.vm, .ssh, .dns, .hostmanager, etc.)
      @_subs[name] ||= begin
        sub = ConfigProxy.new(name_s)
        @_log << { type: :sub, method: name, proxy: sub }
        sub
      end
    end
  end

  def respond_to_missing?(name, include_private = false)
    true
  end
end

# ============================================================================
# Mock Vagrant module — records all Vagrant.configure blocks
# ============================================================================

$vagrant_configs      = []
$vagrant_plugins      = {}   # plugin name => true when ensure is 'present'
$vagrant_plugin_specs = []   # [name, ensure, version] for present/absent plugins
$vagrant_dns_settings = {}   # VagrantDNS::Config class-level settings, in call order

module Vagrant
  def self.configure(version, &block)
    config = ConfigProxy.new('config')
    block.call(config)
    $vagrant_configs << { version: version, config: config }
  end

  def self.has_plugin?(name)
    $vagrant_plugins.fetch(name, false)
  end

  def self.require_version(*); end
end

# ============================================================================
# Mock VagrantDNS module — the engine sets class-level options on
# VagrantDNS::Config (e.g. passthrough), which is a plugin constant rather
# than part of the config object, so the recording proxy never sees it.
# Record those assignments here so they can be emitted into the compiled file.
# ============================================================================

module VagrantDNS
  class Config
    def self.method_missing(name, *args)
      name_s = name.to_s
      if name_s.end_with?('=')
        $vagrant_dns_settings[name_s.chomp('=')] = args[0]
      else
        $vagrant_dns_settings[name_s]
      end
    end

    def self.respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  # Stand-in for the plugin's daemon service so the vagrant-dns :global hook
  # can apply its daemon output and AAAA wrappers here without warning.  The
  # real wrappers reach the compiled file through the plugin's :compile hook.
  class Service
    def start!(*); end

    private

    def run_options(_cmd, extra = {})
      extra
    end
  end
end

# ============================================================================
# Set up mimeograph constants identical to the real Vagrantfile
# ============================================================================

VAGRANT_VERSION = '2'

BASE_DIR      = File.expand_path('..', __dir__)
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

# Sub-accessors that only exist when a plugin is installed.  The engine skips
# these at runtime when the plugin is missing, so the compiled file wraps them
# in the same has_plugin? check.
PLUGIN_GUARDED_SUBS = {
  dns:         'vagrant-dns',
  hostmanager: 'vagrant-hostmanager'
}

# ============================================================================
# Load mimeograph code (functions only — they use the mock Vagrant module)
# ============================================================================

CODE_LOAD_DIRS.each do |code_dir|
  next unless File.directory?(code_dir)
  Find.find(code_dir) do |f|
    require f if f =~ /\.rb$/
  end
end

# Also load all provider code up front (normally loaded per-instance)
Find.find(PROVIDERS_DIR) do |f|
  require f if f =~ /\.rb$/
end

# Override handle_message to write to stderr so it doesn't pollute
# the compiled Vagrantfile output on stdout.
def handle_message(message, title = 'INFO', display_levels = %w[ERROR INFO WARNING])
  title = title.to_s.upcase
  return unless display_levels.include?(title)
  if message.nil? || message.to_s.empty?
    $stderr.puts '[ERROR]: handle_message called with no message.'
  else
    $stderr.puts "[#{title}]: #{message}"
  end
end

# ============================================================================
# Determine which plugins to enable from plugins.yaml
# ============================================================================

# Mirrors configure_plugins: same file read, same ensure validation.  The
# install/uninstall actions themselves are not run here; they are emitted into
# the compiled Vagrantfile so they happen on the host that runs it.
plugins = read_plugins_config(PLUGINS_CONFIG_FILE)
if plugins
  plugins.each do |plugin_name, plugin_info|
    plugin_info ||= {}
    state = (plugin_info['ensure'] || 'present').to_s
    validate_value(state, %w[present absent ignore])
    $vagrant_plugins[plugin_name] = (state == 'present')
    next if state == 'ignore'

    version = plugin_info['version']
    $vagrant_plugin_specs << [plugin_name.to_s, state, version.nil? ? nil : version.to_s]
  end
end

# ============================================================================
# Run the mimeograph configuration engine against the mock
# ============================================================================

# Plugin integration code and its global hooks (vagrant-dns TLD, passthrough,
# ...), exactly as the Vagrantfile does.  The mock has_plugin? above answers
# true for every ensure: present plugin.
load_plugin_code(PLUGINS_CONFIG_FILE, PLUGINS_CODE_DIR)
run_plugin_hooks(:global)

# vagrant-hostmanager (recorded if plugin is enabled)
if Vagrant.has_plugin?('vagrant-hostmanager')
  # Hostmanager's ip_resolver uses a runtime proc — it cannot be compiled
  # into literal values.  We flag this block so the serialiser can emit it
  # as hand-written Ruby instead of trying to serialise the proc.
  $hostmanager_enabled = true
else
  $hostmanager_enabled = false
end

# Run all instance configuration
configure_all_instances

# ============================================================================
# Serialisation helpers
# ============================================================================

def val_to_ruby(val, indent = 0)
  case val
  when String  then val.inspect
  when Integer then val.to_s
  when Float   then val.to_s
  when true    then 'true'
  when false   then 'false'
  when nil     then 'nil'
  when Symbol  then ":#{val}"
  when Regexp  then val.inspect
  when Array
    if val.length <= 4 && val.all? { |v| v.is_a?(String) || v.is_a?(Integer) || v.is_a?(Symbol) || v.is_a?(Regexp) }
      "[#{val.map { |v| val_to_ruby(v) }.join(', ')}]"
    else
      pad = '  ' * (indent + 1)
      items = val.map { |v| "#{pad}#{val_to_ruby(v, indent + 1)}" }
      "[\n#{items.join(",\n")}\n#{'  ' * indent}]"
    end
  when Hash
    pairs = val.map do |k, v|
      key_s = k.is_a?(Symbol) ? "#{k}:" : "#{val_to_ruby(k)} =>"
      "#{key_s} #{val_to_ruby(v, indent)}"
    end
    if pairs.length <= 3
      "{ #{pairs.join(', ')} }"
    else
      pad = '  ' * (indent + 1)
      "{\n" + pairs.map { |p| "#{pad}#{p}" }.join(",\n") + "\n#{'  ' * indent}}"
    end
  else
    val.inspect
  end
end

# Format a method call with optional keyword-style hash as last arg
def format_call(pad, target, method, args)
  method_s = method.to_s

  # Special case: []= (hash-style assignment, e.g. vmw.vmx['key'] = value)
  if method_s == '[]='
    "#{pad}#{target}[#{val_to_ruby(args[0])}] = #{val_to_ruby(args[1])}"
  elsif method_s.end_with?('=')
    attr = method_s.chomp('=')
    "#{pad}#{target}.#{attr} = #{val_to_ruby(args[0])}"
  elsif args.empty?
    "#{pad}#{target}.#{method_s}"
  elsif args.length == 1 && args[0].is_a?(Hash) && !args[0].empty?
    # Single hash arg — emit as keyword args (no braces) to avoid
    # ambiguity with block syntax: foo cache: "none"  not  foo { cache: "none" }
    parts = args[0].map { |k, v| "#{k}: #{val_to_ruby(v)}" }
    "#{pad}#{target}.#{method_s} #{parts.join(', ')}"
  elsif args.length == 1
    "#{pad}#{target}.#{method_s} #{val_to_ruby(args[0])}"
  else
    # Check if last arg is a Hash (keyword args style)
    if args.last.is_a?(Hash) && !args.last.empty?
      positional = args[0...-1]
      kwargs     = args.last
      parts = positional.map { |a| val_to_ruby(a) }
      kwargs.each { |k, v| parts << "#{k}: #{val_to_ruby(v)}" }
      joiner = ",\n#{pad}  #{' ' * target.length}#{' ' * method_s.length}"
      "#{pad}#{target}.#{method_s} #{parts.join(joiner)}"
    else
      "#{pad}#{target}.#{method_s} #{args.map { |a| val_to_ruby(a) }.join(', ')}"
    end
  end
end

# Map block argument variable names to something readable
def block_var_name(method)
  case method.to_s
  when 'define'   then 'machine'
  when 'provider' then 'prov'
  else 'c'
  end
end

# Recursively serialise a ConfigProxy's log into Ruby source lines
def serialize_proxy(proxy, indent, var_name)
  lines = []
  pad   = '  ' * indent

  proxy._log.each do |entry|
    case entry[:type]
    when :call
      lines << format_call(pad, var_name, entry[:method], entry[:args])

    when :block
      bvar = block_var_name(entry[:method])
      args = entry[:args]
      # Emit trailing Hash as keyword args (no braces) to avoid
      # Ruby parsing ambiguity with the do...end block that follows.
      if !args.empty? && args.last.is_a?(Hash) && !args.last.empty?
        positional = args[0...-1]
        kwargs     = args.last
        parts = positional.map { |a| val_to_ruby(a) }
        kwargs.each { |k, v| parts << "#{k}: #{val_to_ruby(v)}" }
        args_str = ' ' + parts.join(', ')
      else
        args_str = args.map { |a| val_to_ruby(a) }.join(', ')
        args_str = ' ' + args_str unless args_str.empty?
      end
      lines << "#{pad}#{var_name}.#{entry[:method]}#{args_str} do |#{bvar}|"
      lines += serialize_proxy(entry[:child], indent + 1, bvar)
      lines << "#{pad}end"

    when :sub
      plugin    = PLUGIN_GUARDED_SUBS[entry[:method]]
      sub_name  = "#{var_name}.#{entry[:method]}"
      if plugin
        sub_lines = serialize_proxy(entry[:proxy], indent + 1, sub_name)
        unless sub_lines.empty?
          lines << "#{pad}if Vagrant.has_plugin?(#{plugin.inspect})"
          lines += sub_lines
          lines << "#{pad}end"
        end
      else
        lines += serialize_proxy(entry[:proxy], indent, sub_name)
      end
    end
  end

  lines
end

# Consolidate multiple provider blocks for the same provider into one
def consolidate_provider_blocks(proxy)
  # Find all :block entries for :provider in sub-proxies
  proxy._log.each do |entry|
    if entry[:type] == :sub
      consolidate_provider_blocks(entry[:proxy])
    elsif entry[:type] == :block
      consolidate_provider_blocks(entry[:child])
    end
  end

  # Merge consecutive or non-consecutive provider blocks with same args
  provider_groups = {}
  proxy._log.each_with_index do |entry, idx|
    if entry[:type] == :block && entry[:method] == :provider
      key = entry[:args].inspect
      provider_groups[key] ||= []
      provider_groups[key] << idx
    end
  end

  provider_groups.each do |_key, indices|
    next if indices.length <= 1
    # Merge all into the first, remove the rest
    first = proxy._log[indices[0]]
    indices[1..].reverse.each do |idx|
      donor = proxy._log[idx]
      first[:child]._log.concat(donor[:child]._log)
      proxy._log[idx] = nil  # mark for removal
    end
  end

  proxy._log.compact!
end

# ============================================================================
# Classify recorded Vagrant.configure blocks
# ============================================================================
#
# The mimeograph engine produces three kinds of Vagrant.configure blocks:
#
#   1. Global DNS TLD   — from the Vagrantfile and from configure_vagrant_dns
#                         (one per instance that sets config.dns.tld)
#   2. Instance defines — config.vm.define "name" do |machine| ... end
#   3. Other            — anything else (shouldn't happen normally)
#
# We want to:
#   - Deduplicate DNS TLD blocks into one per unique TLD value
#   - Add section comments with instance names
#   - Wrap DNS-only blocks in has_plugin? guards
#

# Helper: find the vm sub-proxy inside a config proxy
def find_vm_sub(config)
  entry = config._log.find { |e| e[:type] == :sub && e[:method] == :vm }
  entry ? entry[:proxy] : nil
end

# Helper: find a define block inside a vm sub-proxy
def find_define_block(config)
  vm = find_vm_sub(config)
  return nil unless vm
  vm._log.find { |e| e[:type] == :block && e[:method] == :define }
end

# Helper: check if a config block is DNS-TLD-only (config.dns.tld = "...")
def dns_tld_only?(config)
  return false unless config._log.length == 1
  entry = config._log[0]
  return false unless entry[:type] == :sub && entry[:method] == :dns
  dns_proxy = entry[:proxy]
  return false unless dns_proxy._log.length == 1
  call = dns_proxy._log[0]
  call[:type] == :call && call[:method] == :tld=
end

# Extract the TLD value from a DNS-TLD-only config block
def extract_tld(config)
  config._log[0][:proxy]._log[0][:args][0]
end

# ============================================================================
# Emit the compiled Vagrantfile
# ============================================================================

output = []
output << '#'
output << "# Compiled Vagrantfile — generated by mimeograph compile_vagrantfile.rb"
output << "# Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
output << "# Source:    #{BASE_DIR}"
output << '#'
output << "# This file contains no YAML parsing, no file I/O for config, and no"
output << "# deep merging.  All values are pre-resolved literals."
output << '#'
output << "# To regenerate after changing YAML configs:"
output << "#   cd #{BASE_DIR}"
output << '#   ruby tools/compile_vagrantfile.rb > Vagrantfile.compiled'
output << '#'
output << ''
output << "VAGRANT_VERSION = #{VAGRANT_VERSION.inspect}"
output << 'Vagrant.require_version ">= #{VAGRANT_VERSION}"'
output << ''

# Emit required host program checks
unless SYSTEMS_PROGRAMS_HOST_REQUIRED.empty?
  output << '#'
  output << '# Verify required host programs'
  output << '#'
  output << "#{val_to_ruby(SYSTEMS_PROGRAMS_HOST_REQUIRED)}.each do |prog|"
  output << '  unless system("which #{prog} > /dev/null 2>&1")'
  output << '    abort "[ERROR]: required host program [#{prog}] not found."'
  output << '  end'
  output << 'end'
  output << ''
end

# Emit plugin management.  The ensure state and version of every plugin are
# literals resolved from plugins.yaml at compile time; the install/uninstall
# actions match configure_plugins and run on the host using the compiled file.
unless $vagrant_plugin_specs.empty?
  output << '#'
  output << '# Manage Vagrant plugin install state (resolved from plugins.yaml)'
  output << '#'
  output << '['
  $vagrant_plugin_specs.each_with_index do |spec, idx|
    comma = idx == $vagrant_plugin_specs.length - 1 ? '' : ','
    output << "  [#{spec.map { |v| val_to_ruby(v) }.join(', ')}]#{comma}"
  end
  output << '].each do |plugin_name, ensure_state, version|'
  output << '  installed = Vagrant.has_plugin?(plugin_name)'
  output << ''
  output << "  if !installed && ensure_state == 'present'"
  output << '    version_flag = version ? "--plugin-version #{version}" : \'\''
  output << '    puts "[INFO]: installing plugin [#{plugin_name}]#{version ? " version [#{version}]" : \'\'}."'
  output << '    unless system("vagrant plugin install #{plugin_name} #{version_flag}".strip)'
  output << '      abort "[ERROR]: failed to install plugin [#{plugin_name}]."'
  output << '    end'
  output << "  elsif installed && ensure_state == 'absent'"
  output << '    puts "[INFO]: uninstalling plugin [#{plugin_name}]."'
  output << '    unless system("vagrant plugin uninstall #{plugin_name}")'
  output << '      abort "[ERROR]: failed to uninstall plugin [#{plugin_name}]."'
  output << '    end'
  output << '  end'
  output << 'end'
  output << ''
end

# Emit hostmanager block as hand-written Ruby (proc can't be serialised)
if $hostmanager_enabled
  output << '#'
  output << '# vagrant-hostmanager'
  output << '#'
  output << "if Vagrant.has_plugin?('vagrant-hostmanager')"
  output << "  Vagrant.configure(VAGRANT_VERSION) do |config|"
  output << "    config.hostmanager.enabled         = true"
  output << "    config.hostmanager.manage_guest     = true"
  output << "    config.hostmanager.manage_host      = false"
  output << "    config.hostmanager.include_offline   = false"
  output << ''
  output << '    hostmanager_ip_cache = {}'
  output << ''
  output << '    config.hostmanager.ip_resolver = proc do |vm, resolving_vm|'
  output << '      next hostmanager_ip_cache[vm.name] if hostmanager_ip_cache.key?(vm.name)'
  output << '      result = nil'
  output << '      if vm.id'
  output << '        info = `VBoxManage guestproperty enumerate #{vm.id} --patterns "/VirtualBox/GuestInfo/Net/*/V4/IP" 2>/dev/null`'
  output << '        ips  = info.scan(/value:\s+(\S+)/).flatten'
  output << '        result = ips.find { |ip| ip.start_with?("192.168.56") }'
  output << '      end'
  output << '      hostmanager_ip_cache[vm.name] = result'
  output << '      result'
  output << '    end'
  output << '  end'
  output << 'end'
  output << ''
end

# ── Pass 1: collect unique DNS TLDs and separate instance blocks ──────────

dns_tlds        = []   # unique TLD strings, order preserved
instance_blocks = []   # [name, config] pairs for instance definitions

$vagrant_configs.each do |vc|
  config = vc[:config]

  if config._log.empty?
    # Nothing was recorded on the config object (e.g. a block that only set a
    # VagrantDNS::Config option, which is captured in $vagrant_dns_settings).
    next
  elsif dns_tld_only?(config)
    tld = extract_tld(config)
    dns_tlds << tld unless dns_tlds.include?(tld)
  else
    instance_blocks << config
  end
end

# ── Emit deduplicated DNS TLD blocks ─────────────────────────────────────

unless dns_tlds.empty? && $vagrant_dns_settings.empty?
  output << '#'
  output << '# vagrant-dns TLD registration and plugin settings'
  output << '#'
  output << "if Vagrant.has_plugin?('vagrant-dns')"
  dns_tlds.each do |tld|
    output << "  Vagrant.configure(VAGRANT_VERSION) do |config|"
    output << "    config.dns.tld = #{tld.inspect}"
    output << "  end"
  end
  $vagrant_dns_settings.each do |setting, value|
    output << "  VagrantDNS::Config.#{setting} = #{val_to_ruby(value)}"
  end
  output << 'end'
  output << ''
end

# ── Emit verbatim Ruby from plugin :compile hooks ────────────────────────

run_plugin_hooks(:compile).each do |lines|
  next unless lines.is_a?(Array) && !lines.empty?
  output += lines
  output << ''
end

# ── Emit instance definitions ────────────────────────────────────────────

instance_blocks.each do |config|
  # Consolidate multiple provider blocks into one per provider
  consolidate_provider_blocks(config)

  # Extract instance name from config.vm.define for the section comment
  define_entry  = find_define_block(config)
  instance_name = define_entry ? define_entry[:args][0] : nil

  output << "# --- Instance: #{instance_name} ---" if instance_name
  output << "Vagrant.configure(VAGRANT_VERSION) do |config|"
  lines = serialize_proxy(config, 1, 'config')
  output += lines
  output << 'end'
  output << ''
end

puts output.join("\n")