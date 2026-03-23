#
# Safely dig a value out of a nested YAML/Hash structure.
# Returns nil if any part of the path is missing or the source is empty.
#
def lookup_values_yaml(source, keys)
  return nil if source.nil? || keys.nil? || keys.empty?
  return nil unless source.respond_to?(:dig)
  return nil if source.respond_to?(:empty?) && source.empty?

  result = source.dig(*keys)
  # Preserve explicit false values; treat missing keys (nil) as not found
  (result.nil? == false || result == false) ? result : nil
end
