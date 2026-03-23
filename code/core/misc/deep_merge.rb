#
# Native deep merge implementation — no external gem required.
#
# Adds deep_merge and deep_merge! to Hash.
#
# Behaviour:
#   - Recursively merges two Hashes. The argument (other_hash) wins on
#     any directly conflicting scalar value.
#   - When both sides have a Hash at the same key, they are merged recursively.
#   - When both sides have an Array at the same key, the argument's Array
#     replaces the receiver's (arrays are not concatenated).
#   - All other types (String, Integer, Boolean, nil) follow the same rule:
#     the argument wins.
#   - Neither the receiver nor the argument is mutated by deep_merge.
#     deep_merge! mutates the receiver in place.
#   - Non-Hash values passed as other_hash are ignored and the receiver
#     is returned unchanged.
#
# Usage:
#   merged = defaults.deep_merge(instance_profile)
#   # => instance_profile values win on conflict; stanzas are combined
#
class Hash
  def deep_merge(other_hash)
    dup.deep_merge!(other_hash)
  end

  def deep_merge!(other_hash)
    return self unless other_hash.is_a?(Hash)

    other_hash.each do |key, other_value|
      self_value = self[key]

      self[key] = if self_value.is_a?(Hash) && other_value.is_a?(Hash)
                    self_value.deep_merge(other_value)
                  else
                    other_value
                  end
    end

    self
  end
end
