#
# collect_vagrant_dns_tld.rb
#
# Resolves the effective global TLD for the vagrant-dns resolver daemon by
# reading the YAML defaults stack in the same order as the rest of mimeograph.
#
# Resolution order (later wins on conflict):
#   1. Hardcoded fallback: 'local'
#   2. config/defaults/defaults.yaml  →  default_settings.dns.tld
#   3. config/defaults/<group>.yaml   →  default_settings.dns.tld
#
# Called from the Vagrantfile for the single global config.dns.tld entry.
# Per-instance and per-group overrides that differ from this value are
# registered from within configure_vagrant_dns as each instance is processed.
#
# The <group> argument is optional.  When omitted every group defaults file is
# scanned; the last file (alphabetically) that sets a value wins, which mirrors
# the sort order used by configure_all_instances.  Pass a specific group name
# when you want to scope the lookup to that group.
#
def collect_vagrant_dns_tld(group = nil, default_tld = 'local')
  tld = default_tld

  global_file = "#{INSTANCE_DEFAULTS_DIR}/defaults.yaml"
  if File.file?(global_file)
    content = YAML.safe_load(File.read(global_file)) || {}
    found   = lookup_values_yaml(content, ['default_settings', 'dns', 'tld'])
    tld     = found if found
  end

  # Build the list of group defaults files to check.
  group_files = if group
    ["#{INSTANCE_DEFAULTS_DIR}/#{group}.yaml"]
  else
    Dir.glob("#{INSTANCE_DEFAULTS_DIR}/*.yaml").sort.reject { |f| File.basename(f) == 'defaults.yaml' }
  end

  group_files.each do |group_file|
    next unless File.file?(group_file)
    content = YAML.safe_load(File.read(group_file)) || {}
    found   = lookup_values_yaml(content, ['default_settings', 'dns', 'tld'])
    tld     = found if found
  end

  tld
end
