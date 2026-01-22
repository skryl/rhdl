# Memory DSL for synthesizable RAM/ROM components
#
# This module provides DSL constructs for memory arrays that can be synthesized
# to Verilog with proper BRAM inference.
#
# Example - Simple RAM with async read (distributed RAM):
#   class RAM256x8 < RHDL::Sim::Component
#     include RHDL::DSL::Memory
#
#     input :clk
#     input :we
#     input :addr, width: 8
#     input :din, width: 8
#     output :dout, width: 8
#
#     memory :mem, depth: 256, width: 8
#
#     sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
#     async_read :dout, from: :mem, addr: :addr
#   end
#
# Example - BRAM with sync read (for FPGA BRAM inference):
#   class BRAM256x8 < RHDL::Sim::Component
#     include RHDL::DSL::Memory
#
#     input :clk
#     input :we
#     input :addr, width: 8
#     input :din, width: 8
#     output :dout, width: 8
#
#     memory :mem, depth: 256, width: 8
#
#     sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
#     sync_read :dout, from: :mem, clock: :clk, addr: :addr
#   end
#
# Example - Expression-based enable (no intermediate wire needed):
#   class RAM < RHDL::Sim::Component
#     include RHDL::DSL::Memory
#
#     input :clk
#     input :cs, :we
#     input :addr, width: 8
#     input :din, width: 8
#     output :dout, width: 8
#
#     memory :mem, depth: 256, width: 8
#
#     # Enable can be an expression instead of a single signal
#     sync_write :mem, clock: :clk, enable: [:cs, :&, :we], addr: :addr, data: :din
#     async_read :dout, from: :mem, addr: :addr, enable: :cs
#   end
#
# Example - Multi-port memory (True Dual Port RAM):
#   class DualPortRAM < RHDL::Sim::Component
#     include RHDL::DSL::Memory
#
#     # Port A
#     input :clk_a, :cs_a, :we_a
#     input :addr_a, width: 8
#     input :din_a, width: 8
#     output :dout_a, width: 8
#
#     # Port B
#     input :clk_b, :cs_b
#     input :addr_b, width: 8
#     output :dout_b, width: 8
#
#     # Define memory with multiple ports using block syntax
#     memory :mem, depth: 256, width: 8 do |m|
#       m.write_port clock: :clk_a, enable: [:cs_a, :&, :we_a], addr: :addr_a, data: :din_a
#       m.sync_read_port clock: :clk_a, enable: :cs_a, addr: :addr_a, output: :dout_a
#       m.async_read_port enable: :cs_b, addr: :addr_b, output: :dout_b
#     end
#   end
#
# Example - Computed address in behavior blocks:
#   class Stack < RHDL::Sim::Component
#     include RHDL::DSL::Memory
#     include RHDL::DSL::Behavior
#
#     # ... ports and memory definition ...
#
#     behavior do
#       # Read with computed address (sp - 1)
#       dout <= mem_read_expr(:data, sp - lit(1, width: 5), width: 8)
#     end
#   end
#
# Example - Lookup Table (ROM):
#   class InstructionDecoder < RHDL::Sim::Component
#     include RHDL::DSL::Memory
#
#     input :opcode, width: 8
#     output :addr_mode, width: 4
#     output :alu_op, width: 4
#
#     lookup_table :decode do |t|
#       t.input :opcode, width: 8
#       t.output :addr_mode, width: 4
#       t.output :alu_op, width: 4
#
#       t.entry 0x00, addr_mode: 0, alu_op: 0   # BRK
#       t.entry 0x69, addr_mode: 1, alu_op: 0   # ADC imm
#       # ... or bulk define
#       t.add_entries({
#         0x00 => { addr_mode: 0, alu_op: 0 },
#         0x01 => { addr_mode: 1, alu_op: 1 },
#       })
#       t.default addr_mode: 0xF, alu_op: 0xF
#     end
#   end

require 'active_support/concern'

