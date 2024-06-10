# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'

# Implementation for the resource_record type using the Resource API.
class Puppet::Provider::ResourceRecord::ResourceRecord < Puppet::ResourceApi::SimpleProvider
  def get(context)
    context.notice("Getting with context: #{context.inspect}")
    # look in the /var/cache/bind/ directory for the zone files
    # parse out to a zone and attempt to zone xfer
    results = []
    Dir.glob('/var/cache/bind/db.*\.').each do |zone|
      context.notice("Zone: #{zone}")
      zone.gsub!('/var/cache/bind/db.', '')
      cmd = "dig +noall +answer -k /etc/bind/rndc.key @localhost #{zone} AXFR"
      IO.popen(cmd, 'r+') do |io|
        io.readlines do |line|

        context.notice(line)
        # parts has form <zone> <ttl> <class> <type> <data>
        (zone, ttl, dnsclass, type, data) = result.split("\t")
           results.push({ :zone => zone, :ttl => ttl, :class => dnsclass, :type => type, :data => data })
          end
      end
    end

    context.notice("Results: #{results.inspect}")
    return results
  end

  def create(context, name, should)
    context.notice("Creating '#{name}' with #{should.inspect}, context: #{context.inspect}")
    # pipe commands to nsupdate to update the zone
     zone = should[:zone]
     record = should[:record]
     type = should[:type]
     data = should[:data]
     ttl = should[:ttl]
     cmd = "update add #{record}.#{zone} #{ttl} #{type} #{data}\nsend"
     IO.popen('nsupdate', 'r+') do |io|
       io.puts(cmd)
       io.close_write
       context.notice(io.read)
     end
  end

  def update(context, name, should)
    context.notice("Updating '#{name}' with #{should.inspect}, context: #{context.inspect}")
    zone = should[:zone]
    record = should[:record]
    type = should[:type]
    data = should[:data]
    ttl = should[:ttl]
    cmd = "update delete #{record}.#{zone} #{ttl} #{type} #{data}\nsend"
    IO.popen('nsupdate', 'r+') do |io|
      io.puts(cmd)
      io.close_write
      context.notice(io.read)
      cmd = "update add #{record}.#{zone} #{ttl} #{type} #{data}\nsend"
      io.puts(cmd)
      io.close_write
      context.notice(io.read)
    end
  end

  def delete(context, name)
    context.notice("Deleting '#{name}', context: #{context.inspect}")
    zone = should[:zone]
    record = should[:record]
    type = should[:type]
    data = should[:data]
    ttl = should[:ttl]
    cmd = "update delete #{record}.#{zone} #{ttl} #{type} #{data}\nsend"
    IO.popen('nsupdate', 'r+') do |io|
      io.puts(cmd)
      io.close_write
      context.notice(io.read)
    end
  end

  def canonicalize(_context, resources)
    resources.each do |r|
      r[:record] = r[:record]
      r[:zone] = r[:zone]
      r[:type] = r[:type].upcase
      r[:data] = r[:data]
      r[:ttl] = r[:ttl] || 3600.to_s
    end
  end
end
