#
# Load the instance profile YAML file.
#
def load_profiles(
  profile
)

  profile_file = INSTANCE_PROFILES_DIR + '/' + file_basename(profile) + '.yaml'

  return nil unless File.file?(profile_file)

  yaml_content = YAML::load(File.read(profile_file))

  if yaml_content.nil? or yaml_content.empty?
    return nil
  else
    yaml_content
  end

end
