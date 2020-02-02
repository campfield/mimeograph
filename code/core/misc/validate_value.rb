#
# Hard-exit, unforgiving, value validate function.  (There is likely a better in-Ruby solution for this task.)
#
def validate_value(
  source_value,
  valid_values = [
    'true',
    'false',
    true,
    false,
    nil
  ]
)

  exit_with_message("value [#{source_value}] not found in list of valid entries") unless valid_values.include?(source_value)

  source_value

end
