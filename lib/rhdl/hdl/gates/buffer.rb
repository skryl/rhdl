# HDL Buffer
# Non-inverting driver

module RHDL
  module HDL
    class Buffer < Component
      input :a
      output :y

      behavior do
        y <= a
      end
    end
  end
end
