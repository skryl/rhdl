# HDL Buffer
# Non-inverting driver

module RHDL
  module HDL
    class Buffer < SimComponent
      port_input :a
      port_output :y

      behavior do
        y <= a
      end
    end
  end
end
