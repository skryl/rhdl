# frozen_string_literal: true

module RHDL
  module Import
    class BlackboxStubGenerator
      KNOWN_BLACKBOX_PORTS = {
        "altdpram" => {
          "data" => { direction: "input", width: "width" },
          "q" => { direction: "output", width: "width" },
          "wraddress" => { direction: "input", width: "widthad" },
          "rdaddress" => { direction: "input", width: "widthad" },
          "byteena" => { direction: "input", width: "width_byteena" }
        },
        "altsyncram" => {
          "address_a" => { direction: "input", width: "widthad_a" },
          "address_b" => { direction: "input", width: "widthad_b" },
          "data_a" => { direction: "input", width: "width_a" },
          "data_b" => { direction: "input", width: "width_b" },
          "byteena_a" => { direction: "input", width: "width_byteena_a" },
          "byteena_b" => { direction: "input", width: "width_byteena_b" },
          "q_a" => { direction: "output", width: "width_a" },
          "q_b" => { direction: "output", width: "width_b" }
        }
      }.freeze

      KNOWN_BLACKBOX_PARAMETERS = {
        "altdpram" => %w[
          indata_aclr indata_reg intended_device_family lpm_type
          outdata_aclr outdata_reg ram_block_type
          rdaddress_aclr rdaddress_reg rdcontrol_aclr rdcontrol_reg
          read_during_write_mode_mixed_ports
          width widthad width_byteena
          wraddress_aclr wraddress_reg wrcontrol_aclr wrcontrol_reg
        ],
        "altsyncram" => %w[
          operation_mode ram_block_type intended_device_family
          width_a widthad_a numwords_a outdata_aclr_a outdata_reg_a
          width_b widthad_b numwords_b outdata_aclr_b outdata_reg_b
          width_byteena_a width_byteena_b
          read_during_write_mode_mixed_ports read_during_write_mode_port_a read_during_write_mode_port_b
          address_reg_b indata_reg_b wrcontrol_wraddress_reg_b
          clock_enable_input_a clock_enable_input_b
          clock_enable_output_a clock_enable_output_b
          power_up_uninitialized
        ]
      }.freeze

      OUTPUT_PORT_NAME_PATTERNS = [
        /\Aq\z/i,
        /\Aq_[ab]\z/i,
        /\Aq[ab]\z/i,
        /\Adata_out\z/i,
        /\Adataout(?:_[ab])?\z/i,
        /\A(?:rd)?data(?:_[ab])?\z/i,
        /_out\z/i
      ].freeze

      class << self
        def generate(signatures:)
          new.generate(signatures: signatures)
        end
      end

      def generate(signatures:)
        Array(signatures).filter_map do |signature|
          normalized = normalize_signature(signature)
          next if normalized.nil?

          {
            name: normalized[:name],
            source: emit_source(normalized),
            dependencies: [],
            ports: normalized[:ports],
            instances: []
          }
        end.sort_by { |entry| entry[:name] }
      end

      private

      def normalize_signature(signature)
        hash = normalize_hash(signature)
        name = value_for(hash, :name).to_s
        return nil if name.empty?

        parameters = normalize_names(value_for(hash, :parameters))
        parameters = merge_known_parameters(module_name: name, parameters: parameters)

        {
          name: name,
          ports: infer_port_specs(
            module_name: name,
            ports: normalize_names(value_for(hash, :ports)),
            parameters: parameters
          ),
          parameters: parameters
        }
      end

      def normalize_names(values)
        Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
      end

      def infer_port_specs(module_name:, ports:, parameters:)
        known = known_port_hints(module_name)
        parameter_lookup = build_parameter_lookup(parameters)

        Array(ports).map do |port_name|
          hint = known[port_name.to_s.downcase] || {}
          width = resolve_port_width(hint[:width], parameter_lookup)
          {
            name: port_name.to_s,
            direction: (hint[:direction] || default_direction_for_port(port_name)).to_s,
            width: width
          }
        end
      end

      def known_port_hints(module_name)
        KNOWN_BLACKBOX_PORTS.fetch(module_name.to_s.downcase, {})
      end

      def build_parameter_lookup(parameters)
        Array(parameters).each_with_object({}) do |parameter, memo|
          token = parameter.to_s.strip
          next if token.empty?

          memo[token.downcase] = token
        end
      end

      def resolve_port_width(width_hint, parameter_lookup)
        return 1 if width_hint.nil?
        return width_hint if width_hint.is_a?(Integer) && width_hint > 0

        token = width_hint.to_s.strip
        return 1 if token.empty?
        return token.to_i if token.match?(/\A\d+\z/) && token.to_i.positive?

        parameter_lookup.fetch(token.downcase, 1)
      end

      def default_direction_for_port(port_name)
        token = port_name.to_s
        return "output" if OUTPUT_PORT_NAME_PATTERNS.any? { |pattern| pattern.match?(token) }

        "input"
      end

      def merge_known_parameters(module_name:, parameters:)
        known = KNOWN_BLACKBOX_PARAMETERS.fetch(module_name.to_s.downcase, [])
        (Array(parameters).map(&:to_s) + known).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
      end

      def emit_source(signature)
        lines = []
        lines << "# frozen_string_literal: true"
        lines << ""
        lines << "class #{class_name_for(signature[:name])} < RHDL::Component"
        lines << "  include RHDL::DSL::Behavior"
        lines << "  include RHDL::DSL::Structure"
        lines << "  self._ports = []"
        lines << "  self._signals = []"
        lines << "  self._constants = []"
        lines << "  self._processes = []"
        lines << "  self._assignments = []"
        lines << "  self._instances = []"
        lines << "  self._generics = []"
        lines << ""
        lines << "  # source_module: #{signature[:name]}"
        lines << "  # generated_blackbox_stub: true"
        lines << ""

        signature[:parameters].each do |parameter|
          lines << "  generic :#{parameter}, default: 0"
        end
        lines << "" unless signature[:parameters].empty?

        signature[:ports].each do |port|
          direction = normalize_port_direction(value_for(port, :direction))
          name = value_for(port, :name).to_s
          next if name.empty?

          width = value_for(port, :width)
          width_clause = ruby_width_clause(width)
          lines << "  #{direction} :#{name}#{width_clause}"
        end
        lines << "" unless signature[:ports].empty?

        output_ports = signature[:ports].select do |port|
          normalize_port_direction(value_for(port, :direction)) == "output"
        end
        unless output_ports.empty?
          output_ports.each do |port|
            name = value_for(port, :name).to_s
            next if name.empty?

            lines << "  assign :#{name}, 0"
          end
          lines << ""
        end

        lines << "end"
        lines << ""
        lines.join("\n")
      end

      def normalize_port_direction(direction)
        case direction.to_s.downcase
        when "out", "output"
          "output"
        when "inout"
          "inout"
        else
          "input"
        end
      end

      def ruby_width_clause(width)
        return "" if width.nil? || width.to_i == 1
        return ", width: #{width}" if width.is_a?(Integer)

        token = width.to_s.strip
        return "" if token.empty? || token == "1"

        ", width: :#{token}"
      end

      def class_name_for(module_name)
        tokens = module_name.gsub(/[^0-9A-Za-z]+/, "_").split("_").reject(&:empty?)
        candidate = tokens.map { |token| token[0].upcase + token[1..] }.join
        candidate = "ImportedModule" if candidate.empty?
        candidate = "M#{candidate}" if candidate.match?(/\A\d/)
        candidate = "Imported#{candidate}" if reserved_constant_name?(candidate)
        candidate
      end

      def reserved_constant_name?(name)
        Object.const_defined?(name)
      rescue NameError
        false
      end

      def normalize_hash(value)
        value.is_a?(Hash) ? value : {}
      end

      def value_for(hash, key)
        return nil unless hash.is_a?(Hash)

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
