#
# Assert that source_value is one of the allowed values.
# Calls exit_with_message on failure.  Returns the value on success.
#
def validate_value(source_value, valid_values = [true, false, nil])
  exit_with_message("value [#{source_value.inspect}] is not valid. Accepted: #{valid_values.inspect}") \
    unless valid_values.include?(source_value)
  source_value
end
