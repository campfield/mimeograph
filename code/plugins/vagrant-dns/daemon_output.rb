#
# code/plugins/vagrant-dns/daemon_output.rb
#
# Controls the vagrant-dns daemon's output and log level.
#
# vagrant-dns starts its DNS server through the 'daemons' gem with
# log_output: true hard-coded in VagrantDNS::Service#run_options, so the
# daemon's stdout and stderr (one line per passthrough query, plus the
# RubyDNS/async console log) are appended without limit to
#
#   ~/.vagrant.d/tmp/dns/daemon/vagrant-dns.output
#
# vagrant-dns has no option for this.  VagrantDNS::Config.logger, which the
# vagrant-dns README still shows, is declared but never read anywhere in the
# plugin (its logger config was removed in v0.2.0).
#
# configure_daemon_output prepends a small wrapper onto
# VagrantDNS::Service#run_options so log_output follows the mimeograph
# setting.  With log_output false the daemons gem reopens the daemon's stdout
# and stderr on /dev/null.  The log level is set through CONSOLE_LEVEL, which
# the console gem (used by async and RubyDNS) reads when the daemon builds its
# logger; the daemon is forked from the vagrant process, so it inherits ENV.
#
# The setting takes effect the next time the daemon starts: vagrant dns
# --start / --restart, or vagrant up / reload (which restart it).  A daemon
# that is already running keeps its old output until then.
#
# This file must stay self-contained (no mimeograph helpers, no constants
# outside the module): tools/compile_vagrantfile.rb embeds it verbatim in
# compiled Vagrantfiles.
#
module MimeographVagrantDNS
  module DaemonOutput
    class << self
      attr_accessor :log_output
    end

    private

    def run_options(cmd, extra = {})
      super.merge(log_output: MimeographVagrantDNS::DaemonOutput.log_output ? true : false)
    end
  end

  # log_output: true keeps vagrant-dns's .output file, false sends it to
  #             /dev/null.
  # log_level:  console gem level name (debug|info|warn|error|fatal), or nil to
  #             leave CONSOLE_LEVEL alone.
  #
  # Returns false, changing nothing, when VagrantDNS::Service#run_options is
  # not there to wrap (plugin not loaded, or its internals have changed).
  def self.configure_daemon_output(log_output, log_level = nil)
    return false unless defined?(VagrantDNS::Service)
    return false unless VagrantDNS::Service.private_method_defined?(:run_options)

    DaemonOutput.log_output = log_output
    VagrantDNS::Service.prepend(DaemonOutput) unless VagrantDNS::Service.ancestors.include?(DaemonOutput)
    ENV['CONSOLE_LEVEL'] = log_level.to_s if log_level
    true
  end
end
