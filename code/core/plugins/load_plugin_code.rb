#
# load_plugin_code.rb
#
# Loads per-plugin integration code from code/plugins/<plugin-name>/.
#
# A plugin's directory is loaded only when ALL of the following are true:
#
#   1. The plugin is listed in config/plugins/plugins.yaml with
#      ensure: present (or no ensure key, which defaults to present).
#   2. code/plugins/<plugin-name>/ exists.  The directory name must match the
#      plugin name exactly (e.g. code/plugins/vagrant-dns/).
#   3. Vagrant reports the plugin as installed in this run.  On the run that
#      first installs a plugin, Vagrant has not loaded it yet, so its code is
#      skipped with a warning and picked up on the next vagrant command.
#
# Plugins set to absent or ignore never have their code loaded, even if the
# plugin happens to be installed.
#
# Every *.rb file under the plugin directory (recursively, sorted by path) is
# required.  Files should only define functions and register hooks with
# register_plugin_hook; nothing should touch Vagrant at require time.
#
# The plugin's optional 'settings' hash from plugins.yaml is stored for
# plugin_settings / run_plugin_hooks.
#
# Returns the names of the plugins whose code was loaded.
#
PLUGIN_NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

def load_plugin_code(source_file, plugins_code_dir)
  return [] unless File.directory?(plugins_code_dir)

  # configure_plugins has already warned about a missing file or key.
  plugins = read_plugins_config(source_file, warn: false)
  return [] unless plugins

  loaded = []

  plugins.each do |plugin_name, plugin_info|
    plugin_info ||= {}
    name         = plugin_name.to_s

    next unless (plugin_info['ensure'] || 'present').to_s == 'present'

    # The name becomes a path component; refuse anything that could escape
    # code/plugins/.
    unless name =~ PLUGIN_NAME_PATTERN
      handle_message("plugin name [#{name}] is not a valid directory name - not loading plugin code.", 'WARNING')
      next
    end

    plugin_dir = File.join(plugins_code_dir, name)
    next unless File.directory?(plugin_dir)

    unless Vagrant.has_plugin?(name)
      handle_message("plugin [#{name}] is not loaded in this run - skipping [#{plugin_dir}]; it will be used on the next vagrant command.", 'WARNING')
      next
    end

    settings = plugin_info['settings'] || {}
    exit_with_message("plugins.yaml: [#{name}] settings must be a hash, got [#{settings.class}].") unless settings.is_a?(Hash)
    PLUGIN_SETTINGS[name] = settings

    Dir.glob(File.join(plugin_dir, '**', '*.rb')).sort.each { |f| require f }
    loaded << name
  end

  loaded
end
