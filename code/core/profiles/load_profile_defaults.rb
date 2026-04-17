#
# Load default settings for a named profile group.
#
# Always loads config/defaults/defaults.yaml as the base.
# If a group-specific file (config/defaults/<group_name>.yaml) also exists,
# it is deep-merged on top — group-specific values win on conflict.
#
# This means bob.yaml only needs to contain the values that differ from the
# global defaults; everything else is inherited automatically.
#
# Returns the merged default_settings hash, or an empty hash if neither file
# exists or neither contains a default_settings key.
#
# The global defaults file is read once and cached for all subsequent calls.
#
GLOBAL_DEFAULTS_CACHE = { loaded: false, data: {} }

def load_profile_defaults(profile_name)
  global_file = "#{INSTANCE_DEFAULTS_DIR}/defaults.yaml"
  group_file  = "#{INSTANCE_DEFAULTS_DIR}/#{file_basename(profile_name)}.yaml"

  # Load global defaults once and cache the result
  unless GLOBAL_DEFAULTS_CACHE[:loaded]
    if File.file?(global_file)
      content = YAML.safe_load(File.read(global_file))
      GLOBAL_DEFAULTS_CACHE[:data] = lookup_values_yaml(content, ['default_settings']) || {}
    end
    GLOBAL_DEFAULTS_CACHE[:loaded] = true
  end

  base = GLOBAL_DEFAULTS_CACHE[:data].dup

  # If no group-specific file exists, or if the group file IS the global
  # defaults file (profile named 'defaults'), return the base as-is.
  return base if !File.file?(group_file) || group_file == global_file

  # Load group-specific defaults and merge on top of base.
  # Group values win; keys absent from group file are inherited from base.
  content = YAML.safe_load(File.read(group_file))
  group   = lookup_values_yaml(content, ['default_settings']) || {}

  return base if group.empty?

  base.deep_merge(group)
end
