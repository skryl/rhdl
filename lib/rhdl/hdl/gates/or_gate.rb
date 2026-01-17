# HDL OR Gate
# 2 or more inputs

module RHDL
  module HDL
    class OrGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= a0 | a1
      end

      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        (@input_count - 2).times { |i| input :"a#{i + 2}" }
      end

      def propagate
        if @input_count == 2 && self.class.behavior_defined?
          execute_behavior
        else
          result = 0
          @input_count.times do |i|
            result |= (in_val(:"a#{i}") & 1)
          end
          out_set(:y, result)
        end
      end
    end
  end
end
