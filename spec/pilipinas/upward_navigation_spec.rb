# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pure Ruby parent navigation' do
  let(:barangay) { Pilipinas::Barangay.find_by(code: '771') }

  it 'chains canonical frozen immediate parents without mutating the child' do
    original_variables = barangay.instance_variables
    city = barangay.city
    province = city.province
    region = province.region

    expect(city).to equal(Pilipinas::City.find_by(code: '770'))
    expect(province).to equal(Pilipinas::Province.find_by(code: '2'))
    expect(region).to equal(Pilipinas::Region.find_by(code: '1'))
    expect([barangay, city, province, region]).to all(be_frozen)
    expect(barangay.instance_variables).to eq(original_variables)
    expect { city.instance_variable_set(:@name, 'changed') }.to raise_error(FrozenError)
  end

  it 'preserves the Manila district display hierarchy' do
    expect(barangay.city.name).to eq('Pandacan')
    expect(barangay.city.barangays).to include(barangay)
    expect(Pilipinas::City.find_by(code: '3').barangays).to be_empty
  end

  it 'returns nil for unresolved codes at each level' do
    [Pilipinas::Barangay, Pilipinas::City, Pilipinas::Province].zip(%i[city province region]).each do |klass, method|
      unknown = klass.send(:new, code: 'unresolved', name: 'Unknown')
      expect(unknown.public_send(method)).to be_nil
    end
  end

  it 'reads only the map and canonical parent index on a cold upward lookup' do
    child = Pilipinas::Barangay.send(:new, code: '771', name: 'Barangay 833')
    allow(Psych).to receive(:load_file).and_call_original

    expect(child.city.code).to eq('770')
    expect(Pilipinas::Cache.keys).to contain_exactly('parent_codes', 'index:Pilipinas::City')
    expect(Psych).to have_received(:load_file)
      .with(File.join(Pilipinas::DATA_DIR, 'parent_codes.yml'), freeze: true).once
    expect(Psych).to have_received(:load_file).with(File.join(Pilipinas::DATA_DIR, 'cities.yml')).once
  end

  it 'uses cached maps and parent entities until the cache is cleared' do
    first = barangay.city
    allow(Psych).to receive(:load_file).and_call_original

    3.times { expect(barangay.city).to equal(first) }
    expect(Psych).not_to have_received(:load_file)

    Pilipinas::Cache.clear
    expect(Pilipinas::Cache.keys).to be_empty
    reloaded = barangay.city
    expect(reloaded).not_to equal(first)
    expect(reloaded).to equal(Pilipinas::City.find_by(code: '770'))
    expect(Psych).to have_received(:load_file)
      .with(File.join(Pilipinas::DATA_DIR, 'parent_codes.yml'), freeze: true).once
  end

  it 'keeps the cached parent map deeply frozen' do
    barangay.city
    map = Pilipinas::Cache.fetch('parent_codes') { raise 'expected a cached map' }

    expect(map).to be_frozen
    map.each_value do |codes|
      expect(codes).to be_frozen
      expect(codes.keys).to all(be_frozen)
      expect(codes.values).to all(be_frozen)
    end
  end

  it 'has one matching parent for every bundled child and no conflicting memberships' do
    relations = [
      [Pilipinas::Region, Pilipinas::Province, :provinces, :region, 'regions'],
      [Pilipinas::Province, Pilipinas::City, :cities, :province, 'provinces'],
      [Pilipinas::City, Pilipinas::Barangay, :barangays, :city, 'cities']
    ]
    relations.each do |parent_class, child_class, collection, parent_method, directory|
      assignments = {}
      parent_class.all.each do |parent|
        file = File.join(Pilipinas::DATA_DIR, directory, "#{parent.code}.yml")
        expect(File).to exist(file)
        (Psych.load_file(file) || []).each do |row|
          child = child_class.find_by(code: row.fetch(:code))
          expect(child).not_to be_nil
          expect(child.name).to eq(row.fetch(:name))
          expect(assignments).not_to have_key(child.code)
          expect(child.public_send(parent_method)).to equal(parent)
          assignments[child.code] = parent.code
        end
      end
      expect(assignments.keys).to match_array(child_class.all.map(&:code))
      cached = Pilipinas::Cache.fetch('parent_codes') { raise 'expected a cached map' }
      expect(cached.fetch(collection.to_s)).to eq(assignments)
    end
  end
end
