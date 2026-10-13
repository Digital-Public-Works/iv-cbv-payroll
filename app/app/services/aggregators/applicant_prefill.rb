# fill partner applicant data based on payroll provider response, if we can.
# rules
# - attribute must be mapped in the database partner usage table
# - if there is already a value there (from landing page), don't overwrite
# - all completely synced resources have to have the same value, otherwise it is left for user to populate
# - value has to match the defined validation regex, or is left blank
# - provenance will be recorded as payroll_provider (not user-provided input)
module Aggregators
  class ApplicantPrefill
    SOURCE = CbvApplicant::PAYROLL_PROVIDER_SOURCE

    # normalized mapping field definitions
    def self.source_fields
      @source_fields ||= Aggregators::ResponseObjects::Identity.members
        .map { |field| "identity.#{field}" }
        .freeze
    end

    def self.source_field?(value)
      source_fields.include?(value.to_s)
    end

    def initialize(cbv_flow, identities)
      @cbv_flow = cbv_flow
      @applicant = cbv_flow.cbv_applicant
      @identities = Array(identities).compact
      @agency = ClientAgencyConfig.instance[cbv_flow.client_agency_id]
    end

    # Returns the attribute names this run changed.
    def call
      return [] if @applicant.nil? || @agency.nil?

      changed = @agency.prefillable_attributes.filter_map do |name, source_field|
        next unless writable?(name)

        apply(name, agreed_value(name, source_field))
      end

      @applicant.save! if changed.any?
      changed
    end

    private

    # Blank, or previously filled by this service. Anything a person supplied is
    # left alone.
    def writable?(name)
      @applicant.attribute_missing?(name) ||
        @applicant.provenance_for(name)&.dig("source") == SOURCE
    end

    # The single value every identity that has an opinion agrees on, or nil.
    def agreed_value(name, source_field)
      values = @identities.filter_map { |identity| usable_value(name, identity, source_field) }.uniq

      values.one? ? values.first : nil
    end

    def usable_value(name, identity, source_field)
      raw = read(identity, source_field)
      value = coerce(raw, @agency.applicant_attributes[name]&.data_type)
      return nil if value.nil?
      return nil unless matches_partner_format?(name, value)

      value
    end

    def read(identity, source_field)
      object, field = source_field.to_s.split(".", 2)
      return nil unless object == "identity" && identity.respond_to?(field)

      value = identity.public_send(field)
      value = value.compact.find(&:present?) if value.is_a?(Array)
      value.presence
    end

    def coerce(raw, data_type)
      return nil if raw.nil? || raw.to_s.strip.empty?

      case data_type.to_s
      when "date"    then parse_date(raw)
      when "integer" then Integer(raw.to_s, exception: false)
      when "float"   then Float(raw.to_s, exception: false)
      else raw.to_s.strip
      end
    end

    # Providers hand back ISO dates; the applicant-facing form uses US order.
    def parse_date(raw)
      return raw if raw.is_a?(Date)

      Date.iso8601(raw.to_s) rescue (Date.strptime(raw.to_s, "%m/%d/%Y") rescue nil)
    end

    def matches_partner_format?(name, value)
      @applicant.valid_format_for?(name, value)
    end

    def apply(name, value)
      return nil if @applicant.send(name) == value

      @applicant.public_send("#{name}=", value)

      if value.nil?
        @applicant.clear_attribute_provenance([ name ])
      else
        @applicant.record_attribute_provenance([ name ], source: SOURCE)
      end

      name
    end
  end
end