module RHDL
  module DSL
    module Memory
      extend ActiveSupport::Concern

      # Memory definition for RAM/ROM
      class MemoryDef
        attr_reader :name, :depth, :width, :initial_values
        attr_reader :write_ports, :sync_read_ports, :async_read_ports

        def initialize(name, depth:, width:, initial_values: nil)
          @name = name
          @depth = depth
          @width = width
          @initial_values = initial_values || Array.new(depth, 0)
          @write_ports = []
          @sync_read_ports = []
          @async_read_ports = []
        end

        def addr_width
          Math.log2(depth).ceil
        end
      end

      # Builder for multi-port memory declarations
      class MemoryPortBuilder
        attr_reader :memory_def

        def initialize(memory_def)
          @memory_def = memory_def
        end

        # Add a write port to the memory
        # @param clock [Symbol] Clock signal
        # @param enable [Symbol, Array] Enable signal or expression (e.g., [:cs, :&, :we])
        # @param addr [Symbol] Address signal
        # @param data [Symbol] Data input signal
        def write_port(clock:, enable:, addr:, data:)
          @memory_def.write_ports << {
            clock: clock,
            enable: enable,
            addr: addr,
            data: data
          }
        end

        # Add a synchronous read port (registered output for BRAM)
        # @param clock [Symbol] Clock signal
        # @param addr [Symbol] Address signal
        # @param output [Symbol] Output signal
        # @param enable [Symbol, Array, nil] Optional enable signal or expression
        def sync_read_port(clock:, addr:, output:, enable: nil)
          @memory_def.sync_read_ports << {
            clock: clock,
            addr: addr,
            output: output,
            enable: enable
          }
        end

        # Add an asynchronous read port (combinational)
        # @param addr [Symbol] Address signal
        # @param output [Symbol] Output signal
        # @param enable [Symbol, Array, nil] Optional enable signal or expression
        def async_read_port(addr:, output:, enable: nil)
          @memory_def.async_read_ports << {
            addr: addr,
            output: output,
            enable: enable
          }
        end
      end

      # Enable expression - can be a symbol or an expression array
      # Expression format: [:signal1, :op, :signal2] where op is :& or :|
      # Nested expressions: [:signal1, :&, [:signal2, :|, :signal3]]
      class EnableExpr
        attr_reader :expr

        def initialize(expr)
          @expr = expr
        end

        # Check if this is a simple symbol or an expression
        def simple?
          @expr.is_a?(Symbol)
        end

        # Evaluate the expression given a signal value lookup proc
        def evaluate(signal_lookup)
          if simple?
            signal_lookup.call(@expr)
          else
            eval_expr(@expr, signal_lookup)
          end
        end

        # Convert to IR expression for code generation
        # @param widths [Hash] Signal name => width mapping (optional)
        def to_ir(widths = {})
          expr_to_ir(@expr, widths)
        end

        private

        def eval_expr(e, signal_lookup)
          return signal_lookup.call(e) if e.is_a?(Symbol)
          return e if e.is_a?(Integer)

          if e.is_a?(Array) && e.length == 3
            left = eval_expr(e[0], signal_lookup)
            op = e[1]
            right = eval_expr(e[2], signal_lookup)

            case op
            when :& then left & right
            when :| then left | right
            when :^ then left ^ right
            else left & right
            end
          else
            0
          end
        end

        def expr_to_ir(e, widths)
          case e
          when Symbol
            width = widths.fetch(e, 1)
            RHDL::Codegen::Verilog::IR::Signal.new(name: e, width: width)
          when Integer
            RHDL::Codegen::Verilog::IR::Literal.new(value: e, width: 1)
          when Array
            if e.length == 3
              left = expr_to_ir(e[0], widths)
              op = e[1]
              right = expr_to_ir(e[2], widths)
              RHDL::Codegen::Verilog::IR::BinaryOp.new(op: op, left: left, right: right, width: 1)
            else
              RHDL::Codegen::Verilog::IR::Literal.new(value: 0, width: 1)
            end
          else
            RHDL::Codegen::Verilog::IR::Literal.new(value: 1, width: 1)
          end
        end
      end

      # Synchronous write port definition
      class SyncWriteDef
        attr_reader :memory, :clock, :addr, :data

        def initialize(memory, clock:, enable:, addr:, data:)
          @memory = memory
          @clock = clock
          @enable_expr = EnableExpr.new(enable)
          @addr = addr
          @data = data
        end

        # Get enable (for backwards compatibility - returns symbol if simple, array if expression)
        def enable
          @enable_expr.expr
        end

        # Check if enable is an expression or simple symbol
        def enable_is_expression?
          !@enable_expr.simple?
        end

        # Evaluate enable given a signal lookup proc
        def evaluate_enable(signal_lookup)
          @enable_expr.evaluate(signal_lookup)
        end

        # Convert enable to IR for code generation
        def enable_to_ir(widths = {})
          @enable_expr.to_ir(widths)
        end
      end

      # Asynchronous read definition
      class AsyncReadDef
        attr_reader :output, :memory, :addr

        def initialize(output, from:, addr:, enable: nil)
          @output = output
          @memory = from
          @addr = addr
          @enable_expr = enable ? EnableExpr.new(enable) : nil
        end

        def enable
          @enable_expr&.expr
        end

        def enable_is_expression?
          @enable_expr && !@enable_expr.simple?
        end

        def evaluate_enable(signal_lookup)
          return 1 if @enable_expr.nil?
          @enable_expr.evaluate(signal_lookup)
        end

        # Convert enable to IR for code generation
        def enable_to_ir(widths = {})
          @enable_expr&.to_ir(widths)
        end
      end

      # Synchronous read definition (registered output for BRAM inference)
      class SyncReadDef
        attr_reader :output, :memory, :clock, :addr

        def initialize(output, from:, clock:, addr:, enable: nil)
          @output = output
          @memory = from
          @clock = clock
          @addr = addr
          @enable_expr = enable ? EnableExpr.new(enable) : nil
        end

        def enable
          @enable_expr&.expr
        end

        def enable_is_expression?
          @enable_expr && !@enable_expr.simple?
        end

        def evaluate_enable(signal_lookup)
          return 1 if @enable_expr.nil?
          @enable_expr.evaluate(signal_lookup)
        end

        # Convert enable to IR for code generation
        def enable_to_ir(widths = {})
          @enable_expr&.to_ir(widths)
        end
      end

      # Lookup table builder
      class LookupTableBuilder
        attr_reader :name, :input_signal, :input_width, :outputs, :default_values
        attr_reader :entries

        def initialize(name)
          @name = name
          @input_signal = nil
          @input_width = 8
          @outputs = {}        # { name => width }
          @entries = {}        # { input_value => { output_name => value } }
          @default_values = {} # { output_name => value }
        end

        def input(name, width: 8)
          @input_signal = name
          @input_width = width
        end

        def output(name, width: 1)
          @outputs[name] = width
        end

        def entry(input_val, **output_vals)
          @entries[input_val] = output_vals
        end

        def add_entries(hash)
          @entries.merge!(hash)
        end

        def default(**output_vals)
          @default_values = output_vals
        end

        # Generate IR for synthesis
        def to_ir
          @outputs.map do |output_name, output_width|
            cases = @entries.transform_keys { |k| [k] }
                           .transform_values { |vals|
                             RHDL::Export::IR::Literal.new(
                               value: vals[output_name] || @default_values[output_name] || 0,
                               width: output_width
                             )
                           }

            default_ir = RHDL::Export::IR::Literal.new(
              value: @default_values[output_name] || 0,
              width: output_width
            )

            case_ir = RHDL::Export::IR::Case.new(
              selector: RHDL::Export::IR::Signal.new(name: @input_signal, width: @input_width),
              cases: cases,
              default: default_ir,
              width: output_width
            )

            RHDL::Export::IR::Assign.new(
              target: output_name,
              expr: case_ir
            )
          end
        end
      end

      class_methods do
        # Define a memory array
        #
        # @param name [Symbol] Memory name
        # @param depth [Integer] Number of entries
        # @param width [Integer] Bits per entry
        # @param initial [Array, nil] Initial values
        # @yield [MemoryPortBuilder] Optional block for multi-port configuration
        #
        # @example Simple memory
        #   memory :ram, depth: 256, width: 8
        #
        # @example Multi-port memory with block
        #   memory :mem, depth: 256, width: 8 do |m|
        #     m.write_port clock: :clk_a, enable: :we_a, addr: :addr_a, data: :din_a
        #     m.sync_read_port clock: :clk_a, addr: :addr_a, output: :dout_a
        #     m.async_read_port addr: :addr_b, output: :dout_b
        #   end
        #
        def memory(name, depth:, width:, initial: nil, readonly: false, &block)
          @_memories ||= {}
          mem_def = MemoryDef.new(name, depth: depth, width: width, initial_values: initial)
          @_memories[name] = mem_def

          # If a block is provided, use it to configure ports
          if block_given?
            builder = MemoryPortBuilder.new(mem_def)
            block.call(builder)

            # Register ports from builder
            mem_def.write_ports.each do |wp|
              sync_write(name, clock: wp[:clock], enable: wp[:enable], addr: wp[:addr], data: wp[:data])
            end

            mem_def.sync_read_ports.each do |rp|
              sync_read(rp[:output], from: name, clock: rp[:clock], addr: rp[:addr], enable: rp[:enable])
            end

            mem_def.async_read_ports.each do |rp|
              async_read(rp[:output], from: name, addr: rp[:addr], enable: rp[:enable])
            end
          end
        end

        def _memories
          @_memories || {}
        end

        # Define a synchronous write port
        #
        # @param memory [Symbol] Memory to write to
        # @param clock [Symbol] Clock signal
        # @param enable [Symbol] Write enable signal
        # @param addr [Symbol] Address signal
        # @param data [Symbol] Data input signal
        #
        # @example
        #   sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
        #
        def sync_write(memory, clock:, enable:, addr:, data:)
          @_sync_writes ||= []
          @_sync_writes << SyncWriteDef.new(memory, clock: clock, enable: enable, addr: addr, data: data)
        end

        def _sync_writes
          @_sync_writes || []
        end

        # Define an asynchronous read
        #
        # @param output [Symbol] Output signal name
        # @param from [Symbol] Memory to read from
        # @param addr [Symbol] Address signal
        # @param enable [Symbol, nil] Optional enable signal
        #
        # @example
        #   async_read :dout, from: :mem, addr: :addr
        #
        def async_read(output, from:, addr:, enable: nil)
          @_async_reads ||= []
          @_async_reads << AsyncReadDef.new(output, from: from, addr: addr, enable: enable)
        end

        def _async_reads
          @_async_reads || []
        end

        # Define a synchronous read (registered output for BRAM inference)
        #
        # @param output [Symbol] Output signal name
        # @param from [Symbol] Memory to read from
        # @param clock [Symbol] Clock signal
        # @param addr [Symbol] Address signal
        # @param enable [Symbol, nil] Optional enable signal
        #
        # @example
        #   sync_read :dout, from: :mem, clock: :clk, addr: :addr
        #
        # This generates proper BRAM read inferencing in synthesis:
        #   always @(posedge clk) begin
        #     dout <= mem[addr];
        #   end
        #
        def sync_read(output, from:, clock:, addr:, enable: nil)
          @_sync_reads ||= []
          @_sync_reads << SyncReadDef.new(output, from: from, clock: clock, addr: addr, enable: enable)
        end

        def _sync_reads
          @_sync_reads || []
        end

        # Define a lookup table (combinational ROM)
        #
        # @param name [Symbol] Lookup table name
        # @yield [LookupTableBuilder] Block to configure the table
        #
        # @example
        #   lookup_table :decode do |t|
        #     t.input :opcode, width: 8
        #     t.output :addr_mode, width: 4
        #     t.entry 0x00, addr_mode: 0
        #     t.default addr_mode: 0xF
        #   end
        #
        def lookup_table(name, &block)
          @_lookup_tables ||= {}
          builder = LookupTableBuilder.new(name)
          block.call(builder)
          @_lookup_tables[name] = builder

          # Define propagate method for simulation
          define_memory_propagate if respond_to?(:define_memory_propagate)
        end

        def _lookup_tables
          @_lookup_tables || {}
        end

        # Check if memory DSL features are defined
        def memory_dsl_defined?
          !_memories.empty? || !_lookup_tables.empty?
        end
      end

      # Instance methods for simulation
      included do
        # Initialize memory arrays and load contents if provided
        def initialize_memories
          @_memory_arrays = {}
          self.class._memories.each do |name, mem_def|
            @_memory_arrays[name] = mem_def.initial_values.dup
          end

          # Load contents if @contents parameter is set (from parameter DSL)
          load_initial_contents if instance_variable_defined?(:@contents) && !@contents.empty?
        end

        # Load initial contents into the first memory (convention for ROM/RAM)
        def load_initial_contents
          return unless @_memory_arrays && !@_memory_arrays.empty?

          # Find the first memory and its width
          mem_name, _mem_array = @_memory_arrays.first
          mem_def = self.class._memories[mem_name]
          width = mem_def&.width || 8
          depth = mem_def&.depth || 256

          @contents.each_with_index do |v, i|
            break if i >= depth
            mem_write(mem_name, i, v, width)
          end
        end

        # Memory read for simulation
        def mem_read(memory, addr)
          @_memory_arrays[memory][addr] || 0
        end

        # Memory write for simulation
        def mem_write(memory, addr, data, width)
          mask = (1 << width) - 1
          @_memory_arrays[memory][addr] = data & mask
        end

        # Get signal value from inputs, outputs, internal signals, or sequential state
        # This allows Memory to work with register-based addresses
        def signal_val(name)
          # Try input first
          if @inputs && @inputs[name]
            return @inputs[name].get
          end
          # Try sequential state (for registers managed by Sequential DSL)
          if @_seq_state && @_seq_state.key?(name)
            return @_seq_state[name]
          end
          # Try internal signals
          if @internal_signals && @internal_signals[name]
            return @internal_signals[name].get
          end
          # Try output
          if @outputs && @outputs[name]
            return @outputs[name].get
          end
          0
        end

        # Override initialize to set up memories
        def initialize(name = nil, **kwargs)
          super
          initialize_memories
        end

        # Process sync writes - called before sequential state updates
        # This uses current register values before they are updated
        def process_memory_sync_writes(rising_clocks)
          signal_lookup = ->(name) { signal_val(name) }

          self.class._sync_writes.each do |write_def|
            enable_val = write_def.evaluate_enable(signal_lookup)
            if rising_clocks[write_def.clock] && (enable_val & 1) == 1
              addr = signal_val(write_def.addr)
              data = signal_val(write_def.data)
              mem_def = self.class._memories[write_def.memory]
              mem_write(write_def.memory, addr, data, mem_def.width)
            end
          end
        end

        # Process async reads - uses current values (combinational)
        def process_memory_async_reads
          signal_lookup = ->(name) { signal_val(name) }

          self.class._async_reads.each do |read_def|
            enable_val = read_def.evaluate_enable(signal_lookup)
            if (enable_val & 1) == 1
              addr = signal_val(read_def.addr)
              value = mem_read(read_def.memory, addr)
              out_set(read_def.output, value)
            else
              out_set(read_def.output, 0)
            end
          end
        end

        # Process sync reads - registered output on clock edge (for BRAM inference)
        def process_memory_sync_reads(rising_clocks)
          signal_lookup = ->(name) { signal_val(name) }

          self.class._sync_reads.each do |read_def|
            next unless rising_clocks[read_def.clock]

            enable_val = read_def.evaluate_enable(signal_lookup)
            if (enable_val & 1) == 1
              addr = signal_val(read_def.addr)
              value = mem_read(read_def.memory, addr)
              out_set(read_def.output, value)
            end
            # Note: When enable is low, output retains previous value (registered)
          end
        end

        # Process lookup tables
        def process_memory_lookup_tables
          self.class._lookup_tables.each do |_name, table|
            input_val = signal_val(table.input_signal)

            table.outputs.each do |output_name, _width|
              value = if table.entries.key?(input_val)
                       table.entries[input_val][output_name] || table.default_values[output_name] || 0
                     else
                       table.default_values[output_name] || 0
                     end
              out_set(output_name, value)
            end
          end
        end

        # Default propagate for memory DSL components (only used if Sequential DSL is NOT included)
        def propagate
          # If Sequential DSL is included, it handles the propagate and calls our methods
          return if self.class.respond_to?(:sequential_defined?) && self.class.sequential_defined?

          # Handle sync writes and reads on rising edge
          # First, detect rising edges for all clocks ONCE
          @_prev_clk ||= {}
          rising_clocks = {}

          # Collect all clocks from sync writes and reads
          all_sync_ops = self.class._sync_writes + self.class._sync_reads
          all_sync_ops.each do |op_def|
            clock = op_def.clock
            next if rising_clocks.key?(clock)  # Already checked this clock

            clk_val = in_val(clock)
            prev = @_prev_clk[clock] || 0
            rising_clocks[clock] = (prev == 0 && clk_val == 1)
            @_prev_clk[clock] = clk_val
          end

          # Process sync writes
          process_memory_sync_writes(rising_clocks)

          # Process sync reads (registered output)
          process_memory_sync_reads(rising_clocks)

          # Handle async reads
          process_memory_async_reads

          # Handle lookup tables
          process_memory_lookup_tables
        end
      end
    end
  end
end
