# frozen_string_literal: true

module Pilipinas
  # Represents a barangay (the smallest administrative division) of the
  # Philippines.
  #
  # Barangays belong to a {City} or municipality.
  #
  # @example
  #   Pilipinas::Barangay.count  # => 42_027
  #   Pilipinas::Barangay.find_by(name: "Casay")
  #
  class Barangay < Base
    # Returns the canonical parent in the bundled display hierarchy.
    #
    # @return [City, nil]
    def city
      parent_code = ParentMap.code_for('barangays', code)
      City.find_by(code: parent_code) if parent_code
    end

    class << self
      private

      # @return [String] absolute path to the barangays YAML file
      def data_file
        File.join(Pilipinas::DATA_DIR, 'barangays.yml')
      end
    end
  end
end
