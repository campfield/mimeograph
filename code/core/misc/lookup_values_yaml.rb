#
# General lookup code for searching for values within a YAML data structure.
#  (There is likely a better in-Ruby solution for this task.)
#
def lookup_values_yaml(
  source_yaml,
  search_array
)

  if source_yaml.nil? || source_yaml.empty? || search_array.nil? || search_array.empty?
    return nil
  end

  dig_results = source_yaml.dig(*search_array)

  if dig_results || (dig_results == false)
    return dig_results
  else
    return nil
  end

end
