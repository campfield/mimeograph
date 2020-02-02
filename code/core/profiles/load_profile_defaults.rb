#
# Load one of the profile defaults settings (part of the deep merge process) from the config/defaults directory.
#
def load_profile_defaults(
  instance_file = 'defaults',
  default_file = 'defaults',
  default_settings = {}
)

  [instance_file, default_file].each do | file_current |
    source_file = "#{INSTANCE_DEFAULTS_DIR}/" + file_basename(file_current) + ".yaml"
    return lookup_values_yaml(YAML::load(File.read(source_file)), ['default_settings']) if File.file?(source_file)
  end

  default_settings

end
