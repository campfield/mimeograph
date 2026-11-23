#
# code/plugins/vagrant-dns/hooks.rb
#
# mimeograph integration for the vagrant-dns plugin.
#
# This directory is loaded by load_plugin_code only when vagrant-dns is set to
# ensure: present in config/plugins/plugins.yaml and Vagrant reports it as
# installed.  Everything vagrant-dns-specific lives here; core and provider
# code only run the hooks registered below.
#
#   :global    resolver TLD (config.dns.tld), passthrough, daemon output, log
#              level and AAAA blocking
#   :instance  per-instance hostname patterns (configure_vagrant_dns.rb)
#   :compile   embeds the daemon wrappers (daemon_output.rb, block_aaaa.rb) in
#              compiled Vagrantfiles
#
# The global TLD controls which suffix the OS resolver delegates to the
# vagrant-dns daemon (/etc/resolver/<tld> on macOS, systemd-resolved on
# Linux).  It comes from default_settings.dns.tld in the defaults stack (see
# collect_vagrant_dns_tld.rb); per-instance overrides are added by
# configure_vagrant_dns.
#
# Settings (config/plugins/plugins.yaml -> plugins.vagrant-dns.settings), all
# optional:
#
#   passthrough:   true     # true | false | unknown
#                           #   true:    forward every non-matching query upstream
#                           #   false:   answer only registered names
#                           #   unknown: forward only names with no pattern
#   daemon_output: false    # false: discard the daemon's stdout/stderr (/dev/null)
#                           # true:  keep vagrant-dns's default .output file
#   log_level:     fatal    # debug | info | warn | error | fatal
#                           # daemon log threshold (CONSOLE_LEVEL); fatal is quietest
#   block_aaaa:    true     # true:  answer every AAAA query with an empty
#                           #        NOERROR (no IPv6 address); never forwarded
#                           # false: vagrant-dns's own AAAA handling
#
VAGRANT_DNS_SETTING_DEFAULTS = {
  'passthrough'   => true,
  'daemon_output' => false,
  'log_level'     => 'fatal',
  'block_aaaa'    => true
}.freeze

VAGRANT_DNS_LOG_LEVELS = %w[debug info warn error fatal].freeze

# Self-contained files embedded verbatim by the :compile hook, in this order.
VAGRANT_DNS_EMBEDDED_FILES = [
  File.join(__dir__, 'daemon_output.rb'),
  File.join(__dir__, 'block_aaaa.rb')
].freeze

# Validate and normalise the vagrant-dns settings hash from plugins.yaml.
def vagrant_dns_settings(settings)
  unknown = settings.keys.map(&:to_s) - VAGRANT_DNS_SETTING_DEFAULTS.keys
  unless unknown.empty?
    handle_message("plugins.yaml: unknown vagrant-dns settings #{unknown.inspect} ignored. Accepted: #{VAGRANT_DNS_SETTING_DEFAULTS.keys.inspect}", 'WARNING')
  end

  merged = VAGRANT_DNS_SETTING_DEFAULTS.merge(settings)

  passthrough = merged['passthrough'].to_s.strip.downcase == 'unknown' ? :unknown : parse_boolean(merged['passthrough'])
  if passthrough.nil?
    exit_with_message("plugins.yaml: vagrant-dns passthrough [#{merged['passthrough'].inspect}] is not valid. Accepted: true, false, unknown")
  end

  daemon_output = parse_boolean(merged['daemon_output'])
  if daemon_output.nil?
    exit_with_message("plugins.yaml: vagrant-dns daemon_output [#{merged['daemon_output'].inspect}] is not valid. Accepted: true, false")
  end

  log_level = merged['log_level'].to_s.strip.downcase
  validate_value(log_level, VAGRANT_DNS_LOG_LEVELS)

  block_aaaa = parse_boolean(merged['block_aaaa'])
  if block_aaaa.nil?
    exit_with_message("plugins.yaml: vagrant-dns block_aaaa [#{merged['block_aaaa'].inspect}] is not valid. Accepted: true, false")
  end

  {
    passthrough:   passthrough,
    daemon_output: daemon_output,
    log_level:     log_level,
    block_aaaa:    block_aaaa
  }
end

register_plugin_hook('vagrant-dns', :global) do |settings|
  dns = vagrant_dns_settings(settings)

  Vagrant.configure(VAGRANT_VERSION) do |config|
    config.dns.tld = collect_vagrant_dns_tld
  end

  VagrantDNS::Config.passthrough = dns[:passthrough]

  unless MimeographVagrantDNS.configure_daemon_output(dns[:daemon_output], dns[:log_level])
    handle_message('vagrant-dns: daemon_output/log_level not applied - VagrantDNS::Service#run_options not found (plugin internals may have changed).', 'WARNING')
  end

  unless MimeographVagrantDNS.configure_block_aaaa(dns[:block_aaaa])
    handle_message('vagrant-dns: block_aaaa not applied - VagrantDNS::Service#start! not found (plugin internals may have changed).', 'WARNING')
  end
end

register_plugin_hook('vagrant-dns', :instance) do |machine, instance_profile, provider, _settings|
  configure_vagrant_dns(machine, instance_profile, provider)
end

register_plugin_hook('vagrant-dns', :compile) do |settings|
  dns = vagrant_dns_settings(settings)

  lines = []
  lines << '#'
  lines << '# vagrant-dns daemon output, log level and AAAA blocking'
  lines << '# (from code/plugins/vagrant-dns/daemon_output.rb and block_aaaa.rb)'
  lines << '#'
  lines << "if Vagrant.has_plugin?('vagrant-dns')"
  VAGRANT_DNS_EMBEDDED_FILES.each do |file|
    # Skip each file's leading comment header; the reference above points to it.
    source = File.readlines(file).map(&:chomp).drop_while { |line| line.start_with?('#') }
    source.each { |line| lines << (line.empty? ? '' : "  #{line}") }
    lines << ''
  end
  lines << "  MimeographVagrantDNS.configure_daemon_output(#{dns[:daemon_output]}, #{dns[:log_level].inspect})"
  lines << "  MimeographVagrantDNS.configure_block_aaaa(#{dns[:block_aaaa]})"
  lines << 'end'
  lines
end
