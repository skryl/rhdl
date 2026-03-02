# frozen_string_literal: true

require "digest"

module RHDL
  module Import
    module Checks
      class StimulusGenerator
        INPUT_DIRECTIONS = %w[input in inout].freeze

        class << self
          def generate(top_signature: nil, module_signature: nil, vectors:, seed:)
            signature = normalize_signature(top_signature || module_signature)
            vector_count = normalize_vector_count(vectors)
            rng = Random.new(derive_seed(seed, signature))
            input_ports = select_input_ports(signature)

            Array.new(vector_count) do |cycle|
              {
                cycle: cycle,
                inputs: build_inputs(input_ports, rng)
              }
            end
          end

          private

          def normalize_signature(signature)
            hash = signature.is_a?(Hash) ? signature : {}
            {
              name: value_for(hash, :name).to_s,
              ports: Array(value_for(hash, :ports))
            }
          end

          def normalize_vector_count(vectors)
            count = Integer(vectors)
            raise ArgumentError, "vectors must be >= 0" if count.negative?

            count
          rescue ArgumentError, TypeError
            raise ArgumentError, "vectors must be an integer >= 0"
          end

          def derive_seed(seed, signature)
            seed_int = Integer(seed)
            digest_hex = Digest::SHA256.hexdigest(canonical_string(signature))
            digest_int = digest_hex[0, 16].to_i(16)

            (seed_int ^ digest_int) & 0xFFFFFFFFFFFFFFFF
          rescue ArgumentError, TypeError
            raise ArgumentError, "seed must be an integer"
          end

          def select_input_ports(signature)
            Array(signature[:ports]).filter_map do |port|
              port_hash = port.is_a?(Hash) ? port : {}
              direction = value_for(port_hash, :direction).to_s.downcase
              next unless INPUT_DIRECTIONS.include?(direction)

              name = value_for(port_hash, :name).to_s
              next if name.empty?

              {
                name: name,
                width: normalize_width(value_for(port_hash, :width))
              }
            end
          end

          def build_inputs(input_ports, rng)
            input_ports.each_with_object({}) do |port, memo|
              max_value = (1 << port[:width]) - 1
              memo[port[:name]] = rng.rand(0..max_value)
            end
          end

          def normalize_width(width)
            value = Integer(width || 1)
            value.positive? ? value : 1
          rescue ArgumentError, TypeError
            1
          end

          def canonical_string(value)
            case value
            when Hash
              value
                .keys
                .map(&:to_s)
                .sort
                .map { |key| "#{key}:#{canonical_string(value_for(value, key))}" }
                .join("|")
            when Array
              value.map { |entry| canonical_string(entry) }.join(",")
            else
              value.to_s
            end
          end

          def value_for(hash, key)
            return hash[key] if hash.key?(key)

            string_key = key.to_s
            return hash[string_key] if hash.key?(string_key)

            symbol_key = key.to_sym
            return hash[symbol_key] if hash.key?(symbol_key)

            nil
          end
        end
      end
    end
  end
end
