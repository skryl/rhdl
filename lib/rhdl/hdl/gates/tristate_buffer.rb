# HDL Tristate Buffer
# Buffer with enable (high-Z output when disabled)

module RHDL
  module HDL
    class TristateBuffer < SimComponent
      port_input :a
      port_input :en
      port_output :y

      behavior do
        # Simplified: always output a when enabled, 0 when disabled
        # Full tristate support would require Z state in synthesis
        y <= mux(en, a, 0)
      end

      def propagate
        if in_val(:en) == 1
          out_set(:y, in_val(:a))
        else
          @outputs[:y].set(SignalValue::Z)
        end
      end
    end
  end
end
