# HDL NOT Gate
# Single input inverter

module RHDL
  module HDL
    class NotGate < SimComponent
      port_input :a
      port_output :y

      behavior do
        y <= ~a
      end
    end
  end
end
