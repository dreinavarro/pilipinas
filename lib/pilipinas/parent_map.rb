# frozen_string_literal: true

module Pilipinas
  # Compact reverse index of the existing file-backed display hierarchy.
  # @api private
  module ParentMap
    def self.code_for(type, code)
      return unless /\A[1-9][0-9]*\z/.match?(code)

      # Resolve canonical entities after Cache.fetch releases its mutex.
      tables = Cache.fetch('parent_codes') { load_tables }
      parents = tables.fetch(type)
      index = code.to_i
      parents[index] if index < parents.length
    end

    def self.load_tables
      mappings = Psych.load_file(File.join(DATA_DIR, 'parent_codes.yml'), freeze: true)
      mappings.transform_values do |codes|
        # The bundled internal IDs are compact positive integers. Keep a
        # separate table per child type so unrelated codes still resolve nil.
        parents = Array.new(codes.keys.map(&:to_i).max.to_i + 1)
        codes.each { |child, parent| parents[child.to_i] = parent }
        parents.freeze
      end.freeze
    end
    private_class_method :load_tables
  end

  private_constant :ParentMap
end
