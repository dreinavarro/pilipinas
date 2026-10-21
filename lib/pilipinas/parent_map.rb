# frozen_string_literal: true

module Pilipinas
  # Compact reverse index of the existing file-backed display hierarchy.
  # @api private
  module ParentMap
    def self.code_for(type, code)
      # Do not resolve entities inside Cache.fetch: their canonical indexes
      # acquire the same mutex when cold.
      mappings = Cache.fetch('parent_codes') do
        Psych.load_file(File.join(DATA_DIR, 'parent_codes.yml'), freeze: true)
      end
      mappings.fetch(type)[code]
    end
  end

  private_constant :ParentMap
end
