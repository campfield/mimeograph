# To Do
  * Finish VMware provider.
  * Plugin management sub-system should handle cases when the an installed version does not match the desired version.
  * Add 'host' as system execute command target.
  * Research options to resolve the O(n) performance issue after catalog passed off to Vagrant.  Likely utilize some form of parallelism or gating.
  * Resolve case where: 'name:' has restricted characters in sane way.
  * Enable an always-run File option which acts on each system action, not only provision.
  * Auth-by-password seems to have stopped working in Vagrant in general for certain actions.
  * Allow setting the values for message_titles_display used by the handle_message() function into a YAML setting.
