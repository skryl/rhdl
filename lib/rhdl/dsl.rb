# Enhanced RHDL DSL
# Ruby-esque block-style syntax for hardware description

require 'active_support/concern'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/string/inflections'

module RHDL
  module DSL
    extend ActiveSupport::Concern

    # Module/entity mixin for classes
    included do
      class_attribute :_ports, :_signals, :_constants, :_processes
      class_attribute :_assignments, :_instances, :_generics

      self._ports = []
      self._signals = []
      self._constants = []
      self._processes = []
      self._assignments = []
      self._instances = []
      self._generics = []
    end

    class_methods do
      # Define a generic parameter
      def generic(name, type: :integer, default: nil)
        _generics << { name: name, type: type, default: default }
        define_method(name) { instance_variable_get("@#{name}") || default }
      end

      # Define an input port
      def input(name, width: 1, default: nil)
        port = Port.new(name, :in, width, default: default)
        _ports << port
        define_method(name) { SignalRef.new(name, width: width, component: self) }
      end

      # Define an output port
      def output(name, width: 1, default: nil)
        port = Port.new(name, :out, width, default: default)
        _ports << port
        define_method(name) { SignalRef.new(name, width: width, component: self) }
      end

      # Define a bidirectional port
      def inout(name, width: 1)
        port = Port.new(name, :inout, width)
        _ports << port
        define_method(name) { SignalRef.new(name, width: width, component: self) }
      end

      # Define an internal signal
      def signal(name, width: 1, default: nil)
        sig = Signal.new(name, width, default: default)
        _signals << sig
        define_method(name) { SignalRef.new(name, width: width, component: self) }
      end

      # Define a constant
      def constant(name, width:, value:)
        const = Constant.new(name, width, value)
        _constants << const
        define_method(name) { SignalRef.new(name, width: width, component: self) }
      end

      # Concurrent signal assignment
      def assign(target, value, when_condition: nil)
        _assignments << Assignment.new(target, value, condition: when_condition)
      end

      # Define a process block
      def process(name, sensitivity: [], clocked: false, &block)
        proc = ProcessBlock.new(name, sensitivity_list: sensitivity, clocked: clocked, &block)
        _processes << proc
      end

      # Combinational process (sensitivity to all inputs)
      def combinational(name = :comb_logic, &block)
        inputs = _ports.select { |p| p.direction == :in }.map(&:name)
        process(name, sensitivity: inputs, &block)
      end

      # Clocked process
      def clocked(name = :clk_logic, clock: :clk, reset: nil, &block)
        sensitivity = [clock]
        sensitivity << reset if reset
        process(name, sensitivity: sensitivity, clocked: true, &block)
      end

      # Instantiate a component
      def instance(name, component_type, ports: {}, generics: {})
        inst = ComponentInstance.new(name, component_type, port_map: ports, generic_map: generics)
        _instances << inst
      end

      # Generate Verilog output
      def to_verilog
        lines = []

        # Module declaration
        module_name = name.split('::').last.underscore
        lines << "module #{module_name}"

        # Parameters (generics)
        unless _generics.empty?
          lines << "  #("
          params_verilog = _generics.map do |g|
            default_str = g[:default] ? " = #{g[:default]}" : ""
            "    parameter #{g[:name]}#{default_str}"
          end
          lines << params_verilog.join(",\n")
          lines << "  )"
        end

        # Port declarations
        unless _ports.empty?
          lines << "  ("
          ports_verilog = _ports.map { |p| "    #{p.to_verilog}" }
          lines << ports_verilog.join(",\n")
          lines << "  );"
        else
          lines << "  ();"
        end

        lines << ""

        # Local parameters (constants)
        _constants.each { |c| lines << "  #{c.to_verilog}" }

        # Internal signals (regs)
        _signals.each { |s| lines << "  #{s.to_verilog}" }

        lines << "" unless _constants.empty? && _signals.empty?

        # Concurrent assignments
        _assignments.each { |a| lines << "  #{a.to_verilog}" }

        # Always blocks (processes)
        _processes.each { |p| lines << "  #{p.to_verilog}" }

        # Module instances
        _instances.each { |i| lines << "  #{i.to_verilog}" }

        lines << ""
        lines << "endmodule"

        lines.join("\n")
      end
    end

    # Instance methods for runtime simulation
    def initialize(**generics)
      @port_values = {}
      @signal_values = {}

      # Set generics
      generics.each do |name, value|
        instance_variable_set("@#{name}", value)
      end

      # Initialize ports and signals to 0
      self.class._ports.each { |p| @port_values[p.name] = 0 }
      self.class._signals.each { |s| @signal_values[s.name] = s.default || 0 }
    end

    def set_input(name, value)
      @port_values[name] = value
    end

    def get_output(name)
      @port_values[name]
    end

    def get_signal(name)
      @signal_values[name]
    end
  end
end

# Load expression classes first (in dependency order)
require_relative "dsl/expressions/bit_select"
require_relative "dsl/expressions/bit_slice"
require_relative "dsl/expressions/binary_op"
require_relative "dsl/expressions/unary_op"
require_relative "dsl/expressions/concatenation"
require_relative "dsl/expressions/replication"
require_relative "dsl/expressions/signal_ref"

# Load basic DSL classes
require_relative "dsl/port"
require_relative "dsl/signal"
require_relative "dsl/constant"

# Load sequential assignment (used by other classes)
require_relative "dsl/sequential_assignment"

# Load block collector (used by if_context and case_context)
require_relative "dsl/block_collector"

# Load statement classes
require_relative "dsl/if_statement"
require_relative "dsl/if_context"
require_relative "dsl/case_statement"
require_relative "dsl/case_context"
require_relative "dsl/for_loop"
require_relative "dsl/rising_edge"
require_relative "dsl/falling_edge"

# Load process classes
require_relative "dsl/process_context"
require_relative "dsl/process_block"

# Load concurrent assignment
require_relative "dsl/assignment"

# Load component instance
require_relative "dsl/component_instance"

# Load component DSL modules (used by sim/component.rb)
require_relative "dsl/ports"
require_relative "dsl/structure"
require_relative "dsl/vec"
require_relative "dsl/bundle"

# Load behavior module after DSL is defined
require_relative "dsl/behavior"
require_relative "dsl/sequential"
require_relative "dsl/memory"
require_relative "dsl/state_machine"

# Load codegen modules (depend on Export::IR, loaded later)
# These are loaded after codegen.rb in the main rhdl.rb
