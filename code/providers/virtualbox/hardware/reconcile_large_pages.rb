#
# Guarantee nested paging is on whenever modifyvm turns large pages on.
#
# Large pages depend on nested paging, so when large pages are on:
#   - nested paging not set  -> added as on, silently
#   - nested paging on       -> left as is, silently
#   - nested paging off      -> a warning is printed and it is turned on
#
# Returns the modifyvm hash to apply. The source hash is not modified.
#
def reconcile_large_pages(modifyvm, name = nil)
  return modifyvm unless modifyvm.is_a?(Hash)

  large_pages_key = modifyvm.keys.reverse.find { |k| normalize_modifyvm_flag(k) == 'largepages' }
  return modifyvm if large_pages_key.nil?
  return modifyvm unless parse_boolean(modifyvm[large_pages_key]) == true

  nested_paging_keys = modifyvm.keys.select { |k| normalize_modifyvm_flag(k) == 'nestedpaging' }

  # Nested paging not specified: add it, using the same flag spelling as the
  # large pages flag (hyphenated on VirtualBox 7, unhyphenated on older releases).
  if nested_paging_keys.empty?
    nested_paging_flag = large_pages_key.to_s.include?('large-pages') ? '--nested-paging' : '--nestedpaging'
    return modifyvm.merge(nested_paging_flag => 'on')
  end

  # Nested paging specified and already on under every spelling present.
  return modifyvm if nested_paging_keys.all? { |k| parse_boolean(modifyvm[k]) == true }

  off_key = nested_paging_keys.reverse.find { |k| parse_boolean(modifyvm[k]) != true }
  target  = name.to_s.empty? ? '' : " for [#{name}]"
  handle_message(
    "modifyvm [#{large_pages_key}] is on but [#{off_key}] is off#{target}. " \
    "Large pages require nested paging; turning [#{off_key}] on.",
    'WARNING'
  )

  # Correct every spelling of the flag that is present, so a later duplicate
  # (e.g. both --nested-paging and --nestedpaging) cannot switch it back off.
  modifyvm.each_with_object({}) do |(param, value), reconciled|
    reconciled[param] = normalize_modifyvm_flag(param) == 'nestedpaging' ? 'on' : value
  end
end