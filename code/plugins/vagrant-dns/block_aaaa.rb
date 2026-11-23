#
# code/plugins/vagrant-dns/block_aaaa.rb
#
# Makes the vagrant-dns daemon answer every AAAA (IPv6) query itself with an
# empty NOERROR response ("no IPv6 address for this name") instead of
# handling it with the plugin's normal rules.
#
# vagrant-dns only registers A records.  Without this, AAAA queries go to the
# plugin's fallback: with passthrough on (the default) every AAAA lookup for a
# VM name is forwarded to the upstream resolver, which is slow and, when the
# TLD is a real domain, leaks VM names upstream; with passthrough off, AAAA
# for a registered name fails with NOTIMP.  Resolvers do an A and an AAAA
# lookup for nearly every name, so this is half the daemon's traffic.
#
# Empty NOERROR (NODATA) is the correct "no IPv6 here" answer.  NXDOMAIN would
# claim the name does not exist at all, which some resolvers apply to the A
# record as well.
#
# The daemon only receives queries for the TLD(s) vagrant-dns is installed
# for, so this affects VM names only, not general host DNS.
#
# How it is installed: the DNS server code (RubyDNS) is only loaded inside the
# forked daemon, so there is nothing to patch at Vagrantfile load time.
# configure_block_aaaa wraps VagrantDNS::Service#start! instead.  Just before
# the daemon is forked, the wrapper loads RubyDNS in the vagrant process and
# prepends the AAAA filter onto RubyDNS::RuleBasedServer#process; the forked
# daemon inherits it.  vagrant-dns itself preloads its server this way on
# some macOS setups, so loading it before the fork is a supported path.
#
# Takes effect the next time the daemon starts (vagrant dns --start /
# --restart, vagrant up / reload).
#
# This file must stay self-contained (no mimeograph helpers, no constants
# outside the module): tools/compile_vagrantfile.rb embeds it verbatim in
# compiled Vagrantfiles.
#
module MimeographVagrantDNS
  # Prepended onto RubyDNS::RuleBasedServer, ahead of every vagrant-dns rule.
  module BlockAAAA
    def process(name, resource_class, transaction)
      if resource_class == Resolv::DNS::Resource::IN::AAAA
        transaction.fail!(:NoError)
        return
      end

      super
    end
  end

  # Prepended onto VagrantDNS::Service so the filter is installed only when
  # the daemon is actually started, not on every vagrant command.
  module BlockAAAAStart
    class << self
      attr_accessor :enabled
    end

    def start!(*args)
      MimeographVagrantDNS.install_block_aaaa if MimeographVagrantDNS::BlockAAAAStart.enabled
      super
    end
  end

  # Load RubyDNS and prepend the AAAA filter.  Returns false (and warns) when
  # RubyDNS cannot be loaded or no longer has the expected method.
  def self.install_block_aaaa
    begin
      require 'rubydns'
    rescue LoadError => e
      $stderr.puts "[WARNING]: vagrant-dns: block_aaaa not applied - cannot load rubydns (#{e.message})."
      return false
    end

    unless defined?(RubyDNS::RuleBasedServer) && RubyDNS::RuleBasedServer.method_defined?(:process)
      $stderr.puts '[WARNING]: vagrant-dns: block_aaaa not applied - RubyDNS::RuleBasedServer#process not found.'
      return false
    end

    RubyDNS::RuleBasedServer.prepend(BlockAAAA) unless RubyDNS::RuleBasedServer.ancestors.include?(BlockAAAA)
    true
  end

  # enabled: true answers all AAAA queries with NODATA; false leaves
  # vagrant-dns's own AAAA handling alone.
  #
  # Returns false, changing nothing, when VagrantDNS::Service#start! is not
  # there to wrap (plugin not loaded, or its internals have changed).
  def self.configure_block_aaaa(enabled)
    return false unless defined?(VagrantDNS::Service)
    return false unless VagrantDNS::Service.method_defined?(:start!)

    BlockAAAAStart.enabled = enabled
    VagrantDNS::Service.prepend(BlockAAAAStart) unless VagrantDNS::Service.ancestors.include?(BlockAAAAStart)
    true
  end
end
