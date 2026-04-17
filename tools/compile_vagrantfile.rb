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
#   3. Runs configure_all_instances and plugin configuration
#   4. Serializes every recorded Vagrant API call into a static Vagrantfile
#
# The compiled Vagrantfile has zero YAML parsing, zero file I/O for config,
# zero deep merging — just direct Vagrant API calls with literal values.
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

$vagrant_configs     = []
$vagrant_plugins     = {}

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

CODE_LOAD_DIRS = [
  "#{CODE_DIR}/core",
  "#{CODE_DIR}/local"
]

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

if File.file?(PLUGINS_CONFIG_FILE)
  yaml    = YAML.safe_load(File.read(PLUGINS_CONFIG_FILE))
  plugins = lookup_values_yaml(yaml, ['plugins'])
  if plugins
    plugins.each do |plugin_name, plugin_info|
      plugin_info ||= {}
      state = (plugin_info['ensure'] || 'present').to_s
      $vagrant_plugins[plugin_name] = (state == 'present')
    end
  end
end

# ============================================================================
# Run the mimeograph configuration engine against the mock
# ============================================================================

# vagrant-dns global TLD
if Vagrant.has_plugin?('vagrant-dns')
  Vagrant.configure(VAGRANT_VERSION) do |config|
    config.dns.tld = collect_vagrant_dns_tld
  end
end

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
      lines += serialize_proxy(entry[:proxy], indent, "#{var_name}.#{entry[:method]}")
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
output << "VAGRANT_VERSION = '2'"
output << ''

# Emit required host program checks
output << '#'
output << '# Verify required host programs'
output << '#'
output << "['rsync'].each do |prog|"
output << '  unless system("which #{prog} > /dev/null 2>&1")'
output << '    abort "[ERROR]: required host program [#{prog}] not found."'
output << '  end'
output << 'end'
output << ''

# Emit plugin management (static list derived from plugins.yaml)
enabled_plugins = $vagrant_plugins.select { |_, v| v }.keys
unless enabled_plugins.empty?
  output << '#'
  output << '# Required plugins'
  output << '#'
  enabled_plugins.each do |p|
    output << "# - #{p}"
  end
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

  if dns_tld_only?(config)
    tld = extract_tld(config)
    dns_tlds << tld unless dns_tlds.include?(tld)
  else
    instance_blocks << config
  end
end

# ── Emit deduplicated DNS TLD blocks ─────────────────────────────────────

unless dns_tlds.empty?
  output << '#'
  output << '# vagrant-dns TLD registration'
  output << '#'
  output << "if Vagrant.has_plugin?('vagrant-dns')"
  dns_tlds.each do |tld|
    output << "  Vagrant.configure(VAGRANT_VERSION) do |config|"
    output << "    config.dns.tld = #{tld.inspect}"
    output << "  end"
  end
  output << 'end'
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
