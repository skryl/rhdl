# Memory DSL for synthesizable RAM/ROM components
#
# This module provides DSL constructs for memory arrays that can be synthesized
# to Verilog with proper BRAM inference.
#
# Example - Simple RAM:
#   class RAM256x8 < RHDL::Sim::Component
#     include RHDL::DSL::MemoryDSL
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
# Example - Lookup Table (ROM):
#   class InstructionDecoder < RHDL::Sim::Component
#     include RHDL::DSL::MemoryDSL
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
    module MemoryDSL
      extend ActiveSupport::Concern

      # Memory definition for RAM/ROM
      class MemoryDef
        attr_reader :name, :depth, :width, :initial_values

        def initialize(name, depth:, width:, initial_values: nil)
          @name = name
          @depth = depth
          @width = width
          @initial_values = initial_values || Array.new(depth, 0)
        end

        def addr_width
          Math.log2(depth).ceil
        end
      end

      # Synchronous write port definition
      class SyncWriteDef
        attr_reader :memory, :clock, :enable, :addr, :data

        def initialize(memory, clock:, enable:, addr:, data:)
          @memory = memory
          @clock = clock
          @enable = enable
          @addr = addr
          @data = data
        end
      end

      # Asynchronous read definition
      class AsyncReadDef
        attr_reader :output, :memory, :addr, :enable

        def initialize(output, from:, addr:, enable: nil)
          @output = output
          @memory = from
          @addr = addr
          @enable = enable
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
        #
        # @example
        #   memory :ram, depth: 256, width: 8
        #
        def memory(name, depth:, width:, initial: nil)
          @_memories ||= {}
          @_memories[name] = MemoryDef.new(name, depth: depth, width: width, initial_values: initial)
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

        # Get signal value from inputs, outputs, or sequential state
        # This allows MemoryDSL to work with register-based addresses
        def signal_val(name)
          # Try input first
          if @inputs && @inputs[name]
            return @inputs[name].get
          end
          # Try sequential state (for registers managed by Sequential DSL)
          if @_seq_state && @_seq_state.key?(name)
            return @_seq_state[name]
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
          self.class._sync_writes.each do |write_def|
            if rising_clocks[write_def.clock] && signal_val(write_def.enable) == 1
              addr = signal_val(write_def.addr)
              data = signal_val(write_def.data)
              mem_def = self.class._memories[write_def.memory]
              mem_write(write_def.memory, addr, data, mem_def.width)
            end
          end
        end

        # Process async reads - uses current values
        def process_memory_async_reads
          self.class._async_reads.each do |read_def|
            if read_def.enable.nil? || signal_val(read_def.enable) == 1
              addr = signal_val(read_def.addr)
              value = mem_read(read_def.memory, addr)
              out_set(read_def.output, value)
            else
              out_set(read_def.output, 0)
            end
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

          # Handle sync writes on rising edge
          # First, detect rising edges for all clocks ONCE
          @_prev_clk ||= {}
          rising_clocks = {}

          self.class._sync_writes.each do |write_def|
            clock = write_def.clock
            next if rising_clocks.key?(clock)  # Already checked this clock

            clk_val = in_val(clock)
            prev = @_prev_clk[clock] || 0
            rising_clocks[clock] = (prev == 0 && clk_val == 1)
            @_prev_clk[clock] = clk_val
          end

          # Process sync writes
          process_memory_sync_writes(rising_clocks)

          # Handle async reads
          process_memory_async_reads

          # Handle lookup tables
          process_memory_lookup_tables
        end
      end
    end
  end
end
