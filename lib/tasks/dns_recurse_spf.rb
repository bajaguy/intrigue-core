module Intrigue
module Task
class DnsRecurseSpf < BaseTask

  include Intrigue::Task::Dns

  def self.metadata
    {
      :name => "dns_recurse_spf",
      :pretty_name => "DNS SPF Recursive Lookup",
      :authors => ["markstanislav","jcran"],
      :description => "Check the SPF records of a domain (recursively) and create entities",
      :references => [
        "http://www.openspf.org/",
        "https://community.rapid7.com/community/infosec/blog/2015/02/23/osint-through-sender-policy-framework-spf-records"
      ],
      :allowed_types => ["Domain","DnsRecord"],
      :type => "discovery",
      :passive => true,
      :example_entities => [{"type" => "DnsRecord", "details" => {"name" => "intrigue.io"}}],
      :allowed_options => [],
      :created_types => ["IpAddress","Info","NetBlock"]
    }
  end

  def run
    super

    dns_name = _get_entity_name
    _log "Running SPF lookup on #{dns_name}"

    # Run a lookup on the entity
    lookup_txt_record(dns_name)
    _log "done!"

  end

  def lookup_txt_record(dns_name)

    begin

      result = resolve(dns_name, [Dnsruby::Types.TXT])

      # If we got a success to the query.
      if result
        _log_good "TXT lookup succeeded on #{dns_name}:"
        _log_good "Result:\n=======\n#{result.to_s}======"

        # Make sure there was actually a record
        unless result.answer.count == 0

          # Iterate through each answer
          result.answer.each do |answer|

            if answer.rdata.first =~ /^v=spf1/

              # We have an SPF record, so let's process it
              answer.rdata.first.split(" ").each do |data|

                _log "Processing SPF component: #{data}"

                if data =~ /^v=spf1/
                  next #skip!

                elsif data =~ /^include:.*/
                  spf_data = data.split(":").last
                  _create_entity "IpAddress", {"name" => spf_data}

                  # RECURSE!
                  lookup_txt_record spf_data

                elsif data =~ /^ip4:.*/
                  range = data.split(":").last

                  if data.include? "/"
                    _create_entity "NetBlock", {"name" => range }
                  else
                    _create_entity "IpAddress", {"name" => range }
                  end
                end
              end

            else  # store everything else as info
              _create_entity "Info", { "name" => "Non-SPF TXT Record for #{dns_name}", "content" => answer.to_s }
            end

          end

          _log "No more records"

        else
          _log "Lookup succeeded, but no records found"
        end
      else
        _log "Lookup failed, no result"
      end

    rescue Dnsruby::Refused
      _log_error "Lookup against #{dns_name} refused"

    rescue Dnsruby::ResolvError
      _log_error "Unable to resolve #{dns_name}"

    rescue Dnsruby::ResolvTimeout
      _log_error "Timed out while querying #{dns_name}."

    rescue Errno::ENETUNREACH => e
      _log_error "Hit exception: #{e}. Are you sure you're connected?"

    rescue Exception => e
      _log_error "Unknown exception: #{e}"
    end
  end


end
end
end
