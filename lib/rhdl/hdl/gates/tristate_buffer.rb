# HDL Tristate Buffer
# Buffer with enable (outputs 0 when disabled for synthesis compatibility)

module RHDL
  module HDL
    class TristateBuffer < SimComponent
      input :a
      input :en
      output :y

      behavior do
        # Note: Full tristate (Z state) would require special synthesis support
        # This implementation outputs 0 when disabled for synthesis compatibility
        y <= mux(en, a, lit(0, width: 1))
      end

      # Behavior block handles both simulation and synthesis
    end
  end
end
