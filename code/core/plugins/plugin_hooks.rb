#
# plugin_hooks.rb
#
# Hook registry for per-plugin integration code under code/plugins/<plugin-name>/.
#
# Plugin code never gets called by name from core or provider code.  Instead,
# each plugin directory registers blocks against a fixed set of phases, and
# the Vagrantfile, the providers and the compiler run whatever is registered.
# If a plugin's code is not loaded (see load_plugin_code), nothing is
# registered for it and every call site is a no-op.
#
# Phases and the arguments each block receives:
#
#   :global    once per run, from the Vagrantfile, after plugin code is loaded
#              and before any instance is processed.
#              block(settings)
#
#   :instance  once per instance, from each provider's configure_instance_*
#              (between networking and communication setup).
#              block(machine, instance_profile, provider, settings)
#
#   :compile   only from tools/compile_vagrantfile.rb.  Must return an Array of
#              Ruby source lines to embed verbatim in the compiled Vagrantfile,
#              for anything the recording proxy cannot capture (monkeypatches,
#              procs, ENV changes).
#              block(settings)
#
# settings is always the last argument: the plugin's 'settings' hash from
# config/plugins/plugins.yaml, or {} when none is given.
#
# Usage from code/plugins/<plugin-name>/*.rb:
#
#   register_plugin_hook('vagrant-foo', :instance) do |machine, profile, provider, settings|
#     configure_vagrant_foo(machine, profile, provider)
#   end
#
PLUGIN_HOOK_PHASES = %i[global instance compile].freeze
PLUGIN_HOOKS       = Hash[PLUGIN_HOOK_PHASES.map { |phase| [phase, []] }]
PLUGIN_SETTINGS    = {}

def register_plugin_hook(plugin_name, phase, &block)
  unless PLUGIN_HOOK_PHASES.include?(phase)
    exit_with_message("plugin [#{plugin_name}] hook phase [#{phase.inspect}] is not valid. Accepted: #{PLUGIN_HOOK_PHASES.inspect}")
  end
  exit_with_message("plugin [#{plugin_name}] registered a [#{phase}] hook without a block.") unless block

  PLUGIN_HOOKS[phase] << { plugin: plugin_name.to_s, block: block }
end

# Settings hash for a loaded plugin ({} when none were given or not loaded).
def plugin_settings(plugin_name)
  PLUGIN_SETTINGS.fetch(plugin_name.to_s, {})
end

# Run every block registered for phase, in registration order.  Returns the
# blocks' return values (used by the :compile phase).
def run_plugin_hooks(phase, *args)
  validate_value(phase, PLUGIN_HOOK_PHASES)

  PLUGIN_HOOKS[phase].map do |hook|
    hook[:block].call(*args, plugin_settings(hook[:plugin]))
  end
end
