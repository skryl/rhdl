# HDL NOT Gate
# Single input inverter

module RHDL
  module HDL
    class NotGate < SimComponent
      input :a
      output :y

      behavior do
        y <= ~a
      end
    end
  end
end
