# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe Pilipinas::Postal do
  let(:file) { File.join(Pilipinas::DATA_DIR, 'postal.yml') }
  let(:rows) do
    [
      { 'region' => 'North', 'province' => 'Alpha', 'locality' => 'Santa Maria', 'zip_code' => '0123' },
      { 'region' => 'North', 'province' => 'Beta', 'locality' => 'Santa Maria', 'zip_code' => '2345' },
      { 'region' => 'South', 'province' => 'Alpha', 'locality' => 'Santa Maria', 'zip_code' => '4567' },
      { 'region' => 'North', 'province' => 'Alpha', 'locality' => 'Other Place', 'zip_code' => '0123' }
    ]
  end

  context 'with postal fixtures' do
    before { allow(Psych).to receive(:load_file).with(file).and_return(rows) }

    describe '.lookup' do
      it 'returns all repeated locality names with their independent parents' do
        entries = described_class.lookup(locality: 'Santa Maria')
        expect(entries.map(&:zip_code)).to eq(%w[0123 2345 4567])
        expect(entries).to be_frozen
      end

      it 'normalizes case and whitespace in every supplied label' do
        entries = described_class.lookup(locality: "\t SANTA   MARIA\n", province: ' ALPHA ', region: ' north ')
        expect(entries.map(&:zip_code)).to eq(['0123'])
        expect(entries).to be_frozen
      end

      it 'normalizes Unicode whitespace' do
        expect(described_class.lookup(locality: "Santa\u00a0Maria").size).to eq(3)
      end

      it 'uses either optional parent filter independently' do
        expect(described_class.lookup(locality: 'Santa Maria', province: 'Alpha').size).to eq(2)
        expect(described_class.lookup(locality: 'Santa Maria', region: 'North').size).to eq(2)
      end

      it 'requires every supplied filter to agree' do
        expect(described_class.lookup(locality: 'Other Place', province: 'Alpha', region: 'South')).to be_empty
      end

      it 'does not use aliases, fuzzy names, or geographic codes' do
        %w[Santa Sta. 17744].each do |locality|
          expect(described_class.lookup(locality: locality)).to be_empty
        end
      end

      it 'returns a frozen empty array for missing locality or parent labels' do
        expect(described_class.lookup(locality: 'Missing')).to be_frozen.and be_empty
        expect(described_class.lookup(locality: 'Santa Maria', province: 'Missing')).to be_frozen.and be_empty
      end
    end

    describe '.reverse_lookup' do
      it 'preserves distinct places sharing a ZIP and its leading zero' do
        entries = described_class.reverse_lookup(zip_code: '0123')
        expect(entries.map(&:locality)).to eq(['Santa Maria', 'Other Place'])
        expect(entries.map(&:zip_code)).to eq(%w[0123 0123])
        expect(entries).to be_frozen
      end

      it 'returns one entry for a unique ZIP and none for a missing ZIP' do
        expect(described_class.reverse_lookup(zip_code: '2345').map(&:province)).to eq(['Beta'])
        expect(described_class.reverse_lookup(zip_code: '9999')).to be_frozen.and be_empty
      end
    end

    it 'returns immutable entries with frozen strings in both directions' do
      entry = described_class.lookup(locality: 'Other Place').first
      expect(entry).to be_frozen
      %i[region province locality zip_code].each do |attribute|
        expect(entry.public_send(attribute)).to be_a(String).and be_frozen
      end
      expect(described_class.reverse_lookup(zip_code: '0123').last).to equal(entry)
      expect { entry.locality << ' changed' }.to raise_error(FrozenError)
      expect { described_class.reverse_lookup(zip_code: '0123') << entry }.to raise_error(FrozenError)
    end

    it 'builds both indexes once and reuses unfiltered frozen buckets' do
      forward = described_class.lookup(locality: 'Santa Maria')
      reverse = described_class.reverse_lookup(zip_code: '0123')
      expect(described_class.lookup(locality: 'santa maria')).to equal(forward)
      expect(described_class.reverse_lookup(zip_code: '0123')).to equal(reverse)
      expect(Psych).to have_received(:load_file).with(file).once
      expect(Pilipinas::Cache.keys).to eq(['index:Pilipinas::Postal'])
    end

    it 'excludes malformed source records instead of padding or inventing fields' do
      rows.push(
        nil,
        rows.first.merge('zip_code' => 'Cajidiocan'),
        rows.first.merge('zip_code' => '123'),
        rows.first.merge('zip_code' => 1234),
        rows.first.merge('region' => ''),
        rows.first.merge('province' => nil),
        rows.first.merge('locality' => "\xff".b.force_encoding('UTF-8'))
      )
      expect(described_class.lookup(locality: 'Santa Maria').size).to eq(3)
      expect(described_class.reverse_lookup(zip_code: '0123').size).to eq(2)
    end

    it 'handles an empty dataset' do
      allow(Psych).to receive(:load_file).with(file).and_return(nil)
      expect(described_class.lookup(locality: 'Santa Maria')).to be_frozen.and be_empty
      expect(described_class.reverse_lookup(zip_code: '0123')).to be_frozen.and be_empty
    end
  end

  context 'with malformed queries' do
    let(:invalid_text) { "\xff".b.force_encoding('UTF-8') }

    it 'rejects blank, non-string, or malformed labels without loading postal data' do
      [nil, '', " \t ", 123, Object.new, invalid_text, 'abc'.encode('UTF-16LE')].each do |locality|
        expect(described_class.lookup(locality: locality)).to be_frozen.and be_empty
      end
      expect(Pilipinas::Cache.keys).to be_empty
    end

    it 'rejects non-nil blank or malformed filters without loading postal data' do
      ['', ' ', 123, invalid_text].each do |value|
        expect(described_class.lookup(locality: 'Pandacan', province: value)).to be_empty
        expect(described_class.lookup(locality: 'Pandacan', region: value)).to be_empty
      end
      expect(Pilipinas::Cache.keys).to be_empty
    end

    it 'rejects ZIPs that are not exactly four ASCII digits in a string' do
      [nil, '', ' ', 1234, '123', '01234', ' 0123', "0123\n", '１２３４', invalid_text].each do |zip|
        expect(described_class.reverse_lookup(zip_code: zip)).to be_frozen.and be_empty
      end
      expect(Pilipinas::Cache.keys).to be_empty
    end
  end

  context 'with the bundled official snapshot' do
    it 'supports both directions using independent postal labels' do
      entries = described_class.lookup(locality: 'Pandacan', province: 'Metro Manila')
      expect(entries.map(&:zip_code)).to eq(['1011'])
      expect(described_class.reverse_lookup(zip_code: '1011')).to eq(entries)
      expect(entries.first.region).to eq('NCR (National Capital Region)')
    end

    it 'ships 958 distinct valid entries while preserving reviewed source gaps and labels' do
      records = Psych.load_file(file)
      expect(records.size).to eq(958)
      expect(records.uniq.size).to eq(958)
      expect(records).to all(include('zip_code' => match(/\A[0-9]{4}\z/)))
      expect(described_class.lookup(locality: 'Makati')).to be_empty
      expect(described_class.lookup(locality: 'Cajidiocan')).to be_empty
      expect(described_class.lookup(locality: 'Lantapan').first.province).to eq('Agusan del Norte')
    end

    it 'keeps requires and existing geography/downward flows free of postal data and code' do
      script = <<~RUBY
        require 'pilipinas'
        raise 'eager cache' unless Pilipinas::Cache.keys.empty?
        region = Pilipinas::Region.first
        province = region.provinces.first
        city = province.cities.first
        city.barangays
        raise 'postal cache loaded' if Pilipinas::Cache.keys.any? { |key| key.include?('Postal') }
        raise 'postal code loaded' if $LOADED_FEATURES.any? { |path| path.end_with?('/pilipinas/postal.rb') }
      RUBY
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', File.expand_path('../../lib', __dir__), '-e', script)
      expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
    end
  end
end
