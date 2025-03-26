module RHDL
  module Components
    class Multiplexer < Component
      def initialize(inputs = 2)
        @inputs = inputs
        @select_width = Math.log2(inputs).ceil

        # Input ports
        inputs.times do |i|
          input :"in#{i}"
        end

        # Select lines
        input :sel, width: @select_width
        output :out
      end
    end

    class Demultiplexer < Component
      def initialize(outputs = 2)
        @outputs = outputs
        @select_width = Math.log2(outputs).ceil

        # Input port
        input :in1

        # Select lines
        input :sel, width: @select_width

        # Output ports
        outputs.times do |i|
          output :"out#{i}"
        end
      end
    end

    class PriorityEncoder < Component
      def initialize(inputs = 8)
        @inputs = inputs
        @output_width = Math.log2(inputs).ceil

        # Input ports
        inputs.times do |i|
          input :"in#{i}"
        end

        # Output ports
        output :valid
        output :code, width: @output_width
      end
    end

    class Decoder < Component
      def initialize(width = 3)
        @width = width
        @outputs = 2**width

        # Input ports
        input :enable
        input :data, width: width

        # Output ports
        @outputs.times do |i|
          output :"out#{i}"
        end
      end
    end
  end
end
