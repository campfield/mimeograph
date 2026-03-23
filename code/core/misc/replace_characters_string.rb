#
# Replace characters that cause problems in VM names, hostnames, and filenames.
#
def replace_characters_string(
  source_string,
  replacements = { ' ' => '-', '/' => '-', '_' => '-' }
)
  return nil unless source_string
  result = source_string.to_s.dup
  replacements.each { |from, to| result.gsub!(from, to) }
  result
end
