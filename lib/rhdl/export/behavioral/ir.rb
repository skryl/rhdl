# Export intermediate representation for HDL code generation

module RHDL
  module Export
    module IR
      class ModuleDef
        attr_reader :name, :ports, :nets, :regs, :assigns, :processes, :reg_ports, :instances,
                    :memories, :write_ports

        def initialize(name:, ports:, nets:, regs:, assigns:, processes:, reg_ports: [], instances: [],
                       memories: [], write_ports: [])
          @name = name
          @ports = ports
          @nets = nets
          @regs = regs
          @assigns = assigns
          @processes = processes
          @reg_ports = reg_ports
          @instances = instances
          @memories = memories
          @write_ports = write_ports
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

      # Case expression for multi-way selection
      # Maps to Verilog case statement
      class Case < Expr
        attr_reader :selector, :cases, :default

        # @param selector [Expr] The expression to match against
        # @param cases [Hash{Array<Integer> => Expr}] Map of values to expressions
        # @param default [Expr, nil] Default expression if no match
        def initialize(selector:, cases:, default:, width:)
          @selector = selector
          @cases = cases
          @default = default
          super(width: width)
        end
      end

      # Sequential block with clock and optional reset
      # Maps to Verilog always @(posedge clk)
      class Sequential
        attr_reader :clock, :reset, :reset_values, :assignments

        # @param clock [Symbol] Clock signal name
        # @param reset [Symbol, nil] Reset signal name
        # @param reset_values [Hash{Symbol => Integer}] Values on reset
        # @param assignments [Array<Assign>] Register assignments
        def initialize(clock:, reset: nil, reset_values: {}, assignments: [])
          @clock = clock
          @reset = reset
          @reset_values = reset_values
          @assignments = assignments
        end
      end

      # Memory block for RAM/ROM inference
      # Maps to Verilog reg array
      class Memory
        attr_reader :name, :depth, :width, :read_ports, :write_ports

        # @param name [String] Memory array name
        # @param depth [Integer] Number of entries
        # @param width [Integer] Bits per entry
        # @param read_ports [Array<ReadPort>] Read port definitions
        # @param write_ports [Array<WritePort>] Write port definitions
        def initialize(name:, depth:, width:, read_ports: [], write_ports: [])
          @name = name
          @depth = depth
          @width = width
          @read_ports = read_ports
          @write_ports = write_ports
        end
      end

      # Memory read port
      class MemoryReadPort
        attr_reader :memory, :addr, :data, :enable

        def initialize(memory:, addr:, data:, enable: nil)
          @memory = memory
          @addr = addr
          @data = data
          @enable = enable
        end
      end

      # Memory write port (synchronous)
      class MemoryWritePort
        attr_reader :memory, :clock, :addr, :data, :enable

        def initialize(memory:, clock:, addr:, data:, enable:)
          @memory = memory
          @clock = clock
          @addr = addr
          @data = data
          @enable = enable
        end
      end

      # Memory read expression
      class MemoryRead < Expr
        attr_reader :memory, :addr

        def initialize(memory:, addr:, width:)
          @memory = memory
          @addr = addr
          super(width: width)
        end
      end

      # Module instance for structural design
      # Maps to Verilog module instantiation
      class Instance
        attr_reader :name, :module_name, :connections, :parameters

        # @param name [String] Instance name
        # @param module_name [String] Module/component type name
        # @param connections [Array<PortConnection>] Port connections
        # @param parameters [Hash{Symbol => Integer}] Parameter overrides
        def initialize(name:, module_name:, connections:, parameters: {})
          @name = name
          @module_name = module_name
          @connections = connections
          @parameters = parameters
        end
      end

      # Port connection for module instantiation
      # Maps to Verilog .port(signal)
      class PortConnection
        attr_reader :port_name, :signal

        # @param port_name [Symbol] Port name on the instance
        # @param signal [String, Expr] Signal to connect (name or expression)
        def initialize(port_name:, signal:)
          @port_name = port_name
          @signal = signal
        end
      end
    end
  end
end
