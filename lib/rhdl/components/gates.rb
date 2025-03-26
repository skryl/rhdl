module RHDL
  module Components
    class And < Component
      def initialize(inputs = 2)
        @inputs = inputs
        (1..inputs).each { |i| input :"in#{i}" }
        output :out
      end
    end

    class Or < Component
      def initialize(inputs = 2)
        @inputs = inputs
        (1..inputs).each { |i| input :"in#{i}" }
        output :out
      end
    end

    class Nand < Component
      def initialize(inputs = 2)
        @inputs = inputs
        (1..inputs).each { |i| input :"in#{i}" }
        output :out
      end
    end

    class Nor < Component
      def initialize(inputs = 2)
        @inputs = inputs
        (1..inputs).each { |i| input :"in#{i}" }
        output :out
      end
    end

    class Xor < Component
      def initialize(inputs = 2)
        @inputs = inputs
        (1..inputs).each { |i| input :"in#{i}" }
        output :out
      end
    end

    class Xnor < Component
      def initialize(inputs = 2)
        @inputs = inputs
        (1..inputs).each { |i| input :"in#{i}" }
        output :out
      end
    end

    class Not < Component
      input :in1
      output :out
    end

    class Buffer < Component
      input :in1
      output :out
    end
  end
end
