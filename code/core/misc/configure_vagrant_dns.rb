#
# configure_vagrant_dns.rb
#
# Registers vagrant-dns hostname entries for an instance when the vagrant-dns
# plugin is installed.  Derives all DNS data from existing instance profile
# fields — no additional YAML keys are required for basic operation.
#
# machine.vm.hostname is already set by configure_vagrant_box (using the
# 'hostname' key if present, or the sanitised instance name as fallback).
# This function reads that same data and maps it to machine.dns.patterns,
# which vagrant-dns uses to bind names to the instance's IP address.
#
# TLD RESOLUTION
# --------------
# The TLD is resolved with the same priority order as all other mimeograph
# settings.  Later levels override earlier ones:
#
#   1. Hardcoded fallback                →  'local'
#   2. config/defaults/defaults.yaml    →  default_settings.dns.tld
#   3. config/defaults/<group>.yaml     →  default_settings.dns.tld
#   4. Per-instance profile             →  providers.<provider>.instance.dns.tld
#
# Levels 2 and 3 arrive pre-merged into the root of instance_profile as
# instance_profile['dns']['tld'] because load_profile_defaults unwraps
# default_settings before the deep_merge in configure_all_instances.
# Level 4 sits at the standard per-instance provider path.
#
# If the resolved TLD differs from the global config.dns.tld already set in
# the Vagrantfile, an additional Vagrant.configure block is registered so the
# resolver daemon covers this TLD as well.
#
# Optional YAML keys (providers.<provider>.instance):
#
#   dns:
#     enabled: false         # Disable vagrant-dns config for this instance (default: true)
#     tld: 'test'            # Override the TLD for this instance (level 4 above)
#     cnames:                # Plain hostname aliases — patterns are built automatically
#       - 'web.local'
#       - 'api.local'
#     patterns:              # Raw patterns for advanced use (regexps or strings)
#       - 'alias.local'
#       - 'web.myhost.local'
#
def configure_vagrant_dns(machine, instance_profile, provider = 'virtualbox')
  return unless Vagrant.has_plugin?('vagrant-dns')

  box_config = lookup_values_yaml(instance_profile, ['providers', provider])
  return unless box_config

  name       = replace_characters_string(lookup_values_yaml(instance_profile, ['name']))
  dns_config = lookup_values_yaml(box_config, ['instance', 'dns'])

  # Honour per-instance opt-out via dns.enabled: false.
  if dns_config
    enabled = lookup_values_yaml(dns_config, ['enabled'])
    unless enabled.nil?
      validate_value(enabled)
      return unless enabled
    end
  end

  # ── TLD resolution ───────────────────────────────────────────────────────────
  # Priority: per-instance (level 4) → group/global defaults (levels 2-3) → fallback.
  #
  # Levels 2 and 3 land at instance_profile['dns']['tld'] after the deep_merge
  # in configure_all_instances (default_settings is unwrapped before merging).
  # Level 4 is at the standard providers.<provider>.instance.dns.tld path.
  tld = [
    lookup_values_yaml(dns_config, ['tld']),                           # level 4: per-instance
    lookup_values_yaml(instance_profile, ['dns', 'tld']),              # levels 2-3: group/global defaults
    'local'                                                            # level 1: hardcoded fallback
  ].find { |v| !v.nil? }

  # If this instance's TLD differs from whatever the Vagrantfile registered
  # globally, add a new configure block so the resolver daemon covers it.
  # Vagrant accumulates configure blocks; last-write-wins for attr_accessor
  # settings, so this effectively sets the "most specific" TLD active.
  Vagrant.configure(VAGRANT_VERSION) do |config|
    config.dns.tld = tld
  end

  # ── Hostname resolution ─────────────────────────────────────────────────────
  # Mirror the logic in configure_vagrant_box exactly so DNS entries match the
  # hostname the guest will actually report.
  hostname = [
    lookup_values_yaml(box_config, ['instance', 'hostname']),
    name.gsub(/[^a-z0-9\-]/i, '')
  ].find { |v| !v.nil? }

  return unless hostname && !hostname.empty?

  # ── FQDN construction ────────────────────────────────────────────────────────
  # Patterns must be built against the fully-qualified hostname.  When the
  # hostname has no domain suffix (bare name from instance name sanitisation),
  # the OS resolver appends the TLD before querying the vagrant-dns daemon, so
  # patterns using the bare name alone will never match.
  fqdn = hostname.include?('.') ? hostname : "#{hostname}.#{tld}"

  # ── Pattern registration ─────────────────────────────────────────────────────
  patterns = [
    /^#{Regexp.escape(fqdn)}$/,
    /^.*\.#{Regexp.escape(fqdn)}$/,
    fqdn
  ]

  # Append patterns for each cname — plain hostnames get the same FQDN
  # construction as the primary hostname (TLD appended if no dot present).
  cnames = dns_config ? lookup_values_yaml(dns_config, ['cnames']) : nil
  if cnames.is_a?(Array)
    cnames.each do |cname|
      cname_fqdn = cname.include?('.') ? cname : "#{cname}.#{tld}"
      patterns << /^#{Regexp.escape(cname_fqdn)}$/
      patterns << /^.*\.#{Regexp.escape(cname_fqdn)}$/
      patterns << cname_fqdn
    end
  end

  # Append any raw patterns declared under dns.patterns in the instance YAML.
  extra = dns_config ? lookup_values_yaml(dns_config, ['patterns']) : nil
  if extra.is_a?(Array)
    extra.each { |p| patterns << p }
  end

  machine.dns.patterns = patterns

  if active_machine?(name)
    handle_message("vagrant-dns: registered [#{fqdn}] (tld: #{tld})")
    patterns.each { |p| handle_message("vagrant-dns:   pattern: #{p}") }
  end
end
