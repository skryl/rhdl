# frozen_string_literal: true

module RHDL
  module CLI
    # Shared configuration for CLI tasks
    # Contains paths, component definitions, and constants used by multiple tasks
    module Config
      # Base directories (relative to project root)
      def self.project_root
        @project_root ||= File.expand_path('../../..', __dir__)
      end

      def self.diagrams_dir
        @diagrams_dir ||= File.join(project_root, 'diagrams')
      end

      def self.verilog_dir
        @verilog_dir ||= File.join(project_root, 'export/verilog')
      end

      def self.gates_dir
        @gates_dir ||= File.join(project_root, 'export/gates')
      end

      def self.rom_output_dir
        @rom_output_dir ||= File.join(project_root, 'export/roms')
      end

      def self.roms_dir
        @roms_dir ||= File.join(project_root, 'examples/mos6502/software/roms')
      end

      def self.examples_dir
        @examples_dir ||= File.join(project_root, 'examples')
      end

      def self.apple2_dir
        @apple2_dir ||= File.join(project_root, 'examples/mos6502')
      end

      # Diagram configuration
      DIAGRAM_MODES = %w[component hierarchical gate].freeze
      CATEGORIES = %w[gates sequential arithmetic combinational memory cpu].freeze

      # Component definitions with their instantiation parameters
      # Lazy-loaded lambdas for deferred instantiation
      def self.hdl_components
        @hdl_components ||= {
          # Gates
          'gates/not_gate' => -> { RHDL::HDL::NotGate.new('not_gate') },
          'gates/buffer' => -> { RHDL::HDL::Buffer.new('buffer') },
          'gates/and_gate' => -> { RHDL::HDL::AndGate.new('and_gate') },
          'gates/and_gate_3input' => -> { RHDL::HDL::AndGate.new('and_gate_3in', inputs: 3) },
          'gates/or_gate' => -> { RHDL::HDL::OrGate.new('or_gate') },
          'gates/nand_gate' => -> { RHDL::HDL::NandGate.new('nand_gate') },
          'gates/nor_gate' => -> { RHDL::HDL::NorGate.new('nor_gate') },
          'gates/xor_gate' => -> { RHDL::HDL::XorGate.new('xor_gate') },
          'gates/xnor_gate' => -> { RHDL::HDL::XnorGate.new('xnor_gate') },
          'gates/tristate_buffer' => -> { RHDL::HDL::TristateBuffer.new('tristate') },
          'gates/bitwise_and' => -> { RHDL::HDL::BitwiseAnd.new('bitwise_and', width: 8) },
          'gates/bitwise_or' => -> { RHDL::HDL::BitwiseOr.new('bitwise_or', width: 8) },
          'gates/bitwise_xor' => -> { RHDL::HDL::BitwiseXor.new('bitwise_xor', width: 8) },
          'gates/bitwise_not' => -> { RHDL::HDL::BitwiseNot.new('bitwise_not', width: 8) },

          # Sequential
          'sequential/d_flipflop' => -> { RHDL::HDL::DFlipFlop.new('dff') },
          'sequential/d_flipflop_async' => -> { RHDL::HDL::DFlipFlopAsync.new('dff_async') },
          'sequential/t_flipflop' => -> { RHDL::HDL::TFlipFlop.new('tff') },
          'sequential/jk_flipflop' => -> { RHDL::HDL::JKFlipFlop.new('jkff') },
          'sequential/sr_flipflop' => -> { RHDL::HDL::SRFlipFlop.new('srff') },
          'sequential/sr_latch' => -> { RHDL::HDL::SRLatch.new('sr_latch') },
          'sequential/register_8bit' => -> { RHDL::HDL::Register.new('reg8', width: 8) },
          'sequential/register_16bit' => -> { RHDL::HDL::Register.new('reg16', width: 16) },
          'sequential/register_load' => -> { RHDL::HDL::RegisterLoad.new('reg_load', width: 8) },
          'sequential/shift_register' => -> { RHDL::HDL::ShiftRegister.new('shift_reg', width: 8) },
          'sequential/counter' => -> { RHDL::HDL::Counter.new('counter', width: 8) },
          'sequential/program_counter' => -> { RHDL::HDL::ProgramCounter.new('pc', width: 16) },
          'sequential/stack_pointer' => -> { RHDL::HDL::StackPointer.new('sp', width: 8) },

          # Arithmetic
          'arithmetic/half_adder' => -> { RHDL::HDL::HalfAdder.new('half_adder') },
          'arithmetic/full_adder' => -> { RHDL::HDL::FullAdder.new('full_adder') },
          'arithmetic/ripple_carry_adder' => -> { RHDL::HDL::RippleCarryAdder.new('rca', width: 8) },
          'arithmetic/subtractor' => -> { RHDL::HDL::Subtractor.new('sub', width: 8) },
          'arithmetic/addsub' => -> { RHDL::HDL::AddSub.new('addsub', width: 8) },
          'arithmetic/comparator' => -> { RHDL::HDL::Comparator.new('cmp', width: 8) },
          'arithmetic/multiplier' => -> { RHDL::HDL::Multiplier.new('mul', width: 8) },
          'arithmetic/divider' => -> { RHDL::HDL::Divider.new('div', width: 8) },
          'arithmetic/incdec' => -> { RHDL::HDL::IncDec.new('incdec', width: 8) },
          'arithmetic/alu_8bit' => -> { RHDL::HDL::ALU.new('alu8', width: 8) },
          'arithmetic/alu_16bit' => -> { RHDL::HDL::ALU.new('alu16', width: 16) },

          # Combinational
          'combinational/mux2' => -> { RHDL::HDL::Mux2.new('mux2', width: 8) },
          'combinational/mux4' => -> { RHDL::HDL::Mux4.new('mux4', width: 8) },
          'combinational/mux8' => -> { RHDL::HDL::Mux8.new('mux8', width: 8) },
          'combinational/muxn' => -> { RHDL::HDL::MuxN.new('muxn', width: 8, inputs: 4) },
          'combinational/demux2' => -> { RHDL::HDL::Demux2.new('demux2', width: 8) },
          'combinational/demux4' => -> { RHDL::HDL::Demux4.new('demux4', width: 8) },
          'combinational/decoder_2to4' => -> { RHDL::HDL::Decoder2to4.new('dec2to4') },
          'combinational/decoder_3to8' => -> { RHDL::HDL::Decoder3to8.new('dec3to8') },
          'combinational/decoder_n' => -> { RHDL::HDL::DecoderN.new('decn', width: 4) },
          'combinational/encoder_4to2' => -> { RHDL::HDL::Encoder4to2.new('enc4to2') },
          'combinational/encoder_8to3' => -> { RHDL::HDL::Encoder8to3.new('enc8to3') },
          'combinational/zero_detect' => -> { RHDL::HDL::ZeroDetect.new('zero_det', width: 8) },
          'combinational/sign_extend' => -> { RHDL::HDL::SignExtend.new('sext', in_width: 8, out_width: 16) },
          'combinational/zero_extend' => -> { RHDL::HDL::ZeroExtend.new('zext', in_width: 8, out_width: 16) },
          'combinational/barrel_shifter' => -> { RHDL::HDL::BarrelShifter.new('barrel', width: 8) },
          'combinational/bit_reverse' => -> { RHDL::HDL::BitReverse.new('bitrev', width: 8) },
          'combinational/popcount' => -> { RHDL::HDL::PopCount.new('popcount', width: 8) },
          'combinational/lzcount' => -> { RHDL::HDL::LZCount.new('lzcount', width: 8) },

          # Memory
          'memory/ram' => -> { RHDL::HDL::RAM.new('ram', data_width: 8, addr_width: 8) },
          'memory/ram_64k' => -> { RHDL::HDL::RAM.new('ram64k', data_width: 8, addr_width: 16) },
          'memory/dual_port_ram' => -> { RHDL::HDL::DualPortRAM.new('dpram', data_width: 8, addr_width: 8) },
          'memory/rom' => -> { RHDL::HDL::ROM.new('rom', data_width: 8, addr_width: 8) },
          'memory/register_file' => -> { RHDL::HDL::RegisterFile.new('regfile', num_regs: 8, data_width: 8) },
          'memory/stack' => -> { RHDL::HDL::Stack.new('stack', data_width: 8, depth: 16) },
          'memory/fifo' => -> { RHDL::HDL::FIFO.new('fifo', data_width: 8, depth: 16) },

          # CPU
          'cpu/instruction_decoder' => -> { RHDL::HDL::CPU::InstructionDecoder.new('decoder') },
          'cpu/accumulator' => -> { RHDL::HDL::CPU::Accumulator.new('acc') },
          'cpu/cpu' => -> { RHDL::HDL::CPU::CPU.new('cpu') }
        }.freeze
      end

      # Components that support gate-level lowering for diagrams
      GATE_LEVEL_COMPONENTS = %w[
        gates/not_gate gates/buffer gates/and_gate gates/and_gate_3input
        gates/or_gate gates/xor_gate
        gates/bitwise_and gates/bitwise_or gates/bitwise_xor
        sequential/d_flipflop sequential/d_flipflop_async
        arithmetic/half_adder arithmetic/full_adder arithmetic/ripple_carry_adder
        combinational/mux2
      ].freeze

      # All components that support gate-level synthesis
      def self.gate_synth_components
        @gate_synth_components ||= {
          # Gates
          'gates/not_gate' => -> { RHDL::HDL::NotGate.new('not_gate') },
          'gates/buffer' => -> { RHDL::HDL::Buffer.new('buffer') },
          'gates/and_gate' => -> { RHDL::HDL::AndGate.new('and_gate') },
          'gates/or_gate' => -> { RHDL::HDL::OrGate.new('or_gate') },
          'gates/xor_gate' => -> { RHDL::HDL::XorGate.new('xor_gate') },
          'gates/nand_gate' => -> { RHDL::HDL::NandGate.new('nand_gate') },
          'gates/nor_gate' => -> { RHDL::HDL::NorGate.new('nor_gate') },
          'gates/xnor_gate' => -> { RHDL::HDL::XnorGate.new('xnor_gate') },
          'gates/tristate_buffer' => -> { RHDL::HDL::TristateBuffer.new('tristate') },
          'gates/bitwise_and' => -> { RHDL::HDL::BitwiseAnd.new('bitwise_and', width: 8) },
          'gates/bitwise_or' => -> { RHDL::HDL::BitwiseOr.new('bitwise_or', width: 8) },
          'gates/bitwise_xor' => -> { RHDL::HDL::BitwiseXor.new('bitwise_xor', width: 8) },
          'gates/bitwise_not' => -> { RHDL::HDL::BitwiseNot.new('bitwise_not', width: 8) },

          # Sequential
          'sequential/d_flipflop' => -> { RHDL::HDL::DFlipFlop.new('dff') },
          'sequential/d_flipflop_async' => -> { RHDL::HDL::DFlipFlopAsync.new('dff_async') },
          'sequential/t_flipflop' => -> { RHDL::HDL::TFlipFlop.new('tff') },
          'sequential/jk_flipflop' => -> { RHDL::HDL::JKFlipFlop.new('jkff') },
          'sequential/sr_flipflop' => -> { RHDL::HDL::SRFlipFlop.new('srff') },
          'sequential/sr_latch' => -> { RHDL::HDL::SRLatch.new('sr_latch') },
          'sequential/register' => -> { RHDL::HDL::Register.new('reg', width: 8) },
          'sequential/register_load' => -> { RHDL::HDL::RegisterLoad.new('reg_load', width: 8) },
          'sequential/shift_register' => -> { RHDL::HDL::ShiftRegister.new('shift_reg', width: 8) },
          'sequential/counter' => -> { RHDL::HDL::Counter.new('counter', width: 8) },
          'sequential/program_counter' => -> { RHDL::HDL::ProgramCounter.new('pc', width: 16) },
          'sequential/stack_pointer' => -> { RHDL::HDL::StackPointer.new('sp', width: 8) },

          # Arithmetic
          'arithmetic/half_adder' => -> { RHDL::HDL::HalfAdder.new('half_adder') },
          'arithmetic/full_adder' => -> { RHDL::HDL::FullAdder.new('full_adder') },
          'arithmetic/ripple_carry_adder' => -> { RHDL::HDL::RippleCarryAdder.new('rca', width: 8) },
          'arithmetic/subtractor' => -> { RHDL::HDL::Subtractor.new('sub', width: 8) },
          'arithmetic/addsub' => -> { RHDL::HDL::AddSub.new('addsub', width: 8) },
          'arithmetic/comparator' => -> { RHDL::HDL::Comparator.new('cmp', width: 8) },
          'arithmetic/incdec' => -> { RHDL::HDL::IncDec.new('incdec', width: 8) },
          'arithmetic/multiplier' => -> { RHDL::HDL::Multiplier.new('mul', width: 4) },
          'arithmetic/divider' => -> { RHDL::HDL::Divider.new('div', width: 4) },
          'arithmetic/alu' => -> { RHDL::HDL::ALU.new('alu', width: 8) },

          # Combinational
          'combinational/mux2' => -> { RHDL::HDL::Mux2.new('mux2', width: 8) },
          'combinational/mux4' => -> { RHDL::HDL::Mux4.new('mux4', width: 4) },
          'combinational/mux8' => -> { RHDL::HDL::Mux8.new('mux8', width: 4) },
          'combinational/demux2' => -> { RHDL::HDL::Demux2.new('demux2', width: 4) },
          'combinational/demux4' => -> { RHDL::HDL::Demux4.new('demux4', width: 4) },
          'combinational/decoder_2to4' => -> { RHDL::HDL::Decoder2to4.new('dec2to4') },
          'combinational/decoder_3to8' => -> { RHDL::HDL::Decoder3to8.new('dec3to8') },
          'combinational/encoder_4to2' => -> { RHDL::HDL::Encoder4to2.new('enc4to2') },
          'combinational/encoder_8to3' => -> { RHDL::HDL::Encoder8to3.new('enc8to3') },
          'combinational/zero_detect' => -> { RHDL::HDL::ZeroDetect.new('zero_det', width: 8) },
          'combinational/sign_extend' => -> { RHDL::HDL::SignExtend.new('sext', in_width: 8, out_width: 16) },
          'combinational/zero_extend' => -> { RHDL::HDL::ZeroExtend.new('zext', in_width: 8, out_width: 16) },
          'combinational/bit_reverse' => -> { RHDL::HDL::BitReverse.new('bitrev', width: 8) },
          'combinational/popcount' => -> { RHDL::HDL::PopCount.new('popcount', width: 8) },
          'combinational/lzcount' => -> { RHDL::HDL::LZCount.new('lzcount', width: 8) },
          'combinational/barrel_shifter' => -> { RHDL::HDL::BarrelShifter.new('barrel', width: 8) },

          # CPU
          'cpu/instruction_decoder' => -> { RHDL::HDL::CPU::InstructionDecoder.new('decoder') },
          'cpu/cpu' => -> { RHDL::HDL::CPU::CPU.new('cpu') }
        }.freeze
      end

      # Example components with to_verilog methods
      EXAMPLE_COMPONENTS = {
        'mos6502/mos6502_registers' => ['examples/mos6502/hdl/registers/registers', 'MOS6502::Registers'],
        'mos6502/mos6502_stack_pointer' => ['examples/mos6502/hdl/registers/stack_pointer', 'MOS6502::StackPointer'],
        'mos6502/mos6502_program_counter' => ['examples/mos6502/hdl/registers/program_counter', 'MOS6502::ProgramCounter'],
        'mos6502/mos6502_instruction_register' => ['examples/mos6502/hdl/registers/instruction_register', 'MOS6502::InstructionRegister'],
        'mos6502/mos6502_address_latch' => ['examples/mos6502/hdl/registers/address_latch', 'MOS6502::AddressLatch'],
        'mos6502/mos6502_data_latch' => ['examples/mos6502/hdl/registers/data_latch', 'MOS6502::DataLatch'],
        'mos6502/mos6502_status_register' => ['examples/mos6502/hdl/registers/status_register', 'MOS6502::StatusRegister'],
        'mos6502/mos6502_address_generator' => ['examples/mos6502/hdl/address_gen/address_generator', 'MOS6502::AddressGenerator'],
        'mos6502/mos6502_indirect_addr_calc' => ['examples/mos6502/hdl/address_gen/indirect_address_calc', 'MOS6502::IndirectAddressCalc'],
        'mos6502/mos6502_alu' => ['examples/mos6502/hdl/alu', 'MOS6502::ALU'],
        'mos6502/mos6502_instruction_decoder' => ['examples/mos6502/hdl/instruction_decoder', 'MOS6502::InstructionDecoder'],
        'mos6502/mos6502_control_unit' => ['examples/mos6502/hdl/control_unit', 'MOS6502::ControlUnit'],
        'mos6502/mos6502_memory' => ['examples/mos6502/hdl/memory', 'MOS6502::Memory']
      }.freeze

      # Instantiate a component by name
      def self.create_component(name)
        creator = hdl_components[name] || gate_synth_components[name]
        raise ArgumentError, "Unknown component: #{name}" unless creator

        creator.call
      end
    end
  end
end
