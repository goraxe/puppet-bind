# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'

# Implementation for the resource_record type using the Resource API.
class Puppet::Provider::ResourceRecord::ResourceRecord < Puppet::ResourceApi::SimpleProvider
  KEY_DIR = '/etc/bind/keys.d'
  ZONE_DIR = '/var/cache/bind'

  def get(context)
    results = []
    return results unless File.directory?(ZONE_DIR)

    key_file = find_key
    key_arg = key_file ? "-k #{key_file}" : ''

    Dir.glob(File.join(ZONE_DIR, 'db.*')).each do |zone_file|
      next if zone_file.end_with?('.jnl')

      zone_name = File.basename(zone_file).sub(%r{^db\.}, '')
      zone_name = "#{zone_name}." unless zone_name.end_with?('.')
      context.debug("Querying zone #{zone_name} via AXFR")

      output = `dig @localhost #{zone_name} AXFR +noall +answer #{key_arg} 2>/dev/null`
      next unless $CHILD_STATUS&.success?

      zone_no_dot = zone_name.chomp('.')

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

        # Skip SOA, TSIG, and RRSIG records
        next if %w[SOA TSIG RRSIG NSEC NSEC3 NSEC3PARAM DNSKEY].include?(type)

        fqdn_no_dot = fqdn.chomp('.')
        record = if fqdn_no_dot == zone_no_dot
                   '@'
                 else
                   fqdn_no_dot.sub(%r{\.#{Regexp.escape(zone_no_dot)}$}, '')
                 end

        # Skip records that don't belong to this zone
        next if record == fqdn_no_dot

        # Validate all namevars are present
        next if record.nil? || record.empty? || type.nil? || type.empty?

        title = "#{record}.#{zone_name} #{type}"
        context.debug("Found record: #{title} -> #{data}")

        results << {
          title: title,
          ensure: 'present',
          record: record,
          zone: zone_name,
          type: type,
          data: data,
          ttl: ttl.to_s,
        }
      end
    end

    context.debug("Found #{results.length} resource records")
    results
  end

  def create(context, name, should)
    context.notice("Creating '#{name}' with #{should.inspect}")
    run_nsupdate(context, should, 'add')
  end

  def update(context, name, should)
    context.notice("Updating '#{name}' with #{should.inspect}")
    zone = should[:zone]
    record = should[:record]
    type = should[:type]
    data = should[:data]
    ttl = should[:ttl]
    fqdn = build_fqdn(record, zone)
    commands = "server localhost\nupdate delete #{fqdn} #{type}\nupdate add #{fqdn} #{ttl} #{type} #{data}\nsend"
    key_file = find_key
    nsupdate_cmd = key_file ? ['nsupdate', '-k', key_file] : ['nsupdate']
    IO.popen(nsupdate_cmd, 'r+') do |io|
      io.puts(commands)
      io.close_write
      context.debug(io.read)
    end
  end

  def delete(context, name)
    context.notice("Deleting '#{name}'")
    run_nsupdate(context, name, 'delete')
  end

  def canonicalize(_context, resources)
    resources.each do |r|
      r[:type] = r[:type].upcase
      r[:ttl] = r[:ttl] || '3600'
      r[:zone] = "#{r[:zone]}." unless r[:zone].end_with?('.')
    end
  end

  private

  def find_key
    if File.directory?(KEY_DIR)
      key = Dir.glob(File.join(KEY_DIR, '*.key')).first
      return key if key
    end
    nil
  end

  def build_fqdn(record, zone)
    fqdn = record == '@' ? zone : "#{record}.#{zone}"
    fqdn = "#{fqdn}." unless fqdn.end_with?('.')
    fqdn
  end

  def run_nsupdate(context, should, action)
    zone = should[:zone]
    record = should[:record]
    type = should[:type]
    fqdn = build_fqdn(record, zone)
    if action == 'delete'
      cmd = "server localhost\nupdate delete #{fqdn} #{type}\nsend"
    else
      data = should[:data]
      ttl = should[:ttl]
      cmd = "server localhost\nupdate add #{fqdn} #{ttl} #{type} #{data}\nsend"
    end
    key_file = find_key
    nsupdate_cmd = key_file ? ['nsupdate', '-k', key_file] : ['nsupdate']
    IO.popen(nsupdate_cmd, 'r+') do |io|
      io.puts(cmd)
      io.close_write
      context.debug(io.read)
    end
  end
end
