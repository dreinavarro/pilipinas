# frozen_string_literal: true

module Pilipinas
  # Independent postal places from the bundled, partial PHLPost snapshot.
  module Postal
    EMPTY = [].freeze
    private_constant :EMPTY

    class Entry
      attr_reader :region, :province, :locality, :zip_code

      def initialize(region:, province:, locality:, zip_code:)
        @region = region.freeze
        @province = province.freeze
        @locality = locality.freeze
        @zip_code = zip_code.freeze
        freeze
      end
    end
    private_constant :Entry

    class << self
      # Return every exact locality match, optionally restricted by postal labels.
      # Labels ignore case and whitespace; an empty array means a snapshot gap.
      def lookup(locality:, province: nil, region: nil)
        locality_key = normalize(locality)
        return EMPTY unless locality_key
        return locality_bucket(locality_key) if province.nil? && region.nil?

        filtered_lookup(locality_key, province, region)
      end

      # Return every postal place with this four-digit string ZIP, without padding.
      def reverse_lookup(zip_code:)
        return EMPTY unless valid_zip?(zip_code)

        index[:by_zip].fetch(zip_code, EMPTY)
      end

      private

      def locality_bucket(locality_key)
        index[:by_locality].fetch(locality_key, EMPTY)
      end

      def filtered_lookup(locality_key, province, region)
        province_key = normalize(province)
        region_key = normalize(region)
        return EMPTY unless valid_filter?(province, province_key) && valid_filter?(region, region_key)

        locality_bucket(locality_key).select do |entry|
          (!province_key || normalize(entry.province) == province_key) &&
            (!region_key || normalize(entry.region) == region_key)
        end.freeze
      end

      def valid_filter?(value, key)
        value.nil? || key
      end

      def normalize(value)
        return unless text?(value)

        key = value.gsub(/[[:space:]]+/, ' ').strip.downcase
        key unless key.empty?
      end

      def text?(value)
        value.is_a?(String) && value.valid_encoding? && value.encoding.ascii_compatible?
      end

      def valid_zip?(value)
        text?(value) && /\A[0-9]{4}\z/.match?(value)
      end

      def index
        Cache.fetch('index:Pilipinas::Postal') { build_index }
      end

      def build_index
        rows = Psych.load_file(File.join(DATA_DIR, 'postal.yml')) || []
        entries = rows.filter_map { |row| build_entry(row) }
        {
          by_locality: buckets(entries) { |entry| normalize(entry.locality) },
          by_zip: buckets(entries, &:zip_code)
        }.freeze
      end

      def build_entry(row)
        return unless row.is_a?(Hash) && valid_zip?(row['zip_code'])
        return unless %w[region province locality].all? { |field| normalize(row[field]) }

        Entry.new(**row.slice('region', 'province', 'locality', 'zip_code').transform_keys(&:to_sym))
      end

      def buckets(entries, &)
        entries.group_by(&).transform_values(&:freeze).freeze
      end
    end
  end
end
