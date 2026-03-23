#
# active_machine.rb
#
# Determines whether a named instance is actively being managed in the
# current Vagrant invocation.
#
# During catalog compilation Vagrant evaluates every instance definition
# regardless of which machine is being targeted. This means checks that
# depend on host state (such as bridge interface presence) would fire for
# all instances, not just the ones being acted upon.
#
# Vagrant passes the target machine name(s) as the trailing positional
# arguments in ARGV after the subcommand, e.g.:
#
#   vagrant up myvm          -> ARGV = ['up', 'myvm']
#   vagrant up myvm1 myvm2   -> ARGV = ['up', 'myvm1', 'myvm2']
#   vagrant up               -> ARGV = ['up']          (all machines)
#   vagrant destroy -f myvm  -> ARGV = ['destroy', '-f', 'myvm']
#
# Returns true if the instance should be considered active — i.e. either
# no specific targets were named (meaning all instances are in scope) or
# this instance's name appears in the target list.
#
def active_machine?(instance_name)
  # Strip flags (anything starting with '-') from ARGV to get bare names
  targets = ARGV.reject { |a| a.start_with?('-') }

  # ARGV[0] is the subcommand (up, halt, destroy, etc.) — drop it
  targets = targets.drop(1)

  # No targets named means all machines are in scope
  return true if targets.empty?

  targets.include?(instance_name)
end
