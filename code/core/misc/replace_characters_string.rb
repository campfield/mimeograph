#
# Bland functionfor replacing characters that can cause issues in filenames, VM names, and hostnames.
#
def replace_characters_string(
  source_string,
  conversion_hashes = {
    ' ' => '-',
    '/' => '-',
    '_' => '-',
  }
)

  target_string = nil

  if source_string
    if !source_string.is_a? String
      target_string = source_string.dup.to_s
    else
      target_string = source_string.dup
    end

    conversion_hashes.each do |original, target|
      target_string.gsub!(original, target)
    end
  end

  target_string

end
