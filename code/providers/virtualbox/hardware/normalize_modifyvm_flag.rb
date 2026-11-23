#
# Reduce a vboxmanage modifyvm flag to a comparable form so that both spellings
# VirtualBox accepts match:
#
#   '--large-pages'   / '--largepages'    -> 'largepages'
#   '--nested-paging' / '--nestedpaging'  -> 'nestedpaging'
#
def normalize_modifyvm_flag(param)
  param.to_s.strip.downcase.sub(/\A-+/, '').delete('-_')
end