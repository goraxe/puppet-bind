# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'

# Implementation for the resource_record type using the Resource API.
class Puppet::Provider::ResourceRecord::ResourceRecord < Puppet::ResourceApi::SimpleProvider
  RNDC_KEY = '/etc/bind/rndc.key'
  ZONE_DIR = '/var/cache/bind'

  def get(context)
    results = []
    return results unless File.directory?(ZONE_DIR)

    Dir.glob(File.join(ZONE_DIR, 'db.*')).each do |zone_file|
      zone_name = File.basename(zone_file).sub(%r{^db\.}, '')
      context.debug("Querying zone #{zone_name} via AXFR")

      key_arg = File.exist?(RNDC_KEY) ? "-k #{RNDC_KEY}" : ''
      output = `dig @localhost #{zone_name} AXFR +noall +answer #{key_arg} 2>/dev/null`
      next unless $CHILD_STATUS&.success?

      output.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?(';')

        parts = line.split(%r{\s+}, 5)
        next if parts.length < 5

        fqdn = parts[0]
        ttl = parts[1]
        # parts[2] is class (IN)
        type = parts[3]
        data = parts[4]

        # Skip SOA records - managed by the zone itself
        next if type == 'SOA'

        # Extract record name from FQDN by removing the zone suffix
        zone_no_dot = zone_name.chomp('.')
        fqdn_no_dot = fqdn.chomp('.')
        record = if fqdn_no_dot == zone_no_dot
                   '@'
                 else
                   fqdn_no_dot.sub(%r{\.#{Regexp.escape(zone_no_dot)}$}, '')
                 end

        results << {
          ensure: 'present',
          record: record,
          zone: zone_no_dot,
          type: type,
          data: data.chomp('.'),
          ttl: ttl.to_s,
        }
      end
    end

    context.debug("Found #{results.length} resource records")
    results
  end

  def create(context, name, should)
    context.notice("Creating '#{name}' with #{should.inspect}")
    nsupdate(context, should, 'add')
  end

  def update(context, name, should)
    context.notice("Updating '#{name}' with #{should.inspect}")
    # Delete old record then add new one in a single nsupdate session
    zone = should[:zone]
    record = should[:record]
    type = should[:type]
    data = should[:data]
    ttl = should[:ttl]
    commands = "update delete #{record}.#{zone} #{type}\nupdate add #{record}.#{zone} #{ttl} #{type} #{data}\nsend"
    IO.popen('nsupdate', 'r+') do |io|
      io.puts(commands)
      io.close_write
      context.debug(io.read)
    end
  end

  def delete(context, name)
    context.notice("Deleting '#{name}'")
    nsupdate(context, name, 'delete')
  end

  def canonicalize(_context, resources)
    resources.each do |r|
      r[:type] = r[:type].upcase
      r[:ttl] = r[:ttl] || '3600'
    end
  end

  private

  def nsupdate(context, should, action)
    zone = should[:zone]
    record = should[:record]
    type = should[:type]
    data = should[:data]
    ttl = should[:ttl]
    cmd = "update #{action} #{record}.#{zone} #{ttl} #{type} #{data}\nsend"
    IO.popen('nsupdate', 'r+') do |io|
      io.puts(cmd)
      io.close_write
      context.debug(io.read)
    end
  end
end
