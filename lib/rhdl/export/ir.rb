# Export intermediate representation for HDL code generation

module RHDL
  module Export
    module IR
      class ModuleDef
        attr_reader :name, :ports, :nets, :regs, :assigns, :processes, :reg_ports

        def initialize(name:, ports:, nets:, regs:, assigns:, processes:, reg_ports: [])
          @name = name
          @ports = ports
          @nets = nets
          @regs = regs
          @assigns = assigns
          @processes = processes
          @reg_ports = reg_ports
        end
      end

      class Port
        attr_reader :name, :direction, :width

        def initialize(name:, direction:, width:)
          @name = name
          @direction = direction
          @width = width
        end
      end

      class Net
        attr_reader :name, :width

        def initialize(name:, width:)
          @name = name
          @width = width
        end
      end

      class Reg
        attr_reader :name, :width

        def initialize(name:, width:)
          @name = name
          @width = width
        end
      end

      class Assign
        attr_reader :target, :expr

        def initialize(target:, expr:)
          @target = target
          @expr = expr
        end
      end

      class Process
        attr_reader :name, :clock, :sensitivity_list, :statements, :clocked

        def initialize(name:, statements:, clocked:, clock: nil, sensitivity_list: [])
          @name = name
          @statements = statements
          @clocked = clocked
          @clock = clock
          @sensitivity_list = sensitivity_list
        end
      end

      class SeqAssign
        attr_reader :target, :expr

        def initialize(target:, expr:)
          @target = target
          @expr = expr
        end
      end

      class If
        attr_reader :condition, :then_statements, :else_statements

        def initialize(condition:, then_statements:, else_statements: [])
          @condition = condition
          @then_statements = then_statements
          @else_statements = else_statements
        end
      end

      class Expr
        attr_reader :width

        def initialize(width:)
          @width = width
        end
      end

      class Signal < Expr
        attr_reader :name

        def initialize(name:, width:)
          @name = name
          super(width: width)
        end
      end

      class Literal < Expr
        attr_reader :value

        def initialize(value:, width:)
          @value = value
          super(width: width)
        end
      end

      class UnaryOp < Expr
        attr_reader :op, :operand

        def initialize(op:, operand:, width:)
          @op = op
          @operand = operand
          super(width: width)
        end
      end

      class BinaryOp < Expr
        attr_reader :op, :left, :right

        def initialize(op:, left:, right:, width:)
          @op = op
          @left = left
          @right = right
          super(width: width)
        end
      end

      class Mux < Expr
        attr_reader :condition, :when_true, :when_false

        def initialize(condition:, when_true:, when_false:, width:)
          @condition = condition
          @when_true = when_true
          @when_false = when_false
          super(width: width)
        end
      end

      class Concat < Expr
        attr_reader :parts

        def initialize(parts:, width:)
          @parts = parts
          super(width: width)
        end
      end

      class Slice < Expr
        attr_reader :base, :range

        def initialize(base:, range:, width:)
          @base = base
          @range = range
          super(width: width)
        end
      end

      class Resize < Expr
        attr_reader :expr

        def initialize(expr:, width:)
          @expr = expr
          super(width: width)
        end
      end
    end
  end
end
