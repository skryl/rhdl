# Enhanced RHDL DSL
# Ruby-esque block-style syntax for hardware description

require 'active_support/concern'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/string/inflections'

module RHDL
  module DSL
    extend ActiveSupport::Concern

    # Signal value wrapper for DSL expressions
    class SignalRef
      attr_reader :name, :width, :component

      def initialize(name, width: 1, component: nil)
        @name = name
        @width = width
        @component = component
        @value = 0
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          BitSlice.new(self, index)
        else
          BitSelect.new(self, index)
        end
      end

      # Arithmetic operators
      def +(other)
        BinaryOp.new(:+, self, other)
      end

      def -(other)
        BinaryOp.new(:-, self, other)
      end

      def *(other)
        BinaryOp.new(:*, self, other)
      end

      def /(other)
        BinaryOp.new(:/, self, other)
      end

      def %(other)
        BinaryOp.new(:%, self, other)
      end

      # Bitwise operators
      def &(other)
        BinaryOp.new(:&, self, other)
      end

      def |(other)
        BinaryOp.new(:|, self, other)
      end

      def ^(other)
        BinaryOp.new(:^, self, other)
      end

      def ~
        UnaryOp.new(:~, self)
      end

      # Shift operators
      def <<(amount)
        BinaryOp.new(:<<, self, amount)
      end

      def >>(amount)
        BinaryOp.new(:>>, self, amount)
      end

      # Comparison operators
      def ==(other)
        BinaryOp.new(:==, self, other)
      end

      def !=(other)
        BinaryOp.new(:!=, self, other)
      end

      def <(other)
        BinaryOp.new(:<, self, other)
      end

      def >(other)
        BinaryOp.new(:>, self, other)
      end

      def <=(other)
        BinaryOp.new(:<=, self, other)
      end

      def >=(other)
        BinaryOp.new(:>=, self, other)
      end

      # Concatenation
      def concat(*others)
        Concatenation.new([self] + others)
      end

      # Replication
      def replicate(times)
        Replication.new(self, times)
      end

      def to_vhdl
        name.to_s
      end

      def to_verilog
        name.to_s
      end

      def to_s
        name.to_s
      end
    end

    # Bit selection expression
    class BitSelect
      attr_reader :signal, :index

      def initialize(signal, index)
        @signal = signal
        @index = index
      end

      def to_vhdl
        "#{signal.to_vhdl}(#{index})"
      end

      def to_verilog
        "#{signal.to_verilog}[#{index}]"
      end
    end

    # Bit slice expression
    class BitSlice
      attr_reader :signal, :range

      def initialize(signal, range)
        @signal = signal
        @range = range
      end

      def to_vhdl
        "#{signal.to_vhdl}(#{range.max} downto #{range.min})"
      end

      def to_verilog
        "#{signal.to_verilog}[#{range.max}:#{range.min}]"
      end
    end

    # Binary operation expression
    class BinaryOp
      attr_reader :op, :left, :right

      VHDL_OPS = {
        :+ => '+', :- => '-', :* => '*', :/ => '/',
        :& => 'and', :| => 'or', :^ => 'xor',
        :<< => 'sll', :>> => 'srl',
        :== => '=', :!= => '/=',
        :< => '<', :> => '>', :<= => '<=', :>= => '>='
      }

      VERILOG_OPS = {
        :+ => '+', :- => '-', :* => '*', :/ => '/',
        :& => '&', :| => '|', :^ => '^',
        :<< => '<<', :>> => '>>',
        :== => '==', :!= => '!=',
        :< => '<', :> => '>', :<= => '<=', :>= => '>='
      }

      def initialize(op, left, right)
        @op = op
        @left = left
        @right = right
      end

      def to_vhdl
        l = left.respond_to?(:to_vhdl) ? left.to_vhdl : left.to_s
        r = right.respond_to?(:to_vhdl) ? right.to_vhdl : right.to_s
        "(#{l} #{VHDL_OPS[op]} #{r})"
      end

      def to_verilog
        l = left.respond_to?(:to_verilog) ? left.to_verilog : left.to_s
        r = right.respond_to?(:to_verilog) ? right.to_verilog : right.to_s
        "(#{l} #{VERILOG_OPS[op]} #{r})"
      end

      # Allow chaining
      def &(other); BinaryOp.new(:&, self, other); end
      def |(other); BinaryOp.new(:|, self, other); end
      def ^(other); BinaryOp.new(:^, self, other); end
    end

    # Unary operation expression
    class UnaryOp
      attr_reader :op, :operand

      def initialize(op, operand)
        @op = op
        @operand = operand
      end

      def to_vhdl
        case op
        when :~ then "not #{operand.to_vhdl}"
        else "#{op}#{operand.to_vhdl}"
        end
      end

      def to_verilog
        case op
        when :~ then "~#{operand.to_verilog}"
        else "#{op}#{operand.to_verilog}"
        end
      end
    end

    # Concatenation expression
    class Concatenation
      attr_reader :signals

      def initialize(signals)
        @signals = signals
      end

      def to_vhdl
        parts = signals.map { |s| s.respond_to?(:to_vhdl) ? s.to_vhdl : s.to_s }
        "(#{parts.join(' & ')})"
      end

      def to_verilog
        parts = signals.map { |s| s.respond_to?(:to_verilog) ? s.to_verilog : s.to_s }
        "{#{parts.join(', ')}}"
      end
    end

    # Replication expression
    class Replication
      attr_reader :signal, :times

      def initialize(signal, times)
        @signal = signal
        @times = times
      end

      def to_vhdl
        parts = Array.new(times) { signal.to_vhdl }
        "(#{parts.join(' & ')})"
      end

      def to_verilog
        "{#{times}{#{signal.to_verilog}}}"
      end
    end

    # Port definition
    class Port
      attr_reader :name, :direction, :width, :default

      def initialize(name, direction, width, default: nil)
        @name = name
        @direction = direction
        @width = width
        @default = default
      end

      def to_vhdl
        type_str = width > 1 ? "std_logic_vector(#{width-1} downto 0)" : "std_logic"
        "#{name} : #{direction} #{type_str}"
      end

      def to_verilog
        dir = case direction
              when :in then "input"
              when :out then "output"
              when :inout then "inout"
              end
        width > 1 ? "#{dir} [#{width-1}:0] #{name}" : "#{dir} #{name}"
      end

      def to_signal_ref
        SignalRef.new(name, width: width)
      end
    end

    # Internal signal definition
    class Signal
      attr_reader :name, :width, :default

      def initialize(name, width, default: nil)
        @name = name
        @width = width
        @default = default
      end

      def to_vhdl
        type_str = width > 1 ? "std_logic_vector(#{width-1} downto 0)" : "std_logic"
        default_str = default ? " := #{format_value(default)}" : ""
        "signal #{name} : #{type_str}#{default_str};"
      end

      def to_verilog
        type_str = width > 1 ? "[#{width-1}:0]" : ""
        default_str = default ? " = #{format_verilog_value(default)}" : ""
        "reg #{type_str} #{name}#{default_str};".gsub(/\s+/, ' ').strip
      end

      def to_signal_ref
        SignalRef.new(name, width: width)
      end

      private

      def format_value(val)
        if width == 1
          val == 0 ? "'0'" : "'1'"
        else
          "\"#{val.to_s(2).rjust(width, '0')}\""
        end
      end

      def format_verilog_value(val)
        if width == 1
          val == 0 ? "1'b0" : "1'b1"
        else
          "#{width}'b#{val.to_s(2).rjust(width, '0')}"
        end
      end
    end

    # Constant definition
    class Constant
      attr_reader :name, :width, :value

      def initialize(name, width, value)
        @name = name
        @width = width
        @value = value
      end

      def to_vhdl
        type_str = width > 1 ? "std_logic_vector(#{width-1} downto 0)" : "std_logic"
        "constant #{name} : #{type_str} := #{format_value(value)};"
      end

      def to_verilog
        type_str = width > 1 ? "[#{width-1}:0]" : ""
        "localparam #{type_str} #{name} = #{format_verilog_value(value)};".gsub(/\s+/, ' ').strip
      end

      def to_signal_ref
        SignalRef.new(name, width: width)
      end

      private

      def format_value(val)
        if width == 1
          val == 0 ? "'0'" : "'1'"
        else
          "\"#{val.to_s(2).rjust(width, '0')}\""
        end
      end

      def format_verilog_value(val)
        if width == 1
          val == 0 ? "1'b0" : "1'b1"
        else
          "#{width}'b#{val.to_s(2).rjust(width, '0')}"
        end
      end
    end

    # Signal assignment
    class Assignment
      attr_reader :target, :value, :condition

      def initialize(target, value, condition: nil)
        @target = target
        @value = value
        @condition = condition
      end

      def to_vhdl
        t = target.respond_to?(:to_vhdl) ? target.to_vhdl : target.to_s
        v = value.respond_to?(:to_vhdl) ? value.to_vhdl : format_literal(value)

        if condition
          c = condition.respond_to?(:to_vhdl) ? condition.to_vhdl : condition.to_s
          "#{t} <= #{v} when #{c} else #{t};"
        else
          "#{t} <= #{v};"
        end
      end

      def to_verilog
        t = target.respond_to?(:to_verilog) ? target.to_verilog : target.to_s
        v = value.respond_to?(:to_verilog) ? value.to_verilog : format_verilog_literal(value)

        if condition
          c = condition.respond_to?(:to_verilog) ? condition.to_verilog : condition.to_s
          "assign #{t} = #{c} ? #{v} : #{t};"
        else
          "assign #{t} = #{v};"
        end
      end

      private

      def format_literal(val)
        if val.is_a?(Integer)
          if target.respond_to?(:width) && target.width > 1
            "\"#{val.to_s(2).rjust(target.width, '0')}\""
          else
            val == 0 ? "'0'" : "'1'"
          end
        else
          val.to_s
        end
      end

      def format_verilog_literal(val)
        if val.is_a?(Integer)
          if target.respond_to?(:width) && target.width > 1
            "#{target.width}'b#{val.to_s(2).rjust(target.width, '0')}"
          else
            val == 0 ? "1'b0" : "1'b1"
          end
        else
          val.to_s
        end
      end
    end

    # Process block (sequential or combinational)
    class ProcessBlock
      attr_reader :name, :sensitivity_list, :statements, :is_clocked

      def initialize(name, sensitivity_list: [], clocked: false, &block)
        @name = name
        @sensitivity_list = sensitivity_list
        @statements = []
        @is_clocked = clocked
        @context = ProcessContext.new(self)
        @context.instance_eval(&block) if block_given?
      end

      def to_vhdl
        sens = sensitivity_list.map { |s| s.respond_to?(:to_vhdl) ? s.to_vhdl : s.to_s }
        lines = []
        lines << "#{name}: process(#{sens.join(', ')})"
        lines << "begin"
        statements.each { |s| lines << "  #{s.to_vhdl}" }
        lines << "end process #{name};"
        lines.join("\n")
      end

      def to_verilog
        sens = sensitivity_list.map { |s| s.respond_to?(:to_verilog) ? s.to_verilog : s.to_s }
        lines = []
        if is_clocked
          # For clocked processes, use posedge/negedge
          edge_list = sens.map { |s| "posedge #{s}" }
          lines << "always @(#{edge_list.join(' or ')}) begin"
        else
          lines << "always @(#{sens.join(' or ')}) begin"
        end
        statements.each { |s| lines << "  #{s.to_verilog}" }
        lines << "end"
        lines.join("\n")
      end

      def add_statement(stmt)
        @statements << stmt
      end
    end

    # Context for process blocks
    class ProcessContext
      def initialize(process)
        @process = process
      end

      # Sequential assignment
      def assign(target, value)
        @process.add_statement(SequentialAssignment.new(target, value))
      end

      # If statement
      def if_stmt(condition, &block)
        stmt = IfStatement.new(condition)
        ctx = IfContext.new(stmt)
        ctx.instance_eval(&block)
        @process.add_statement(stmt)
        stmt
      end

      # Case statement
      def case_stmt(selector, &block)
        stmt = CaseStatement.new(selector)
        ctx = CaseContext.new(stmt)
        ctx.instance_eval(&block)
        @process.add_statement(stmt)
        stmt
      end

      # For loop
      def for_loop(var, range, &block)
        stmt = ForLoop.new(var, range)
        ctx = ProcessContext.new(stmt)
        ctx.instance_eval(&block)
        @process.add_statement(stmt)
        stmt
      end

      # Rising edge check
      def rising_edge(signal)
        RisingEdge.new(signal)
      end

      # Falling edge check
      def falling_edge(signal)
        FallingEdge.new(signal)
      end
    end

    # Sequential assignment (inside process)
    class SequentialAssignment
      attr_reader :target, :value

      def initialize(target, value)
        @target = target
        @value = value
      end

      def to_vhdl
        t = target.respond_to?(:to_vhdl) ? target.to_vhdl : target.to_s
        v = value.respond_to?(:to_vhdl) ? value.to_vhdl : value.to_s
        "#{t} <= #{v};"
      end

      def to_verilog
        t = target.respond_to?(:to_verilog) ? target.to_verilog : target.to_s
        v = value.respond_to?(:to_verilog) ? value.to_verilog : value.to_s
        "#{t} <= #{v};"
      end
    end

    # If statement
    class IfStatement
      attr_reader :condition, :then_block, :elsif_blocks, :else_block

      def initialize(condition)
        @condition = condition
        @then_block = []
        @elsif_blocks = []
        @else_block = []
      end

      def add_then(stmt)
        @then_block << stmt
      end

      def add_elsif(condition, statements)
        @elsif_blocks << [condition, statements]
      end

      def add_else(stmt)
        @else_block << stmt
      end

      def to_vhdl
        lines = []
        cond = condition.respond_to?(:to_vhdl) ? condition.to_vhdl : condition.to_s
        lines << "if #{cond} then"
        then_block.each { |s| lines << "  #{s.to_vhdl}" }

        elsif_blocks.each do |cond, stmts|
          c = cond.respond_to?(:to_vhdl) ? cond.to_vhdl : cond.to_s
          lines << "elsif #{c} then"
          stmts.each { |s| lines << "  #{s.to_vhdl}" }
        end

        unless else_block.empty?
          lines << "else"
          else_block.each { |s| lines << "  #{s.to_vhdl}" }
        end

        lines << "end if;"
        lines.join("\n")
      end

      def to_verilog
        lines = []
        cond = condition.respond_to?(:to_verilog) ? condition.to_verilog : condition.to_s
        lines << "if (#{cond}) begin"
        then_block.each { |s| lines << "  #{s.to_verilog}" }
        lines << "end"

        elsif_blocks.each do |cond, stmts|
          c = cond.respond_to?(:to_verilog) ? cond.to_verilog : cond.to_s
          lines << "else if (#{c}) begin"
          stmts.each { |s| lines << "  #{s.to_verilog}" }
          lines << "end"
        end

        unless else_block.empty?
          lines << "else begin"
          else_block.each { |s| lines << "  #{s.to_verilog}" }
          lines << "end"
        end

        lines.join("\n")
      end
    end

    # If statement context
    class IfContext
      def initialize(if_stmt)
        @if_stmt = if_stmt
        @current_block = :then
      end

      def assign(target, value)
        stmt = SequentialAssignment.new(target, value)
        case @current_block
        when :then then @if_stmt.add_then(stmt)
        when :else then @if_stmt.add_else(stmt)
        end
      end

      def elsif_block(condition, &block)
        stmts = []
        ctx = BlockCollector.new(stmts)
        ctx.instance_eval(&block)
        @if_stmt.add_elsif(condition, stmts)
      end

      def else_block(&block)
        @current_block = :else
        instance_eval(&block)
        @current_block = :then
      end
    end

    # Helper for collecting statements
    class BlockCollector
      def initialize(statements)
        @statements = statements
      end

      def assign(target, value)
        @statements << SequentialAssignment.new(target, value)
      end
    end

    # Case statement
    class CaseStatement
      attr_reader :selector, :when_blocks, :default_block

      def initialize(selector)
        @selector = selector
        @when_blocks = []
        @default_block = []
      end

      def add_when(value, statements)
        @when_blocks << [value, statements]
      end

      def add_default(statements)
        @default_block = statements
      end

      def to_vhdl
        lines = []
        sel = selector.respond_to?(:to_vhdl) ? selector.to_vhdl : selector.to_s
        lines << "case #{sel} is"

        when_blocks.each do |val, stmts|
          v = val.respond_to?(:to_vhdl) ? val.to_vhdl : format_case_value(val)
          lines << "  when #{v} =>"
          stmts.each { |s| lines << "    #{s.to_vhdl}" }
        end

        unless default_block.empty?
          lines << "  when others =>"
          default_block.each { |s| lines << "    #{s.to_vhdl}" }
        end

        lines << "end case;"
        lines.join("\n")
      end

      def to_verilog
        lines = []
        sel = selector.respond_to?(:to_verilog) ? selector.to_verilog : selector.to_s
        lines << "case (#{sel})"

        when_blocks.each do |val, stmts|
          v = val.respond_to?(:to_verilog) ? val.to_verilog : format_verilog_case_value(val)
          lines << "  #{v}: begin"
          stmts.each { |s| lines << "    #{s.to_verilog}" }
          lines << "  end"
        end

        unless default_block.empty?
          lines << "  default: begin"
          default_block.each { |s| lines << "    #{s.to_verilog}" }
          lines << "  end"
        end

        lines << "endcase"
        lines.join("\n")
      end

      private

      def format_case_value(val)
        val.is_a?(Integer) ? "\"#{val.to_s(2)}\"" : val.to_s
      end

      def format_verilog_case_value(val)
        val.is_a?(Integer) ? val.to_s : val.to_s
      end
    end

    # Case statement context
    class CaseContext
      def initialize(case_stmt)
        @case_stmt = case_stmt
      end

      def when_value(value, &block)
        stmts = []
        ctx = BlockCollector.new(stmts)
        ctx.instance_eval(&block)
        @case_stmt.add_when(value, stmts)
      end

      def default(&block)
        stmts = []
        ctx = BlockCollector.new(stmts)
        ctx.instance_eval(&block)
        @case_stmt.add_default(stmts)
      end
    end

    # For loop
    class ForLoop
      attr_reader :variable, :range, :statements

      def initialize(variable, range)
        @variable = variable
        @range = range
        @statements = []
      end

      def add_statement(stmt)
        @statements << stmt
      end

      def to_vhdl
        lines = []
        lines << "for #{variable} in #{range.min} to #{range.max} loop"
        statements.each { |s| lines << "  #{s.to_vhdl}" }
        lines << "end loop;"
        lines.join("\n")
      end

      def to_verilog
        lines = []
        lines << "for (#{variable} = #{range.min}; #{variable} <= #{range.max}; #{variable} = #{variable} + 1) begin"
        statements.each { |s| lines << "  #{s.to_verilog}" }
        lines << "end"
        lines.join("\n")
      end
    end

    # Rising edge condition
    class RisingEdge
      attr_reader :signal

      def initialize(signal)
        @signal = signal
      end

      def to_vhdl
        "rising_edge(#{signal.respond_to?(:to_vhdl) ? signal.to_vhdl : signal})"
      end

      def to_verilog
        "posedge #{signal.respond_to?(:to_verilog) ? signal.to_verilog : signal}"
      end
    end

    # Falling edge condition
    class FallingEdge
      attr_reader :signal

      def initialize(signal)
        @signal = signal
      end

      def to_vhdl
        "falling_edge(#{signal.respond_to?(:to_vhdl) ? signal.to_vhdl : signal})"
      end

      def to_verilog
        "negedge #{signal.respond_to?(:to_verilog) ? signal.to_verilog : signal}"
      end
    end

    # Component instance
    class ComponentInstance
      attr_reader :name, :component_type, :port_map, :generic_map

      def initialize(name, component_type, port_map: {}, generic_map: {})
        @name = name
        @component_type = component_type
        @port_map = port_map
        @generic_map = generic_map
      end

      def to_vhdl
        lines = []
        lines << "#{name}: #{component_type}"

        unless generic_map.empty?
          generics = generic_map.map { |k, v| "#{k} => #{v}" }
          lines << "  generic map(#{generics.join(', ')})"
        end

        ports = port_map.map do |k, v|
          val = v.respond_to?(:to_vhdl) ? v.to_vhdl : v.to_s
          "#{k} => #{val}"
        end
        lines << "  port map(#{ports.join(', ')});"

        lines.join("\n")
      end

      def to_verilog
        lines = []

        # In Verilog: module_name #(.param(value)) instance_name (.port(signal), ...);
        if generic_map.empty?
          lines << "#{component_type} #{name} ("
        else
          params = generic_map.map { |k, v| ".#{k}(#{v})" }
          lines << "#{component_type} #(#{params.join(', ')}) #{name} ("
        end

        ports = port_map.map do |k, v|
          val = v.respond_to?(:to_verilog) ? v.to_verilog : v.to_s
          ".#{k}(#{val})"
        end
        lines << "  #{ports.join(', ')}"
        lines << ");"

        lines.join("\n")
      end
    end

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

      # Generate VHDL output
      def to_vhdl
        lines = []

        # Library declarations
        lines << "library IEEE;"
        lines << "use IEEE.STD_LOGIC_1164.ALL;"
        lines << "use IEEE.NUMERIC_STD.ALL;"
        lines << ""

        # Entity declaration
        entity_name = name.split('::').last.underscore
        lines << "entity #{entity_name} is"

        unless _generics.empty?
          lines << "  generic("
          generics_vhdl = _generics.map do |g|
            default_str = g[:default] ? " := #{g[:default]}" : ""
            "    #{g[:name]} : #{g[:type]}#{default_str}"
          end
          lines << generics_vhdl.join(";\n")
          lines << "  );"
        end

        unless _ports.empty?
          lines << "  port("
          ports_vhdl = _ports.map { |p| "    #{p.to_vhdl}" }
          lines << ports_vhdl.join(";\n")
          lines << "  );"
        end

        lines << "end #{entity_name};"
        lines << ""

        # Architecture
        lines << "architecture rtl of #{entity_name} is"

        _constants.each { |c| lines << "  #{c.to_vhdl}" }
        _signals.each { |s| lines << "  #{s.to_vhdl}" }

        lines << "begin"

        _assignments.each { |a| lines << "  #{a.to_vhdl}" }
        _processes.each { |p| lines << "  #{p.to_vhdl}" }
        _instances.each { |i| lines << "  #{i.to_vhdl}" }

        lines << "end rtl;"

        lines.join("\n")
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
