#
# Load an instance profile YAML file from config/profiles/.
# Returns an array of instance hashes, or nil if the file is missing or empty.
#
def load_profiles(profile_name)
  profile_file = "#{INSTANCE_PROFILES_DIR}/#{file_basename(profile_name)}.yaml"

  unless File.file?(profile_file)
    handle_message("profile file [#{profile_file}] not found.", 'WARNING')
    return nil
  end

  content = YAML.safe_load(File.read(profile_file))
  (content.nil? || content.empty?) ? nil : content
end
