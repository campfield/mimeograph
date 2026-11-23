#
# read_plugins_config.rb
#
# Reads config/plugins/plugins.yaml and returns the 'plugins' hash, or nil when
# the file or the 'plugins' key is missing.  Shared by configure_plugins,
# load_plugin_code and tools/compile_vagrantfile.rb so all three agree on what
# the file contains.
#
# Pass warn: false to suppress the missing-file / missing-key warnings when a
# caller that runs later in the same pass would only repeat them.
#
def read_plugins_config(source_file, warn: true)
  unless File.file?(source_file)
    handle_message("plugins configuration file [#{source_file}] not found - skipping plugin management.", 'WARNING') if warn
    return nil
  end

  yaml    = YAML.safe_load(File.read(source_file))
  plugins = lookup_values_yaml(yaml, ['plugins'])

  unless plugins.is_a?(Hash)
    handle_message('No plugins key found in plugins.yaml - skipping plugin management.', 'WARNING') if warn
    return nil
  end

  plugins
end
