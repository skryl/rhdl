# Memory DSL for synthesizable RAM/ROM components
#
# This module provides DSL constructs for memory arrays that can be synthesized
# to Verilog/VHDL with proper BRAM inference.
#
# Example - Simple RAM:
#   class RAM256x8 < RHDL::HDL::SimComponent
#     include RHDL::DSL::MemoryDSL
#
#     port_input :clk
#     port_input :we
#     port_input :addr, width: 8
#     port_input :din, width: 8
#     port_output :dout, width: 8
#
#     memory :mem, depth: 256, width: 8
#
#     sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
#     async_read :dout, from: :mem, addr: :addr
#   end
#
# Example - Lookup Table (ROM):
#   class InstructionDecoder < RHDL::HDL::SimComponent
#     include RHDL::DSL::MemoryDSL
#
#     port_input :opcode, width: 8
#     port_output :addr_mode, width: 4
#     port_output :alu_op, width: 4
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
        # Initialize memory arrays
        def initialize_memories
          @_memory_arrays = {}
          self.class._memories.each do |name, mem_def|
            @_memory_arrays[name] = mem_def.initial_values.dup
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

        # Override initialize to set up memories
        alias_method :original_initialize, :initialize rescue nil

        def initialize(name, *args, **kwargs, &block)
          if respond_to?(:original_initialize)
            original_initialize(name, *args, **kwargs, &block)
          else
            super
          end
          initialize_memories
        end

        # Default propagate for memory DSL components
        def propagate
          # Handle sync writes on rising edge
          clk_val = nil
          @_prev_clk ||= {}

          self.class._sync_writes.each do |write_def|
            clk_val = in_val(write_def.clock)
            prev = @_prev_clk[write_def.clock] || 0
            rising = (prev == 0 && clk_val == 1)
            @_prev_clk[write_def.clock] = clk_val

            if rising && in_val(write_def.enable) == 1
              addr = in_val(write_def.addr)
              data = in_val(write_def.data)
              mem_def = self.class._memories[write_def.memory]
              mem_write(write_def.memory, addr, data, mem_def.width)
            end
          end

          # Handle async reads
          self.class._async_reads.each do |read_def|
            if read_def.enable.nil? || in_val(read_def.enable) == 1
              addr = in_val(read_def.addr)
              value = mem_read(read_def.memory, addr)
              out_set(read_def.output, value)
            else
              out_set(read_def.output, 0)
            end
          end

          # Handle lookup tables
          self.class._lookup_tables.each do |_name, table|
            input_val = in_val(table.input_signal)

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
      end
    end
  end
end
