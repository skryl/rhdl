# frozen_string_literal: true

module RHDL
  module Codegen
    module CIRCT
      module IR
        class Package
          attr_reader :modules

          def initialize(modules:)
            @modules = modules
          end
        end

        class ModuleOp
          attr_reader :name, :ports, :nets, :regs, :assigns, :processes, :instances,
                      :memories, :write_ports, :sync_read_ports, :parameters

          def initialize(name:, ports:, nets:, regs:, assigns:, processes:, instances: [],
                         memories: [], write_ports: [], sync_read_ports: [], parameters: {})
            @name = name
            @ports = ports
            @nets = nets
            @regs = regs
            @assigns = assigns
            @processes = processes
            @instances = instances
            @memories = memories
            @write_ports = write_ports
            @sync_read_ports = sync_read_ports
            @parameters = parameters
          end
        end

        class Port
          attr_reader :name, :direction, :width, :default

          def initialize(name:, direction:, width:, default: nil)
            @name = name
            @direction = direction
            @width = width
            @default = default
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
          attr_reader :name, :width, :reset_value

          def initialize(name:, width:, reset_value: nil)
            @name = name
            @width = width
            @reset_value = reset_value
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

        class Case < Expr
          attr_reader :selector, :cases, :default

          def initialize(selector:, cases:, default:, width:)
            @selector = selector
            @cases = cases
            @default = default
            super(width: width)
          end
        end

        class Memory
          attr_reader :name, :depth, :width, :read_ports, :write_ports, :initial_data

          def initialize(name:, depth:, width:, read_ports: [], write_ports: [], initial_data: nil)
            @name = name
            @depth = depth
            @width = width
            @read_ports = read_ports
            @write_ports = write_ports
            @initial_data = initial_data
          end
        end

        class MemoryRead < Expr
          attr_reader :memory, :addr

          def initialize(memory:, addr:, width:)
            @memory = memory
            @addr = addr
            super(width: width)
          end
        end

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

        class MemorySyncReadPort
          attr_reader :memory, :clock, :addr, :data, :enable

          def initialize(memory:, clock:, addr:, data:, enable: nil)
            @memory = memory
            @clock = clock
            @addr = addr
            @data = data
            @enable = enable
          end
        end

        class Instance
          attr_reader :name, :module_name, :connections, :parameters

          def initialize(name:, module_name:, connections:, parameters: {})
            @name = name
            @module_name = module_name
            @connections = connections
            @parameters = parameters
          end
        end

        class PortConnection
          attr_reader :port_name, :signal, :direction

          def initialize(port_name:, signal:, direction: :in)
            @port_name = port_name
            @signal = signal
            @direction = direction
          end
        end
      end
    end
  end
end
