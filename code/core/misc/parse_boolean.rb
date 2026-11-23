#
# Interpret an on/off style setting as a boolean.
#
# YAML loads unquoted on/off/yes/no/true/false as booleans and quoted ones as
# strings, so both forms are accepted, along with 1 and 0.
#
# Returns true (on), false (off), or nil when the value is not recognised
# (including nil itself), so callers can tell "off" apart from "not set".
#
def parse_boolean(value)
  case value.to_s.strip.downcase
  when 'on', 'true', 'yes', '1'  then true
  when 'off', 'false', 'no', '0' then false
  end
end
