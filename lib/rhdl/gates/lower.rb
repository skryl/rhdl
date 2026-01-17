# Lower HDL simulation components into gate-level IR

require 'fileutils'

require_relative 'ir'
require_relative 'primitives'
require_relative 'toposort'

module RHDL
  module Gates
    class Lower
      def self.from_components(components, name: 'design')
        new(components, name: name).lower
      end

      def initialize(components, name:)
        @components = components
        @name = name
        @ir = IR.new(name: name)
        @net_map = {}
      end

      def lower
        build_net_map
        lower_components
        @ir.set_schedule(Toposort.schedule(@ir.gates))
        dump_netlist if ENV.fetch('RHDL_DUMP_NETLIST', '0') == '1'
        @ir
      end

      private

      def dump_netlist
        FileUtils.mkdir_p('tmp/netlists')
        File.write("tmp/netlists/#{@name}.json", @ir.to_json)
      end

      def wires
        @components.flat_map do |component|
          component.inputs.values + component.outputs.values + component.internal_signals.values
        end
      end

      def build_net_map
        wire_bits = {}
        index = 0

        wires.each do |wire|
          wire.width.times do |bit|
            wire_bits[[wire, bit]] = index
            index += 1
          end
        end

        parent = Array.new(index) { |i| i }

        find = lambda do |i|
          while parent[i] != i
            parent[i] = parent[parent[i]]
            i = parent[i]
          end
          i
        end

        union = lambda do |a, b|
          ra = find.call(a)
          rb = find.call(b)
          parent[rb] = ra unless ra == rb
        end

        wires.each do |wire|
          next unless wire.driver

          wire.width.times do |bit|
            source = wire_bits[[wire.driver, bit]]
            dest = wire_bits[[wire, bit]]
            next unless source && dest

            union.call(dest, source)
          end
        end

        root_to_net = {}
        wire_bits.each do |(wire, bit), node|
          root = find.call(node)
          root_to_net[root] ||= @ir.new_net
          @net_map[[wire, bit]] = root_to_net[root]
        end

        @components.each do |component|
          component.inputs.each do |name, wire|
            @ir.add_input("#{component.name}.#{name}", map_bus(wire))
          end
          component.outputs.each do |name, wire|
            @ir.add_output("#{component.name}.#{name}", map_bus(wire))
          end
        end
      end

      def map_bus(wire)
        (0...wire.width).map { |bit| @net_map[[wire, bit]] }
      end

      def new_temp
        @ir.new_net
      end

      def lower_components
        @components.each do |component|
          dispatch_lower(component)
        end
      end

      def dispatch_lower(component)
          case component
          when RHDL::HDL::NotGate
            lower_not(component)
          when RHDL::HDL::Buffer
            lower_buffer(component)
          when RHDL::HDL::AndGate
            lower_nary(component, Primitives::AND, :y)
          when RHDL::HDL::OrGate
            lower_nary(component, Primitives::OR, :y)
          when RHDL::HDL::XorGate
            lower_nary(component, Primitives::XOR, :y)
          when RHDL::HDL::NandGate
            lower_nand(component)
          when RHDL::HDL::NorGate
            lower_nor(component)
          when RHDL::HDL::XnorGate
            lower_xnor(component)
          when RHDL::HDL::BitwiseAnd
            lower_bitwise(component, Primitives::AND)
          when RHDL::HDL::BitwiseOr
            lower_bitwise(component, Primitives::OR)
          when RHDL::HDL::BitwiseXor
            lower_bitwise(component, Primitives::XOR)
          when RHDL::HDL::BitwiseNot
            lower_bitwise_not(component)
          when RHDL::HDL::Mux2
            lower_mux2(component)
          when RHDL::HDL::Mux4
            lower_mux4(component)
          when RHDL::HDL::Mux8
            lower_mux8(component)
          when RHDL::HDL::Demux2
            lower_demux2(component)
          when RHDL::HDL::Demux4
            lower_demux4(component)
          when RHDL::HDL::Decoder2to4
            lower_decoder2to4(component)
          when RHDL::HDL::Decoder3to8
            lower_decoder3to8(component)
          when RHDL::HDL::Encoder4to2
            lower_encoder4to2(component)
          when RHDL::HDL::Encoder8to3
            lower_encoder8to3(component)
          when RHDL::HDL::ZeroDetect
            lower_zero_detect(component)
          when RHDL::HDL::SignExtend
            lower_sign_extend(component)
          when RHDL::HDL::ZeroExtend
            lower_zero_extend(component)
          when RHDL::HDL::BitReverse
            lower_bit_reverse(component)
          when RHDL::HDL::PopCount
            lower_pop_count(component)
          when RHDL::HDL::LZCount
            lower_lz_count(component)
          when RHDL::HDL::BarrelShifter
            lower_barrel_shifter(component)
          when RHDL::HDL::HalfAdder
            lower_half_adder(component)
          when RHDL::HDL::FullAdder
            lower_full_adder(component)
          when RHDL::HDL::RippleCarryAdder
            lower_ripple_adder(component)
          when RHDL::HDL::Subtractor
            lower_subtractor(component)
          when RHDL::HDL::AddSub
            lower_add_sub(component)
          when RHDL::HDL::Comparator
            lower_comparator(component)
          when RHDL::HDL::IncDec
            lower_inc_dec(component)
          when RHDL::HDL::DFlipFlop
            lower_dff(component, async_reset: false)
          when RHDL::HDL::DFlipFlopAsync
            lower_dff(component, async_reset: true)
          when RHDL::HDL::Register
            lower_register(component)
          when RHDL::HDL::ShiftRegister
            lower_shift_register(component)
          when RHDL::HDL::Counter
            lower_counter(component)
          when RHDL::HDL::JKFlipFlop
            lower_jk_flip_flop(component)
          when RHDL::HDL::TFlipFlop
            lower_t_flip_flop(component)
          when RHDL::HDL::SRFlipFlop
            lower_sr_flip_flop(component)
          when RHDL::HDL::SRLatch
            lower_sr_latch(component)
          when RHDL::HDL::TristateBuffer
            lower_tristate_buffer(component)
          when RHDL::HDL::MuxN
            lower_mux_n(component)
          when RHDL::HDL::DecoderN
            lower_decoder_n(component)
          when RHDL::HDL::Multiplier
            lower_multiplier(component)
          when RHDL::HDL::Divider
            lower_divider(component)
          when RHDL::HDL::ALU
            lower_alu(component)
          when RHDL::HDL::RAM
            lower_ram(component)
          when RHDL::HDL::ROM
            lower_rom(component)
          when RHDL::HDL::DualPortRAM
            lower_dual_port_ram(component)
          when RHDL::HDL::RegisterFile
            lower_register_file(component)
          when RHDL::HDL::FIFO
            lower_fifo(component)
          when RHDL::HDL::Stack
            lower_stack(component)
          when RHDL::HDL::RegisterLoad
            lower_register_load(component)
          when RHDL::HDL::ProgramCounter
            lower_program_counter(component)
          when RHDL::HDL::StackPointer
            lower_stack_pointer(component)
          when RHDL::HDL::CPU::InstructionDecoder
            lower_instruction_decoder(component)
          when RHDL::HDL::CPU::Datapath
            lower_datapath(component)
          when RHDL::HDL::CPU::SynthDatapath
            lower_synth_datapath(component)
          # MOS6502S components
          when MOS6502S::Registers
            lower_mos6502s_registers(component)
          when MOS6502S::StackPointer
            lower_mos6502s_stack_pointer(component)
          when MOS6502S::ProgramCounter
            lower_mos6502s_program_counter(component)
          when MOS6502S::InstructionRegister
            lower_mos6502s_instruction_register(component)
          when MOS6502S::AddressLatch
            lower_mos6502s_address_latch(component)
          when MOS6502S::DataLatch
            lower_mos6502s_data_latch(component)
          when MOS6502S::StatusRegister
            lower_mos6502s_status_register(component)
          when MOS6502S::AddressGenerator
            lower_mos6502s_address_generator(component)
          when MOS6502S::IndirectAddressCalc
            lower_mos6502s_indirect_addr_calc(component)
          when MOS6502S::ALU
            lower_mos6502s_alu(component)
          when MOS6502S::InstructionDecoder
            lower_mos6502s_instruction_decoder(component)
          when MOS6502S::ControlUnit
            lower_mos6502s_control_unit(component)
          when MOS6502S::Datapath
            lower_mos6502s_datapath(component)
          else
            raise ArgumentError, "Unsupported component for gate-level lowering: #{component.class}"
          end
      end

      def lower_not(component)
        in_net = map_bus(component.inputs[:a]).first
        out_net = map_bus(component.outputs[:y]).first
        @ir.add_gate(type: Primitives::NOT, inputs: [in_net], output: out_net)
      end

      def lower_buffer(component)
        in_net = map_bus(component.inputs[:a]).first
        out_net = map_bus(component.outputs[:y]).first
        @ir.add_gate(type: Primitives::BUF, inputs: [in_net], output: out_net)
      end

      def lower_nary(component, type, output_name)
        inputs = component.inputs.values.sort_by(&:name)
        in_nets = inputs.map { |wire| map_bus(wire).first }
        out_net = map_bus(component.outputs[output_name]).first
        reduce_gate(type, in_nets, out_net)
      end

      def lower_bitwise(component, type)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        y_nets = map_bus(component.outputs[:y])
        a_nets.each_with_index do |a_net, idx|
          b_net = b_nets[idx]
          y_net = y_nets[idx]
          @ir.add_gate(type: type, inputs: [a_net, b_net], output: y_net)
        end
      end

      def lower_bitwise_not(component)
        a_nets = map_bus(component.inputs[:a])
        y_nets = map_bus(component.outputs[:y])
        a_nets.each_with_index do |a_net, idx|
          y_net = y_nets[idx]
          @ir.add_gate(type: Primitives::NOT, inputs: [a_net], output: y_net)
        end
      end

      def lower_nand(component)
        inputs = component.inputs.values.sort_by(&:name)
        in_nets = inputs.map { |wire| map_bus(wire).first }
        out_net = map_bus(component.outputs[:y]).first
        # NAND = NOT(AND)
        and_temp = new_temp
        reduce_gate(Primitives::AND, in_nets, and_temp)
        @ir.add_gate(type: Primitives::NOT, inputs: [and_temp], output: out_net)
      end

      def lower_nor(component)
        inputs = component.inputs.values.sort_by(&:name)
        in_nets = inputs.map { |wire| map_bus(wire).first }
        out_net = map_bus(component.outputs[:y]).first
        # NOR = NOT(OR)
        or_temp = new_temp
        reduce_gate(Primitives::OR, in_nets, or_temp)
        @ir.add_gate(type: Primitives::NOT, inputs: [or_temp], output: out_net)
      end

      def lower_xnor(component)
        inputs = component.inputs.values.sort_by(&:name)
        in_nets = inputs.map { |wire| map_bus(wire).first }
        out_net = map_bus(component.outputs[:y]).first
        # XNOR = NOT(XOR)
        xor_temp = new_temp
        reduce_gate(Primitives::XOR, in_nets, xor_temp)
        @ir.add_gate(type: Primitives::NOT, inputs: [xor_temp], output: out_net)
      end

      def reduce_gate(type, inputs, out_net)
        case inputs.length
        when 0
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: out_net, value: 0)
        when 1
          @ir.add_gate(type: Primitives::BUF, inputs: [inputs.first], output: out_net)
        else
          current = inputs[0]
          inputs[1..].each_with_index do |input_net, idx|
            target = (idx == inputs.length - 2) ? out_net : new_temp
            @ir.add_gate(type: type, inputs: [current, input_net], output: target)
            current = target
          end
        end
      end

      def lower_mux2(component)
        sel_net = map_bus(component.inputs[:sel]).first
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        y_nets = map_bus(component.outputs[:y])
        a_nets.each_with_index do |a_net, idx|
          b_net = b_nets[idx]
          y_net = y_nets[idx]
          @ir.add_gate(type: Primitives::MUX, inputs: [a_net, b_net, sel_net], output: y_net)
        end
      end

      # Mux4: 4-to-1 multiplexer using nested 2-to-1 muxes
      def lower_mux4(component)
        sel_nets = map_bus(component.inputs[:sel])
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        c_nets = map_bus(component.inputs[:c])
        d_nets = map_bus(component.inputs[:d])
        y_nets = map_bus(component.outputs[:y])

        width = a_nets.length
        width.times do |idx|
          a_net = a_nets[idx]
          b_net = b_nets[idx]
          c_net = c_nets[idx]
          d_net = d_nets[idx]
          y_net = y_nets[idx]

          # Two-level mux tree: sel[0] selects within pairs, sel[1] selects pair
          low_mux = new_temp
          high_mux = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [a_net, b_net, sel_nets[0]], output: low_mux)
          @ir.add_gate(type: Primitives::MUX, inputs: [c_net, d_net, sel_nets[0]], output: high_mux)
          @ir.add_gate(type: Primitives::MUX, inputs: [low_mux, high_mux, sel_nets[1]], output: y_net)
        end
      end

      # Mux8: 8-to-1 multiplexer using nested 2-to-1 muxes
      def lower_mux8(component)
        sel_nets = map_bus(component.inputs[:sel])
        in_nets = (0..7).map { |i| map_bus(component.inputs[:"in#{i}"]) }
        y_nets = map_bus(component.outputs[:y])

        width = y_nets.length
        width.times do |idx|
          inputs = in_nets.map { |n| n[idx] }

          # Three-level mux tree
          # Level 1: pairs
          mux_01 = new_temp
          mux_23 = new_temp
          mux_45 = new_temp
          mux_67 = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [inputs[0], inputs[1], sel_nets[0]], output: mux_01)
          @ir.add_gate(type: Primitives::MUX, inputs: [inputs[2], inputs[3], sel_nets[0]], output: mux_23)
          @ir.add_gate(type: Primitives::MUX, inputs: [inputs[4], inputs[5], sel_nets[0]], output: mux_45)
          @ir.add_gate(type: Primitives::MUX, inputs: [inputs[6], inputs[7], sel_nets[0]], output: mux_67)

          # Level 2: quads
          mux_0123 = new_temp
          mux_4567 = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [mux_01, mux_23, sel_nets[1]], output: mux_0123)
          @ir.add_gate(type: Primitives::MUX, inputs: [mux_45, mux_67, sel_nets[1]], output: mux_4567)

          # Level 3: final
          @ir.add_gate(type: Primitives::MUX, inputs: [mux_0123, mux_4567, sel_nets[2]], output: y_nets[idx])
        end
      end

      # Demux2: 1-to-2 demultiplexer
      def lower_demux2(component)
        sel_net = map_bus(component.inputs[:sel]).first
        a_nets = map_bus(component.inputs[:a])
        y0_nets = map_bus(component.outputs[:y0])
        y1_nets = map_bus(component.outputs[:y1])

        # NOT sel
        sel_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [sel_net], output: sel_inv)

        a_nets.each_with_index do |a_net, idx|
          # y0 = a AND NOT sel
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, sel_inv], output: y0_nets[idx])
          # y1 = a AND sel
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, sel_net], output: y1_nets[idx])
        end
      end

      # Demux4: 1-to-4 demultiplexer
      def lower_demux4(component)
        sel_nets = map_bus(component.inputs[:sel])
        a_nets = map_bus(component.inputs[:a])
        y0_nets = map_bus(component.outputs[:y0])
        y1_nets = map_bus(component.outputs[:y1])
        y2_nets = map_bus(component.outputs[:y2])
        y3_nets = map_bus(component.outputs[:y3])

        # Decode selector
        sel0_inv = new_temp
        sel1_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [sel_nets[0]], output: sel0_inv)
        @ir.add_gate(type: Primitives::NOT, inputs: [sel_nets[1]], output: sel1_inv)

        # sel_0 = ~sel[1] & ~sel[0]
        # sel_1 = ~sel[1] & sel[0]
        # sel_2 = sel[1] & ~sel[0]
        # sel_3 = sel[1] & sel[0]
        dec_0 = new_temp
        dec_1 = new_temp
        dec_2 = new_temp
        dec_3 = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [sel1_inv, sel0_inv], output: dec_0)
        @ir.add_gate(type: Primitives::AND, inputs: [sel1_inv, sel_nets[0]], output: dec_1)
        @ir.add_gate(type: Primitives::AND, inputs: [sel_nets[1], sel0_inv], output: dec_2)
        @ir.add_gate(type: Primitives::AND, inputs: [sel_nets[1], sel_nets[0]], output: dec_3)

        a_nets.each_with_index do |a_net, idx|
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, dec_0], output: y0_nets[idx])
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, dec_1], output: y1_nets[idx])
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, dec_2], output: y2_nets[idx])
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, dec_3], output: y3_nets[idx])
        end
      end

      # Decoder2to4: 2-to-4 decoder with enable
      def lower_decoder2to4(component)
        a_nets = map_bus(component.inputs[:a])
        en_net = map_bus(component.inputs[:en]).first
        y0_net = map_bus(component.outputs[:y0]).first
        y1_net = map_bus(component.outputs[:y1]).first
        y2_net = map_bus(component.outputs[:y2]).first
        y3_net = map_bus(component.outputs[:y3]).first

        # Invert address bits
        a0_inv = new_temp
        a1_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [a_nets[0]], output: a0_inv)
        @ir.add_gate(type: Primitives::NOT, inputs: [a_nets[1]], output: a1_inv)

        # Decode: y0=en & ~a1 & ~a0, y1=en & ~a1 & a0, etc.
        dec_0 = new_temp
        dec_1 = new_temp
        dec_2 = new_temp
        dec_3 = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [a1_inv, a0_inv], output: dec_0)
        @ir.add_gate(type: Primitives::AND, inputs: [a1_inv, a_nets[0]], output: dec_1)
        @ir.add_gate(type: Primitives::AND, inputs: [a_nets[1], a0_inv], output: dec_2)
        @ir.add_gate(type: Primitives::AND, inputs: [a_nets[1], a_nets[0]], output: dec_3)

        @ir.add_gate(type: Primitives::AND, inputs: [en_net, dec_0], output: y0_net)
        @ir.add_gate(type: Primitives::AND, inputs: [en_net, dec_1], output: y1_net)
        @ir.add_gate(type: Primitives::AND, inputs: [en_net, dec_2], output: y2_net)
        @ir.add_gate(type: Primitives::AND, inputs: [en_net, dec_3], output: y3_net)
      end

      # Decoder3to8: 3-to-8 decoder with enable
      def lower_decoder3to8(component)
        a_nets = map_bus(component.inputs[:a])
        en_net = map_bus(component.inputs[:en]).first
        y_nets = (0..7).map { |i| map_bus(component.outputs[:"y#{i}"]).first }

        # Invert address bits
        a_inv = a_nets.map do |a_net|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [a_net], output: inv)
          inv
        end

        # Decode each output
        8.times do |i|
          # Build minterm: AND of each bit or its inverse
          bits = []
          3.times do |j|
            bits << ((i >> j) & 1 == 1 ? a_nets[j] : a_inv[j])
          end

          # AND the bits together
          and_01 = new_temp
          and_012 = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [bits[0], bits[1]], output: and_01)
          @ir.add_gate(type: Primitives::AND, inputs: [and_01, bits[2]], output: and_012)
          @ir.add_gate(type: Primitives::AND, inputs: [en_net, and_012], output: y_nets[i])
        end
      end

      # Encoder4to2: 4-to-2 priority encoder
      def lower_encoder4to2(component)
        a_nets = map_bus(component.inputs[:a])
        y_nets = map_bus(component.outputs[:y])
        valid_net = map_bus(component.outputs[:valid]).first

        # Priority: a[3] > a[2] > a[1] > a[0]
        # is_3 = a[3]
        # is_2 = ~a[3] & a[2]
        # is_1 = ~a[3] & ~a[2] & a[1]
        # is_0 = ~a[3] & ~a[2] & ~a[1] & a[0]

        a3_inv = new_temp
        a2_inv = new_temp
        a1_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [a_nets[3]], output: a3_inv)
        @ir.add_gate(type: Primitives::NOT, inputs: [a_nets[2]], output: a2_inv)
        @ir.add_gate(type: Primitives::NOT, inputs: [a_nets[1]], output: a1_inv)

        is_3 = a_nets[3]
        is_2 = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [a3_inv, a_nets[2]], output: is_2)
        is_1_temp = new_temp
        is_1 = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [a3_inv, a2_inv], output: is_1_temp)
        @ir.add_gate(type: Primitives::AND, inputs: [is_1_temp, a_nets[1]], output: is_1)

        # y[1] = is_3 OR is_2 (bit positions 2, 3)
        # y[0] = is_3 OR is_1 (bit positions 1, 3)
        @ir.add_gate(type: Primitives::OR, inputs: [is_3, is_2], output: y_nets[1])
        @ir.add_gate(type: Primitives::OR, inputs: [is_3, is_1], output: y_nets[0])

        # valid = a[3] OR a[2] OR a[1] OR a[0]
        or_01 = new_temp
        or_012 = new_temp
        @ir.add_gate(type: Primitives::OR, inputs: [a_nets[0], a_nets[1]], output: or_01)
        @ir.add_gate(type: Primitives::OR, inputs: [or_01, a_nets[2]], output: or_012)
        @ir.add_gate(type: Primitives::OR, inputs: [or_012, a_nets[3]], output: valid_net)
      end

      # Encoder8to3: 8-to-3 priority encoder
      def lower_encoder8to3(component)
        a_nets = map_bus(component.inputs[:a])
        y_nets = map_bus(component.outputs[:y])
        valid_net = map_bus(component.outputs[:valid]).first

        # Invert all input bits for priority logic
        a_inv = a_nets.map do |a_net|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [a_net], output: inv)
          inv
        end

        # Priority detection for each position (highest bit wins)
        is_active = []
        8.times do |i|
          if i == 7
            # Highest priority: just the bit itself
            is_active[i] = a_nets[7]
          else
            # is_i = ~a[7] & ~a[6] & ... & ~a[i+1] & a[i]
            terms = (i + 1..7).map { |j| a_inv[j] }
            terms << a_nets[i]
            result = terms.first
            terms[1..].each do |term|
              and_temp = new_temp
              @ir.add_gate(type: Primitives::AND, inputs: [result, term], output: and_temp)
              result = and_temp
            end
            is_active[i] = result
          end
        end

        # y[2] = is_4 OR is_5 OR is_6 OR is_7 (positions 4-7)
        or_45 = new_temp
        or_67 = new_temp
        or_4567 = new_temp
        @ir.add_gate(type: Primitives::OR, inputs: [is_active[4], is_active[5]], output: or_45)
        @ir.add_gate(type: Primitives::OR, inputs: [is_active[6], is_active[7]], output: or_67)
        @ir.add_gate(type: Primitives::OR, inputs: [or_45, or_67], output: or_4567)
        @ir.add_gate(type: Primitives::BUF, inputs: [or_4567], output: y_nets[2])

        # y[1] = is_2 OR is_3 OR is_6 OR is_7 (positions 2,3,6,7)
        or_23 = new_temp
        or_2367 = new_temp
        @ir.add_gate(type: Primitives::OR, inputs: [is_active[2], is_active[3]], output: or_23)
        @ir.add_gate(type: Primitives::OR, inputs: [or_23, or_67], output: or_2367)
        @ir.add_gate(type: Primitives::BUF, inputs: [or_2367], output: y_nets[1])

        # y[0] = is_1 OR is_3 OR is_5 OR is_7 (odd positions)
        or_13 = new_temp
        or_57 = new_temp
        or_1357 = new_temp
        @ir.add_gate(type: Primitives::OR, inputs: [is_active[1], is_active[3]], output: or_13)
        @ir.add_gate(type: Primitives::OR, inputs: [is_active[5], is_active[7]], output: or_57)
        @ir.add_gate(type: Primitives::OR, inputs: [or_13, or_57], output: or_1357)
        @ir.add_gate(type: Primitives::BUF, inputs: [or_1357], output: y_nets[0])

        # valid = OR of all input bits
        or_all = a_nets.first
        a_nets[1..].each do |a_net|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [or_all, a_net], output: or_temp)
          or_all = or_temp
        end
        @ir.add_gate(type: Primitives::BUF, inputs: [or_all], output: valid_net)
      end

      # ZeroDetect: Check if all bits are zero
      def lower_zero_detect(component)
        a_nets = map_bus(component.inputs[:a])
        zero_net = map_bus(component.outputs[:zero]).first

        # zero = NOR of all bits
        or_all = a_nets.first
        a_nets[1..].each do |a_net|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [or_all, a_net], output: or_temp)
          or_all = or_temp
        end
        @ir.add_gate(type: Primitives::NOT, inputs: [or_all], output: zero_net)
      end

      # SignExtend: Sign extend narrower value to wider
      def lower_sign_extend(component)
        a_nets = map_bus(component.inputs[:a])
        y_nets = map_bus(component.outputs[:y])

        in_width = a_nets.length
        out_width = y_nets.length

        # Copy input bits to lower output bits
        in_width.times do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [a_nets[idx]], output: y_nets[idx])
        end

        # Sign extend: copy MSB to all upper bits
        sign_bit = a_nets[-1]
        (in_width...out_width).each do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [sign_bit], output: y_nets[idx])
        end
      end

      # ZeroExtend: Zero extend narrower value to wider
      def lower_zero_extend(component)
        a_nets = map_bus(component.inputs[:a])
        y_nets = map_bus(component.outputs[:y])

        in_width = a_nets.length
        out_width = y_nets.length

        # Copy input bits to lower output bits
        in_width.times do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [a_nets[idx]], output: y_nets[idx])
        end

        # Zero extend: set upper bits to 0
        const_zero = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
        (in_width...out_width).each do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: y_nets[idx])
        end
      end

      # BitReverse: Reverse bit order
      def lower_bit_reverse(component)
        a_nets = map_bus(component.inputs[:a])
        y_nets = map_bus(component.outputs[:y])

        width = a_nets.length
        width.times do |idx|
          # y[idx] = a[width - 1 - idx]
          @ir.add_gate(type: Primitives::BUF, inputs: [a_nets[width - 1 - idx]], output: y_nets[idx])
        end
      end

      # PopCount: Count number of 1 bits using adder tree
      def lower_pop_count(component)
        a_nets = map_bus(component.inputs[:a])
        count_nets = map_bus(component.outputs[:count])

        width = a_nets.length
        out_width = count_nets.length

        # Build adder tree to sum all bits
        # Each bit is a 1-bit value, sum them all
        current = a_nets.dup

        while current.length > 1
          next_level = []
          current.each_slice(2) do |pair|
            if pair.length == 2
              # Add two values
              sum = lower_add_bits(pair[0], pair[1])
              next_level << sum
            else
              # Odd one out, pass through
              next_level << pair[0]
            end
          end
          current = next_level
        end

        # Final sum is the count - may need padding to match output width
        final_sum = current.first
        if final_sum.is_a?(Array)
          # Multi-bit result
          final_sum.each_with_index do |net, idx|
            if idx < out_width
              @ir.add_gate(type: Primitives::BUF, inputs: [net], output: count_nets[idx])
            end
          end
          # Zero-fill remaining bits
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          (final_sum.length...out_width).each do |idx|
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: count_nets[idx])
          end
        else
          # Single bit result
          @ir.add_gate(type: Primitives::BUF, inputs: [final_sum], output: count_nets[0])
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          (1...out_width).each do |idx|
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: count_nets[idx])
          end
        end
      end

      # Helper for pop_count: add two bit values/vectors and return result vector
      def lower_add_bits(a, b)
        if a.is_a?(Array) && b.is_a?(Array)
          # Add two vectors
          width = [a.length, b.length].max
          result = []
          carry = nil

          width.times do |idx|
            a_bit = idx < a.length ? a[idx] : nil
            b_bit = idx < b.length ? b[idx] : nil

            if a_bit.nil?
              a_bit = new_temp
              @ir.add_gate(type: Primitives::CONST, inputs: [], output: a_bit, value: 0)
            end
            if b_bit.nil?
              b_bit = new_temp
              @ir.add_gate(type: Primitives::CONST, inputs: [], output: b_bit, value: 0)
            end

            if carry.nil?
              # Half adder
              sum = new_temp
              carry = new_temp
              @ir.add_gate(type: Primitives::XOR, inputs: [a_bit, b_bit], output: sum)
              @ir.add_gate(type: Primitives::AND, inputs: [a_bit, b_bit], output: carry)
              result << sum
            else
              # Full adder
              sum = new_temp
              axb = new_temp
              ab = new_temp
              cab = new_temp
              new_carry = new_temp
              @ir.add_gate(type: Primitives::XOR, inputs: [a_bit, b_bit], output: axb)
              @ir.add_gate(type: Primitives::XOR, inputs: [axb, carry], output: sum)
              @ir.add_gate(type: Primitives::AND, inputs: [a_bit, b_bit], output: ab)
              @ir.add_gate(type: Primitives::AND, inputs: [carry, axb], output: cab)
              @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: new_carry)
              result << sum
              carry = new_carry
            end
          end
          result << carry if carry
          result
        elsif a.is_a?(Array)
          lower_add_bits(a, [b])
        elsif b.is_a?(Array)
          lower_add_bits([a], b)
        else
          # Two single bits: half adder
          sum = new_temp
          carry = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a, b], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [a, b], output: carry)
          [sum, carry]
        end
      end

      # LZCount: Count leading zeros
      def lower_lz_count(component)
        a_nets = map_bus(component.inputs[:a])
        count_nets = map_bus(component.outputs[:count])
        all_zero_net = map_bus(component.outputs[:all_zero]).first

        width = a_nets.length
        out_width = count_nets.length

        # For simplicity, use a priority encoder approach:
        # Find the position of the highest set bit, then leading zeros = width - 1 - position
        # If all zeros, count = width

        # First check all_zero
        or_all = a_nets.first
        a_nets[1..].each do |a_net|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [or_all, a_net], output: or_temp)
          or_all = or_temp
        end
        @ir.add_gate(type: Primitives::NOT, inputs: [or_all], output: all_zero_net)

        # Priority encode from MSB
        # lz[i] = 1 if all bits from MSB down to i are 0, and bit i-1 is 1 (or i=0)
        # Use recursive halving or direct encoding

        # For 8 bits: encode position of highest set bit
        # Then count = 7 - position (or 8 if all zero)

        # Build position of highest set bit (similar to priority encoder)
        a_inv = a_nets.map do |a_net|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [a_net], output: inv)
          inv
        end

        # is_at[i] = ~a[n-1] & ~a[n-2] & ... & ~a[i+1] & a[i]
        # This gives us position of highest set bit
        is_at = []
        width.times do |i|
          idx = width - 1 - i  # Start from MSB
          if i == 0
            is_at[idx] = a_nets[idx]
          else
            terms = ((idx + 1)...width).map { |j| a_inv[j] }
            terms << a_nets[idx]
            result = terms.first
            terms[1..].each do |term|
              and_temp = new_temp
              @ir.add_gate(type: Primitives::AND, inputs: [result, term], output: and_temp)
              result = and_temp
            end
            is_at[idx] = result
          end
        end

        # Now compute leading zero count based on position
        # LZ = 0 if MSB set, 1 if MSB-1 set, ..., width if all zero
        # Build output using mux chain or direct encoding

        # For each output bit, determine which positions contribute
        out_width.times do |out_idx|
          # count[out_idx] = OR of all positions where bit out_idx is set
          contributors = []
          width.times do |pos|
            lz_val = width - 1 - pos  # Leading zeros if highest bit is at pos
            if (lz_val >> out_idx) & 1 == 1
              contributors << is_at[pos]
            end
          end
          # Add all_zero case: count = width
          if (width >> out_idx) & 1 == 1
            contributors << all_zero_net
          end

          if contributors.empty?
            const_zero = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: count_nets[out_idx])
          elsif contributors.length == 1
            @ir.add_gate(type: Primitives::BUF, inputs: [contributors.first], output: count_nets[out_idx])
          else
            or_result = contributors.first
            contributors[1..].each do |c|
              or_temp = new_temp
              @ir.add_gate(type: Primitives::OR, inputs: [or_result, c], output: or_temp)
              or_result = or_temp
            end
            @ir.add_gate(type: Primitives::BUF, inputs: [or_result], output: count_nets[out_idx])
          end
        end
      end

      # BarrelShifter: Multi-mode barrel shifter
      def lower_barrel_shifter(component)
        a_nets = map_bus(component.inputs[:a])
        shift_nets = map_bus(component.inputs[:shift])
        dir_net = map_bus(component.inputs[:dir]).first
        arith_net = map_bus(component.inputs[:arith]).first
        rotate_net = map_bus(component.inputs[:rotate]).first
        y_nets = map_bus(component.outputs[:y])

        width = a_nets.length
        shift_width = shift_nets.length

        # Use mux-based barrel shifter
        # Each shift bit selects between shifted/non-shifted version

        # Build all 4 shift variants:
        # 1. Left logical (fill with 0)
        # 2. Right logical (fill with 0)
        # 3. Right arithmetic (fill with sign)
        # 4. Rotate left
        # 5. Rotate right

        # Then select based on dir, arith, rotate flags

        # For simplicity, build shift stages for each shift bit
        # Then mux between directions/modes

        # Left shift chain
        left_current = a_nets.dup
        shift_width.times do |stage|
          shift_amt = 1 << stage
          next_level = []
          width.times do |idx|
            new_pos = idx - shift_amt
            if new_pos >= 0
              shifted = left_current[new_pos]
            else
              shifted = new_temp
              @ir.add_gate(type: Primitives::CONST, inputs: [], output: shifted, value: 0)
            end
            muxed = new_temp
            @ir.add_gate(type: Primitives::MUX, inputs: [left_current[idx], shifted, shift_nets[stage]], output: muxed)
            next_level << muxed
          end
          left_current = next_level
        end

        # Right logical shift chain
        right_current = a_nets.dup
        shift_width.times do |stage|
          shift_amt = 1 << stage
          next_level = []
          width.times do |idx|
            new_pos = idx + shift_amt
            if new_pos < width
              shifted = right_current[new_pos]
            else
              shifted = new_temp
              @ir.add_gate(type: Primitives::CONST, inputs: [], output: shifted, value: 0)
            end
            muxed = new_temp
            @ir.add_gate(type: Primitives::MUX, inputs: [right_current[idx], shifted, shift_nets[stage]], output: muxed)
            next_level << muxed
          end
          right_current = next_level
        end

        # Right arithmetic shift chain (fill with sign bit)
        sign_bit = a_nets[-1]
        arith_current = a_nets.dup
        shift_width.times do |stage|
          shift_amt = 1 << stage
          next_level = []
          width.times do |idx|
            new_pos = idx + shift_amt
            if new_pos < width
              shifted = arith_current[new_pos]
            else
              shifted = sign_bit
            end
            muxed = new_temp
            @ir.add_gate(type: Primitives::MUX, inputs: [arith_current[idx], shifted, shift_nets[stage]], output: muxed)
            next_level << muxed
          end
          arith_current = next_level
        end

        # Rotate left chain
        rot_left_current = a_nets.dup
        shift_width.times do |stage|
          shift_amt = 1 << stage
          next_level = []
          width.times do |idx|
            new_pos = (idx - shift_amt) % width
            shifted = rot_left_current[new_pos]
            muxed = new_temp
            @ir.add_gate(type: Primitives::MUX, inputs: [rot_left_current[idx], shifted, shift_nets[stage]], output: muxed)
            next_level << muxed
          end
          rot_left_current = next_level
        end

        # Rotate right chain
        rot_right_current = a_nets.dup
        shift_width.times do |stage|
          shift_amt = 1 << stage
          next_level = []
          width.times do |idx|
            new_pos = (idx + shift_amt) % width
            shifted = rot_right_current[new_pos]
            muxed = new_temp
            @ir.add_gate(type: Primitives::MUX, inputs: [rot_right_current[idx], shifted, shift_nets[stage]], output: muxed)
            next_level << muxed
          end
          rot_right_current = next_level
        end

        # Select based on control signals:
        # dir=0, rotate=0: left logical
        # dir=0, rotate=1: rotate left
        # dir=1, rotate=0, arith=0: right logical
        # dir=1, rotate=0, arith=1: right arithmetic
        # dir=1, rotate=1: rotate right

        dir_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [dir_net], output: dir_inv)

        width.times do |idx|
          # Left side: mux between left_logical and rotate_left based on rotate
          left_result = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [left_current[idx], rot_left_current[idx], rotate_net], output: left_result)

          # Right side: first mux between logical and arithmetic based on arith
          right_shift_result = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [right_current[idx], arith_current[idx], arith_net], output: right_shift_result)

          # Then mux between shift and rotate based on rotate
          right_result = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [right_shift_result, rot_right_current[idx], rotate_net], output: right_result)

          # Final mux based on dir
          @ir.add_gate(type: Primitives::MUX, inputs: [left_result, right_result, dir_net], output: y_nets[idx])
        end
      end

      def lower_half_adder(component)
        a_net = map_bus(component.inputs[:a]).first
        b_net = map_bus(component.inputs[:b]).first
        sum_net = map_bus(component.outputs[:sum]).first
        cout_net = map_bus(component.outputs[:cout]).first
        @ir.add_gate(type: Primitives::XOR, inputs: [a_net, b_net], output: sum_net)
        @ir.add_gate(type: Primitives::AND, inputs: [a_net, b_net], output: cout_net)
      end

      def lower_full_adder(component)
        a_net = map_bus(component.inputs[:a]).first
        b_net = map_bus(component.inputs[:b]).first
        cin_net = map_bus(component.inputs[:cin]).first
        sum_net = map_bus(component.outputs[:sum]).first
        cout_net = map_bus(component.outputs[:cout]).first

        axb_net = new_temp
        a_and_b = new_temp
        cin_and_axb = new_temp

        @ir.add_gate(type: Primitives::XOR, inputs: [a_net, b_net], output: axb_net)
        @ir.add_gate(type: Primitives::XOR, inputs: [axb_net, cin_net], output: sum_net)
        @ir.add_gate(type: Primitives::AND, inputs: [a_net, b_net], output: a_and_b)
        @ir.add_gate(type: Primitives::AND, inputs: [cin_net, axb_net], output: cin_and_axb)
        @ir.add_gate(type: Primitives::OR, inputs: [a_and_b, cin_and_axb], output: cout_net)
      end

      def lower_ripple_adder(component)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        cin_net = map_bus(component.inputs[:cin]).first
        sum_nets = map_bus(component.outputs[:sum])
        cout_net = map_bus(component.outputs[:cout]).first
        overflow_net = map_bus(component.outputs[:overflow]).first

        carry = cin_net
        width = a_nets.length
        width.times do |idx|
          a_net = a_nets[idx]
          b_net = b_nets[idx]
          sum_net = sum_nets[idx]
          cout = (idx == width - 1) ? cout_net : new_temp

          axb_net = new_temp
          a_and_b = new_temp
          cin_and_axb = new_temp

          @ir.add_gate(type: Primitives::XOR, inputs: [a_net, b_net], output: axb_net)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb_net, carry], output: sum_net)
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, b_net], output: a_and_b)
          @ir.add_gate(type: Primitives::AND, inputs: [carry, axb_net], output: cin_and_axb)
          @ir.add_gate(type: Primitives::OR, inputs: [a_and_b, cin_and_axb], output: cout)
          carry = cout
        end

        a_msb = a_nets[-1]
        b_msb = b_nets[-1]
        sum_msb = sum_nets[-1]
        xor_ab = new_temp
        xnor_ab = new_temp
        sum_xor_a = new_temp

        @ir.add_gate(type: Primitives::XOR, inputs: [a_msb, b_msb], output: xor_ab)
        @ir.add_gate(type: Primitives::NOT, inputs: [xor_ab], output: xnor_ab)
        @ir.add_gate(type: Primitives::XOR, inputs: [sum_msb, a_msb], output: sum_xor_a)
        @ir.add_gate(type: Primitives::AND, inputs: [xnor_ab, sum_xor_a], output: overflow_net)
      end

      # Subtractor: A - B - bin using two's complement
      # diff = A + ~B + 1 - bin = A + ~B + (1 - bin) = A + ~B + ~bin
      def lower_subtractor(component)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        bin_net = map_bus(component.inputs[:bin]).first
        diff_nets = map_bus(component.outputs[:diff])
        bout_net = map_bus(component.outputs[:bout]).first
        overflow_net = map_bus(component.outputs[:overflow]).first

        width = a_nets.length

        # Invert B for two's complement
        b_inv_nets = b_nets.map do |b_net|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [b_net], output: inv)
          inv
        end

        # Invert bin to get initial carry (1 - bin = ~bin for single bit)
        cin_net = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [bin_net], output: cin_net)

        # Ripple carry addition: A + ~B + ~bin
        carry = cin_net
        width.times do |idx|
          a_net = a_nets[idx]
          b_inv = b_inv_nets[idx]
          diff_net = diff_nets[idx]

          axb = new_temp
          a_and_b = new_temp
          cin_and_axb = new_temp
          cout = new_temp

          @ir.add_gate(type: Primitives::XOR, inputs: [a_net, b_inv], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, carry], output: diff_net)
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, b_inv], output: a_and_b)
          @ir.add_gate(type: Primitives::AND, inputs: [carry, axb], output: cin_and_axb)
          @ir.add_gate(type: Primitives::OR, inputs: [a_and_b, cin_and_axb], output: cout)
          carry = cout
        end

        # Borrow out = NOT(carry out from subtraction)
        @ir.add_gate(type: Primitives::NOT, inputs: [carry], output: bout_net)

        # Overflow: when operand signs differ and result sign differs from A
        a_msb = a_nets[-1]
        b_msb = b_nets[-1]
        diff_msb = diff_nets[-1]
        signs_differ = new_temp
        diff_xor_a = new_temp
        @ir.add_gate(type: Primitives::XOR, inputs: [a_msb, b_msb], output: signs_differ)
        @ir.add_gate(type: Primitives::XOR, inputs: [diff_msb, a_msb], output: diff_xor_a)
        @ir.add_gate(type: Primitives::AND, inputs: [signs_differ, diff_xor_a], output: overflow_net)
      end

      # AddSub: Combined adder/subtractor
      def lower_add_sub(component)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        sub_net = map_bus(component.inputs[:sub]).first
        result_nets = map_bus(component.outputs[:result])
        cout_net = map_bus(component.outputs[:cout]).first
        overflow_net = map_bus(component.outputs[:overflow]).first
        zero_net = map_bus(component.outputs[:zero]).first
        negative_net = map_bus(component.outputs[:negative]).first

        width = a_nets.length

        # B XOR sub: inverts B when subtracting
        b_xor_nets = b_nets.map do |b_net|
          xor_net = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [b_net, sub_net], output: xor_net)
          xor_net
        end

        # Ripple carry addition: A + (B XOR sub) + sub
        carry = sub_net
        width.times do |idx|
          a_net = a_nets[idx]
          b_xor = b_xor_nets[idx]
          result_net = result_nets[idx]

          axb = new_temp
          a_and_b = new_temp
          cin_and_axb = new_temp
          cout = new_temp

          @ir.add_gate(type: Primitives::XOR, inputs: [a_net, b_xor], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, carry], output: result_net)
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, b_xor], output: a_and_b)
          @ir.add_gate(type: Primitives::AND, inputs: [carry, axb], output: cin_and_axb)
          @ir.add_gate(type: Primitives::OR, inputs: [a_and_b, cin_and_axb], output: cout)
          carry = cout
        end

        # Cout: for add it's carry, for sub it's inverted (borrow)
        # cout = carry XOR sub (invert carry when subtracting)
        @ir.add_gate(type: Primitives::XOR, inputs: [carry, sub_net], output: cout_net)

        # Overflow detection
        a_msb = a_nets[-1]
        b_xor_msb = b_xor_nets[-1]
        result_msb = result_nets[-1]
        signs_same = new_temp
        xor_ab = new_temp
        result_xor_a = new_temp
        @ir.add_gate(type: Primitives::XOR, inputs: [a_msb, b_xor_msb], output: xor_ab)
        @ir.add_gate(type: Primitives::NOT, inputs: [xor_ab], output: signs_same)
        @ir.add_gate(type: Primitives::XOR, inputs: [result_msb, a_msb], output: result_xor_a)
        @ir.add_gate(type: Primitives::AND, inputs: [signs_same, result_xor_a], output: overflow_net)

        # Zero flag: NOR of all result bits
        zero_or = result_nets.first
        result_nets[1..].each do |r_net|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [zero_or, r_net], output: or_temp)
          zero_or = or_temp
        end
        @ir.add_gate(type: Primitives::NOT, inputs: [zero_or], output: zero_net)

        # Negative flag: MSB of result
        @ir.add_gate(type: Primitives::BUF, inputs: [result_msb], output: negative_net)
      end

      # Comparator: Compare two values
      def lower_comparator(component)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        signed_cmp_net = map_bus(component.inputs[:signed_cmp]).first
        eq_net = map_bus(component.outputs[:eq]).first
        gt_net = map_bus(component.outputs[:gt]).first
        lt_net = map_bus(component.outputs[:lt]).first
        gte_net = map_bus(component.outputs[:gte]).first
        lte_net = map_bus(component.outputs[:lte]).first

        width = a_nets.length

        # Compute A == B: AND of all (A[i] XNOR B[i])
        eq_bits = a_nets.zip(b_nets).map do |a_net, b_net|
          xor_temp = new_temp
          xnor_temp = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a_net, b_net], output: xor_temp)
          @ir.add_gate(type: Primitives::NOT, inputs: [xor_temp], output: xnor_temp)
          xnor_temp
        end
        unsigned_eq = reduce_and(eq_bits)

        # Compute unsigned A > B using subtraction: A - B, check if no borrow and not equal
        # Using ripple subtractor to compute A - B
        b_inv_nets = b_nets.map do |b_net|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [b_net], output: inv)
          inv
        end

        const_one = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_one, value: 1)

        carry = const_one
        diff_nets = []
        width.times do |idx|
          a_net = a_nets[idx]
          b_inv = b_inv_nets[idx]
          diff_net = new_temp
          diff_nets << diff_net

          axb = new_temp
          a_and_b = new_temp
          cin_and_axb = new_temp
          cout = new_temp

          @ir.add_gate(type: Primitives::XOR, inputs: [a_net, b_inv], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, carry], output: diff_net)
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, b_inv], output: a_and_b)
          @ir.add_gate(type: Primitives::AND, inputs: [carry, axb], output: cin_and_axb)
          @ir.add_gate(type: Primitives::OR, inputs: [a_and_b, cin_and_axb], output: cout)
          carry = cout
        end

        # Unsigned A > B: carry out is 1 (no borrow) and not equal
        not_eq = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [unsigned_eq], output: not_eq)
        unsigned_gt = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [carry, not_eq], output: unsigned_gt)

        # Unsigned A < B: NOT(A >= B) = NOT(carry)
        unsigned_lt = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [carry], output: unsigned_lt)

        # Signed comparison: consider sign bits
        a_msb = a_nets[-1]
        b_msb = b_nets[-1]
        signs_differ = new_temp
        @ir.add_gate(type: Primitives::XOR, inputs: [a_msb, b_msb], output: signs_differ)

        # When signs differ: A < B if A is negative (a_msb = 1)
        # When signs same: use unsigned comparison
        signed_lt = new_temp
        @ir.add_gate(type: Primitives::MUX, inputs: [unsigned_lt, a_msb, signs_differ], output: signed_lt)

        signed_gt = new_temp
        @ir.add_gate(type: Primitives::MUX, inputs: [unsigned_gt, b_msb, signs_differ], output: signed_gt)

        # Select based on signed_cmp flag
        @ir.add_gate(type: Primitives::BUF, inputs: [unsigned_eq], output: eq_net)
        @ir.add_gate(type: Primitives::MUX, inputs: [unsigned_gt, signed_gt, signed_cmp_net], output: gt_net)
        @ir.add_gate(type: Primitives::MUX, inputs: [unsigned_lt, signed_lt, signed_cmp_net], output: lt_net)

        # GTE = EQ OR GT
        @ir.add_gate(type: Primitives::OR, inputs: [eq_net, gt_net], output: gte_net)
        # LTE = EQ OR LT
        @ir.add_gate(type: Primitives::OR, inputs: [eq_net, lt_net], output: lte_net)
      end

      # IncDec: Increment or decrement by 1
      def lower_inc_dec(component)
        a_nets = map_bus(component.inputs[:a])
        inc_net = map_bus(component.inputs[:inc]).first
        result_nets = map_bus(component.outputs[:result])
        cout_net = map_bus(component.outputs[:cout]).first

        width = a_nets.length

        # For increment (inc=1): A + 0...01 = A + 1, carry_in = 1, b = 0
        # For decrement (inc=0): A + 1...11 = A + (-1) = A - 1, carry_in = 0, b = 1
        #
        # Using full adder with b = NOT(inc) for each bit:
        #   sum = a XOR b XOR carry = a XOR NOT(inc) XOR carry
        #   next_carry = (a AND b) OR (carry AND (a XOR b))
        #             = (a AND NOT(inc)) OR (carry AND (a XOR NOT(inc)))
        #
        # For increment (b=0): next_carry = 0 OR (carry AND a) = carry AND a (half adder)
        # For decrement (b=1): next_carry = a OR (carry AND NOT(a)) = a OR carry

        carry = inc_net  # Start with inc as carry-in (1 for inc, 0 for dec)
        inc_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [inc_net], output: inc_inv)

        width.times do |idx|
          a_net = a_nets[idx]
          result_net = result_nets[idx]

          # a_xor = a XOR NOT(inc) = a XOR b
          a_xor = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a_net, inc_inv], output: a_xor)

          # sum = a_xor XOR carry
          @ir.add_gate(type: Primitives::XOR, inputs: [a_xor, carry], output: result_net)

          # Full adder carry: (a AND b) OR (carry AND a_xor)
          # a_and_b = a AND NOT(inc)
          a_and_b = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [a_net, inc_inv], output: a_and_b)

          # carry_and_axor = carry AND a_xor
          carry_and_axor = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [carry, a_xor], output: carry_and_axor)

          # next_carry = a_and_b OR carry_and_axor
          next_carry = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [a_and_b, carry_and_axor], output: next_carry)
          carry = next_carry
        end

        # Cout: overflow/underflow detection
        # For increment: cout = 1 when A == max (all 1s)
        # For decrement: cout = 1 when A == 0
        # Combined with mux based on inc

        # Check if A == 0xFF...F (all 1s) - AND all bits
        all_ones = reduce_and(a_nets)

        # Check if A == 0 - NOR all bits
        any_bit = a_nets.first
        a_nets[1..].each do |a_net|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [any_bit, a_net], output: or_temp)
          any_bit = or_temp
        end
        all_zeros = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [any_bit], output: all_zeros)

        # Select cout based on inc
        @ir.add_gate(type: Primitives::MUX, inputs: [all_zeros, all_ones, inc_net], output: cout_net)
      end

      # Helper: reduce AND - AND all nets together
      def reduce_and(nets)
        return nets.first if nets.length == 1

        result = nets.first
        nets[1..].each do |net|
          and_temp = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [result, net], output: and_temp)
          result = and_temp
        end
        result
      end

      def lower_dff(component, async_reset: false)
        d_net = map_bus(component.inputs[:d]).first
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        q_net = map_bus(component.outputs[:q]).first
        qn_net = map_bus(component.outputs[:qn]).first

        @ir.add_dff(d: d_net, q: q_net, rst: rst_net, en: en_net, async_reset: async_reset)
        @ir.add_gate(type: Primitives::NOT, inputs: [q_net], output: qn_net)
      end

      # Register: Multi-bit register with reset and enable
      def lower_register(component)
        d_nets = map_bus(component.inputs[:d])
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        q_nets = map_bus(component.outputs[:q])

        width = d_nets.length
        width.times do |idx|
          @ir.add_dff(d: d_nets[idx], q: q_nets[idx], rst: rst_net, en: en_net)
        end
      end

      # ShiftRegister: Shift register with serial/parallel I/O
      def lower_shift_register(component)
        d_in_net = map_bus(component.inputs[:d_in]).first
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        dir_net = map_bus(component.inputs[:dir]).first
        load_net = map_bus(component.inputs[:load]).first
        d_nets = map_bus(component.inputs[:d])
        q_nets = map_bus(component.outputs[:q])
        d_out_net = map_bus(component.outputs[:d_out]).first

        width = d_nets.length

        # For each bit position, compute next value:
        # If load: d[i]
        # Elif shift right (dir=0): q[i+1] (or d_in for MSB)
        # Elif shift left (dir=1): q[i-1] (or d_in for LSB)

        # Create intermediate signals for the feedback
        q_internal = width.times.map { new_temp }

        width.times do |idx|
          # Right shift value: next higher bit, or d_in for MSB
          right_val = idx < width - 1 ? q_internal[idx + 1] : d_in_net

          # Left shift value: next lower bit, or d_in for LSB
          left_val = idx > 0 ? q_internal[idx - 1] : d_in_net

          # Select shift direction
          shift_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [right_val, left_val, dir_net], output: shift_val)

          # Select between load and shift
          next_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [shift_val, d_nets[idx], load_net], output: next_val)

          # Create DFF for this bit
          @ir.add_dff(d: next_val, q: q_internal[idx], rst: rst_net, en: en_net)

          # Buffer to output
          @ir.add_gate(type: Primitives::BUF, inputs: [q_internal[idx]], output: q_nets[idx])
        end

        # Serial output: LSB when shifting right (dir=0), MSB when shifting left (dir=1)
        @ir.add_gate(type: Primitives::MUX, inputs: [q_internal[0], q_internal[width - 1], dir_net], output: d_out_net)
      end

      # Counter: Binary counter with up/down, load
      def lower_counter(component)
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        up_net = map_bus(component.inputs[:up]).first
        load_net = map_bus(component.inputs[:load]).first
        d_nets = map_bus(component.inputs[:d])
        q_nets = map_bus(component.outputs[:q])
        tc_net = map_bus(component.outputs[:tc]).first
        zero_net = map_bus(component.outputs[:zero]).first

        width = d_nets.length

        # Create internal state
        q_internal = width.times.map { new_temp }

        # Compute increment and decrement using ripple carry
        # Increment: q + 1
        # Decrement: q - 1 = q + all_ones (two's complement)

        const_one = new_temp
        const_zero = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_one, value: 1)
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)

        # Up direction: use up_net as carry in
        up_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [up_net], output: up_inv)

        # Build adder chain
        # When up=1: add 1 (carry_in = 1, addend = 0)
        # When up=0: subtract 1 = add all 1s + 1, but simpler: add -1 = add all 1s with carry 1
        carry = const_one
        count_result = []
        width.times do |idx|
          q_bit = q_internal[idx]
          # Addend bit: 0 for increment (up=1), 1 for decrement (up=0)
          addend = up_inv

          # Full adder
          axb = new_temp
          sum = new_temp
          ab = new_temp
          cab = new_temp
          cout = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [q_bit, addend], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [q_bit, addend], output: ab)
          @ir.add_gate(type: Primitives::AND, inputs: [carry, axb], output: cab)
          @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: cout)
          count_result << sum
          carry = cout
        end

        # Select next value: load > count
        width.times do |idx|
          next_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [count_result[idx], d_nets[idx], load_net], output: next_val)
          @ir.add_dff(d: next_val, q: q_internal[idx], rst: rst_net, en: en_net)
          @ir.add_gate(type: Primitives::BUF, inputs: [q_internal[idx]], output: q_nets[idx])
        end

        # Terminal count: all 1s when counting up, all 0s when counting down
        all_ones = reduce_and(q_internal)
        any_bit = q_internal.first
        q_internal[1..].each do |q_bit|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [any_bit, q_bit], output: or_temp)
          any_bit = or_temp
        end
        all_zeros = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [any_bit], output: all_zeros)
        @ir.add_gate(type: Primitives::MUX, inputs: [all_zeros, all_ones, up_net], output: tc_net)

        # Zero flag
        @ir.add_gate(type: Primitives::BUF, inputs: [all_zeros], output: zero_net)
      end

      # JKFlipFlop: J=0,K=0 -> hold; J=0,K=1 -> reset; J=1,K=0 -> set; J=1,K=1 -> toggle
      def lower_jk_flip_flop(component)
        j_net = map_bus(component.inputs[:j]).first
        k_net = map_bus(component.inputs[:k]).first
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        q_net = map_bus(component.outputs[:q]).first
        qn_net = map_bus(component.outputs[:qn]).first

        # JK flip-flop characteristic equation: Q_next = J*~Q + ~K*Q
        q_internal = new_temp

        q_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [q_internal], output: q_inv)

        k_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [k_net], output: k_inv)

        jqn = new_temp
        kq = new_temp
        d_next = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [j_net, q_inv], output: jqn)
        @ir.add_gate(type: Primitives::AND, inputs: [k_inv, q_internal], output: kq)
        @ir.add_gate(type: Primitives::OR, inputs: [jqn, kq], output: d_next)

        @ir.add_dff(d: d_next, q: q_internal, rst: rst_net, en: en_net)

        @ir.add_gate(type: Primitives::BUF, inputs: [q_internal], output: q_net)
        @ir.add_gate(type: Primitives::NOT, inputs: [q_internal], output: qn_net)
      end

      # TFlipFlop: Toggle when T=1
      def lower_t_flip_flop(component)
        t_net = map_bus(component.inputs[:t]).first
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        q_net = map_bus(component.outputs[:q]).first
        qn_net = map_bus(component.outputs[:qn]).first

        # T flip-flop: Q_next = T XOR Q
        q_internal = new_temp

        d_next = new_temp
        @ir.add_gate(type: Primitives::XOR, inputs: [t_net, q_internal], output: d_next)

        @ir.add_dff(d: d_next, q: q_internal, rst: rst_net, en: en_net)

        @ir.add_gate(type: Primitives::BUF, inputs: [q_internal], output: q_net)
        @ir.add_gate(type: Primitives::NOT, inputs: [q_internal], output: qn_net)
      end

      # SRFlipFlop: Set-Reset flip-flop
      def lower_sr_flip_flop(component)
        s_net = map_bus(component.inputs[:s]).first
        r_net = map_bus(component.inputs[:r]).first
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        q_net = map_bus(component.outputs[:q]).first
        qn_net = map_bus(component.outputs[:qn]).first

        # SR flip-flop: Q_next = S + ~R*Q (R takes precedence)
        q_internal = new_temp

        r_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [r_net], output: r_inv)

        rq = new_temp
        d_next = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [r_inv, q_internal], output: rq)
        @ir.add_gate(type: Primitives::OR, inputs: [s_net, rq], output: d_next)

        # Apply R dominance: if R=1, force d_next to 0
        d_final = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [d_next, r_inv], output: d_final)

        @ir.add_dff(d: d_final, q: q_internal, rst: rst_net, en: en_net)

        @ir.add_gate(type: Primitives::BUF, inputs: [q_internal], output: q_net)
        @ir.add_gate(type: Primitives::NOT, inputs: [q_internal], output: qn_net)
      end

      # SRLatch: Combinational SR latch (level-sensitive)
      def lower_sr_latch(component)
        s_net = map_bus(component.inputs[:s]).first
        r_net = map_bus(component.inputs[:r]).first
        q_net = map_bus(component.outputs[:q]).first
        qn_net = map_bus(component.outputs[:qn]).first

        # Cross-coupled NOR gates
        # Q = NOR(R, Qn)
        # Qn = NOR(S, Q)
        # This creates feedback - for gate-level we approximate with the stable state:
        # If S=1, R=0: Q=1
        # If S=0, R=1: Q=0
        # If S=0, R=0: hold (we can't easily model memory in combinational gates)
        # If S=1, R=1: invalid (Q=0 in our implementation)

        # For synthesis purposes, model as: Q = S AND NOT R
        r_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [r_net], output: r_inv)
        @ir.add_gate(type: Primitives::AND, inputs: [s_net, r_inv], output: q_net)
        @ir.add_gate(type: Primitives::NOT, inputs: [q_net], output: qn_net)
      end

      # TristateBuffer: Buffer with enable (outputs 0 when disabled)
      def lower_tristate_buffer(component)
        a_net = map_bus(component.inputs[:a]).first
        en_net = map_bus(component.inputs[:en]).first
        y_net = map_bus(component.outputs[:y]).first

        # y = mux(en, a, 0) - when en=1, output a; when en=0, output 0
        const_zero = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
        @ir.add_gate(type: Primitives::MUX, inputs: [const_zero, a_net, en_net], output: y_net)
      end

      # MuxN: N-way mux using mux tree
      def lower_mux_n(component)
        # Get all input signals
        input_count = component.instance_variable_get(:@input_count) || 2
        sel_nets = map_bus(component.inputs[:sel])
        y_nets = map_bus(component.outputs[:y])
        width = y_nets.length

        # Gather input nets
        inputs = []
        input_count.times do |i|
          in_sym = :"in#{i}"
          if component.inputs[in_sym]
            inputs << map_bus(component.inputs[in_sym])
          end
        end

        # Build mux tree for each output bit
        width.times do |bit_idx|
          bit_inputs = inputs.map { |in_nets| in_nets[bit_idx] }
          result = lower_mux_tree(bit_inputs, sel_nets, 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: y_nets[bit_idx])
        end
      end

      # Helper: build mux tree recursively
      def lower_mux_tree(inputs, sel_nets, sel_idx)
        return inputs.first if inputs.length == 1

        if inputs.length == 2
          result = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [inputs[0], inputs[1], sel_nets[sel_idx]], output: result)
          return result
        end

        # Split inputs in half and recurse
        mid = inputs.length / 2
        low_inputs = inputs[0...mid]
        high_inputs = inputs[mid..]

        # Pad high_inputs if needed
        while high_inputs.length < low_inputs.length
          zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: zero, value: 0)
          high_inputs << zero
        end

        low_result = lower_mux_tree(low_inputs, sel_nets, sel_idx)
        high_result = lower_mux_tree(high_inputs, sel_nets, sel_idx)

        result = new_temp
        next_sel = sel_idx + Math.log2(low_inputs.length).ceil
        next_sel = [next_sel, sel_nets.length - 1].min
        @ir.add_gate(type: Primitives::MUX, inputs: [low_result, high_result, sel_nets[next_sel]], output: result)
        result
      end

      # DecoderN: N-bit decoder to 2^N outputs
      def lower_decoder_n(component)
        a_nets = map_bus(component.inputs[:a])
        en_net = map_bus(component.inputs[:en]).first
        width = a_nets.length
        output_count = 1 << width

        # Invert all address bits
        a_inv = a_nets.map do |a_net|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [a_net], output: inv)
          inv
        end

        # Generate each output
        output_count.times do |i|
          out_sym = :"y#{i}"
          next unless component.outputs[out_sym]

          y_net = map_bus(component.outputs[out_sym]).first

          # Build minterm
          bits = []
          width.times do |j|
            bits << ((i >> j) & 1 == 1 ? a_nets[j] : a_inv[j])
          end

          # AND all bits together with enable
          and_result = bits.first
          bits[1..].each do |bit|
            and_temp = new_temp
            @ir.add_gate(type: Primitives::AND, inputs: [and_result, bit], output: and_temp)
            and_result = and_temp
          end

          @ir.add_gate(type: Primitives::AND, inputs: [en_net, and_result], output: y_net)
        end
      end

      # Multiplier: Array multiplier
      def lower_multiplier(component)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        product_nets = map_bus(component.outputs[:product])

        width = a_nets.length
        product_width = product_nets.length

        # Array multiplier: generate partial products and sum
        # pp[i][j] = a[j] AND b[i]
        partial_products = []
        width.times do |i|
          row = []
          width.times do |j|
            pp = new_temp
            @ir.add_gate(type: Primitives::AND, inputs: [a_nets[j], b_nets[i]], output: pp)
            row << pp
          end
          partial_products << row
        end

        # Sum partial products using carry-save adders then final adder
        # For simplicity, use ripple-carry addition between rows
        result = Array.new(product_width) { new_temp }

        # Initialize with first row (shifted by 0)
        width.times do |j|
          @ir.add_gate(type: Primitives::BUF, inputs: [partial_products[0][j]], output: result[j])
        end
        (width...product_width).each do |j|
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: result[j], value: 0)
        end

        # Add remaining rows
        (1...width).each do |i|
          # Add partial_products[i] shifted left by i to result
          carry = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: carry, value: 0)

          (i...product_width).each do |j|
            pp_idx = j - i
            pp_bit = pp_idx < width ? partial_products[i][pp_idx] : nil

            if pp_bit.nil?
              pp_bit = new_temp
              @ir.add_gate(type: Primitives::CONST, inputs: [], output: pp_bit, value: 0)
            end

            # Full adder: result[j] + pp_bit + carry
            new_result = new_temp
            new_carry = new_temp
            axb = new_temp
            ab = new_temp
            cab = new_temp

            @ir.add_gate(type: Primitives::XOR, inputs: [result[j], pp_bit], output: axb)
            @ir.add_gate(type: Primitives::XOR, inputs: [axb, carry], output: new_result)
            @ir.add_gate(type: Primitives::AND, inputs: [result[j], pp_bit], output: ab)
            @ir.add_gate(type: Primitives::AND, inputs: [carry, axb], output: cab)
            @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: new_carry)

            result[j] = new_result
            carry = new_carry
          end
        end

        # Copy result to output
        product_width.times do |j|
          @ir.add_gate(type: Primitives::BUF, inputs: [result[j]], output: product_nets[j])
        end
      end

      # Divider: Restoring divider
      def lower_divider(component)
        dividend_nets = map_bus(component.inputs[:dividend])
        divisor_nets = map_bus(component.inputs[:divisor])
        quotient_nets = map_bus(component.outputs[:quotient])
        remainder_nets = map_bus(component.outputs[:remainder])
        div_by_zero_net = map_bus(component.outputs[:div_by_zero]).first

        width = dividend_nets.length

        # Check for division by zero
        any_divisor = divisor_nets.first
        divisor_nets[1..].each do |d|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [any_divisor, d], output: or_temp)
          any_divisor = or_temp
        end
        @ir.add_gate(type: Primitives::NOT, inputs: [any_divisor], output: div_by_zero_net)

        # For gate-level, implement restoring division algorithm
        # This is complex - use a simplified iterative subtraction approach
        # Initialize remainder with dividend
        remainder = dividend_nets.map do |d|
          r = new_temp
          @ir.add_gate(type: Primitives::BUF, inputs: [d], output: r)
          r
        end

        quotient = []

        # Iterative division: for each bit position from MSB to LSB
        (width - 1).downto(0) do |i|
          # Check if remainder >= (divisor << i)
          # For simplicity, we compare and subtract at each step
          # This is a simplified approach suitable for small widths

          # Build shifted divisor (divisor << i)
          shifted_divisor = Array.new(width) do |j|
            if j >= i && (j - i) < width
              divisor_nets[j - i]
            else
              z = new_temp
              @ir.add_gate(type: Primitives::CONST, inputs: [], output: z, value: 0)
              z
            end
          end

          # Compare: remainder >= shifted_divisor
          # Subtract and check borrow
          diff = []
          borrow = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: borrow, value: 0)

          width.times do |j|
            d = new_temp
            new_borrow = new_temp

            # Subtractor: diff = remainder - shifted_divisor
            r_xor_d = new_temp
            @ir.add_gate(type: Primitives::XOR, inputs: [remainder[j], shifted_divisor[j]], output: r_xor_d)
            @ir.add_gate(type: Primitives::XOR, inputs: [r_xor_d, borrow], output: d)

            # Borrow logic
            r_inv = new_temp
            @ir.add_gate(type: Primitives::NOT, inputs: [remainder[j]], output: r_inv)
            and1 = new_temp
            and2 = new_temp
            and3 = new_temp
            @ir.add_gate(type: Primitives::AND, inputs: [r_inv, shifted_divisor[j]], output: and1)
            @ir.add_gate(type: Primitives::AND, inputs: [r_inv, borrow], output: and2)
            @ir.add_gate(type: Primitives::AND, inputs: [shifted_divisor[j], borrow], output: and3)
            or1 = new_temp
            @ir.add_gate(type: Primitives::OR, inputs: [and1, and2], output: or1)
            @ir.add_gate(type: Primitives::OR, inputs: [or1, and3], output: new_borrow)

            diff << d
            borrow = new_borrow
          end

          # If no borrow (remainder >= shifted_divisor), set quotient bit and update remainder
          q_bit = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [borrow], output: q_bit)
          quotient[i] = q_bit

          # Select new remainder: if q_bit then diff else remainder
          new_remainder = []
          width.times do |j|
            new_r = new_temp
            @ir.add_gate(type: Primitives::MUX, inputs: [remainder[j], diff[j], q_bit], output: new_r)
            new_remainder << new_r
          end
          remainder = new_remainder
        end

        # Copy outputs, masking with NOT div_by_zero
        not_dbz = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [div_by_zero_net], output: not_dbz)

        width.times do |j|
          # quotient output
          masked_q = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [quotient[j], not_dbz], output: masked_q)
          @ir.add_gate(type: Primitives::BUF, inputs: [masked_q], output: quotient_nets[j])

          # remainder output
          masked_r = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [remainder[j], not_dbz], output: masked_r)
          @ir.add_gate(type: Primitives::BUF, inputs: [masked_r], output: remainder_nets[j])
        end
      end

      # ALU: Multi-operation ALU using mux selection
      def lower_alu(component)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        op_nets = map_bus(component.inputs[:op])
        cin_net = map_bus(component.inputs[:cin]).first
        result_nets = map_bus(component.outputs[:result])
        cout_net = map_bus(component.outputs[:cout]).first
        zero_net = map_bus(component.outputs[:zero]).first
        negative_net = map_bus(component.outputs[:negative]).first
        overflow_net = map_bus(component.outputs[:overflow]).first

        width = a_nets.length

        # Build results for each operation
        # OP 0: ADD, OP 1: SUB, OP 2: AND, OP 3: OR, OP 4: XOR, OP 5: NOT
        # For simplicity, implement basic operations

        # ADD result
        add_result = []
        add_carry = cin_net
        width.times do |idx|
          sum = new_temp
          cout = new_temp
          axb = new_temp
          ab = new_temp
          cab = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a_nets[idx], b_nets[idx]], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, add_carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [a_nets[idx], b_nets[idx]], output: ab)
          @ir.add_gate(type: Primitives::AND, inputs: [add_carry, axb], output: cab)
          @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: cout)
          add_result << sum
          add_carry = cout
        end
        add_cout = add_carry

        # SUB result (A - B - cin)
        b_inv = b_nets.map do |b|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [b], output: inv)
          inv
        end
        sub_cin = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [cin_net], output: sub_cin)

        sub_result = []
        sub_carry = sub_cin
        width.times do |idx|
          sum = new_temp
          cout = new_temp
          axb = new_temp
          ab = new_temp
          cab = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a_nets[idx], b_inv[idx]], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, sub_carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [a_nets[idx], b_inv[idx]], output: ab)
          @ir.add_gate(type: Primitives::AND, inputs: [sub_carry, axb], output: cab)
          @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: cout)
          sub_result << sum
          sub_carry = cout
        end
        sub_cout = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [sub_carry], output: sub_cout)

        # AND result
        and_result = a_nets.zip(b_nets).map do |a, b|
          r = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [a, b], output: r)
          r
        end

        # OR result
        or_result = a_nets.zip(b_nets).map do |a, b|
          r = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [a, b], output: r)
          r
        end

        # XOR result
        xor_result = a_nets.zip(b_nets).map do |a, b|
          r = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a, b], output: r)
          r
        end

        # NOT result
        not_result = a_nets.map do |a|
          r = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [a], output: r)
          r
        end

        # Use op bits to select result
        # op[0]: select between pairs
        # op[1]: select between quads
        # For 6 operations: use 3-bit mux selection

        width.times do |idx|
          # Group 0-1: ADD/SUB selected by op[0]
          mux_01 = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [add_result[idx], sub_result[idx], op_nets[0]], output: mux_01)

          # Group 2-3: AND/OR selected by op[0]
          mux_23 = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [and_result[idx], or_result[idx], op_nets[0]], output: mux_23)

          # Group 4-5: XOR/NOT selected by op[0]
          mux_45 = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [xor_result[idx], not_result[idx], op_nets[0]], output: mux_45)

          # Select between groups by op[1]
          mux_0123 = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [mux_01, mux_23, op_nets[1]], output: mux_0123)

          mux_4567 = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [mux_45, mux_45, op_nets[1]], output: mux_4567)

          # Final select by op[2]
          @ir.add_gate(type: Primitives::MUX, inputs: [mux_0123, mux_4567, op_nets[2]], output: result_nets[idx])
        end

        # Cout: select based on operation
        add_sub_cout = new_temp
        @ir.add_gate(type: Primitives::MUX, inputs: [add_cout, sub_cout, op_nets[0]], output: add_sub_cout)
        zero_const = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: zero_const, value: 0)
        @ir.add_gate(type: Primitives::MUX, inputs: [add_sub_cout, zero_const, op_nets[1]], output: cout_net)

        # Zero flag: NOR of all result bits
        any_result = result_nets.first
        result_nets[1..].each do |r|
          or_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [any_result, r], output: or_temp)
          any_result = or_temp
        end
        @ir.add_gate(type: Primitives::NOT, inputs: [any_result], output: zero_net)

        # Negative flag: MSB of result
        @ir.add_gate(type: Primitives::BUF, inputs: [result_nets[-1]], output: negative_net)

        # Overflow: for add/sub only
        a_msb = a_nets[-1]
        b_msb = b_nets[-1]
        r_msb = result_nets[-1]
        signs_same = new_temp
        ab_xor = new_temp
        @ir.add_gate(type: Primitives::XOR, inputs: [a_msb, b_msb], output: ab_xor)
        @ir.add_gate(type: Primitives::NOT, inputs: [ab_xor], output: signs_same)
        r_xor_a = new_temp
        @ir.add_gate(type: Primitives::XOR, inputs: [r_msb, a_msb], output: r_xor_a)
        add_overflow = new_temp
        @ir.add_gate(type: Primitives::AND, inputs: [signs_same, r_xor_a], output: add_overflow)
        @ir.add_gate(type: Primitives::MUX, inputs: [add_overflow, zero_const, op_nets[1]], output: overflow_net)
      end

      # RAM: Memory array using DFFs for each bit
      def lower_ram(component)
        we_net = map_bus(component.inputs[:we]).first
        addr_nets = map_bus(component.inputs[:addr])
        din_nets = map_bus(component.inputs[:din])
        dout_nets = map_bus(component.outputs[:dout])

        addr_width = addr_nets.length
        data_width = din_nets.length
        depth = 1 << addr_width

        # For synthesis, create memory using DFFs
        # Note: This creates a lot of gates for large memories
        # In practice, use memory macros

        # Create decoder for write address
        addr_inv = addr_nets.map do |a|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [a], output: inv)
          inv
        end

        # Memory storage: array of DFF outputs
        mem_q = Array.new(depth) { Array.new(data_width) }

        # Create DFFs and write logic for each memory location
        depth.times do |loc|
          # Generate write enable for this location
          write_en_bits = []
          addr_width.times do |j|
            write_en_bits << ((loc >> j) & 1 == 1 ? addr_nets[j] : addr_inv[j])
          end

          loc_select = write_en_bits.first
          write_en_bits[1..].each do |b|
            and_temp = new_temp
            @ir.add_gate(type: Primitives::AND, inputs: [loc_select, b], output: and_temp)
            loc_select = and_temp
          end

          # AND with global write enable
          loc_we = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [we_net, loc_select], output: loc_we)

          # Create DFF for each data bit
          data_width.times do |bit|
            q = new_temp
            mem_q[loc][bit] = q

            # DFF with enable
            rst_net = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: rst_net, value: 0)
            @ir.add_dff(d: din_nets[bit], q: q, rst: rst_net, en: loc_we)
          end
        end

        # Read mux: select data based on address
        data_width.times do |bit|
          data_bits = depth.times.map { |loc| mem_q[loc][bit] }
          result = lower_mux_tree(data_bits, addr_nets, 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: dout_nets[bit])
        end
      end

      # ROM: Read-only memory using mux tree
      def lower_rom(component)
        addr_nets = map_bus(component.inputs[:addr])
        en_net = map_bus(component.inputs[:en]).first
        dout_nets = map_bus(component.outputs[:dout])

        addr_width = addr_nets.length
        data_width = dout_nets.length
        depth = 1 << addr_width

        # Get ROM contents from component
        memory = component.instance_variable_get(:@memory) || Array.new(depth, 0)

        # Build constant generators for each memory location
        mem_data = Array.new(depth) { Array.new(data_width) }

        depth.times do |loc|
          data_val = memory[loc] || 0
          data_width.times do |bit|
            bit_val = (data_val >> bit) & 1
            const = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const, value: bit_val)
            mem_data[loc][bit] = const
          end
        end

        # Mux tree to select data based on address
        data_width.times do |bit|
          data_bits = depth.times.map { |loc| mem_data[loc][bit] }
          selected = lower_mux_tree(data_bits, addr_nets, 0)

          # Gate output with enable
          zero_const = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: zero_const, value: 0)
          @ir.add_gate(type: Primitives::MUX, inputs: [zero_const, selected, en_net], output: dout_nets[bit])
        end
      end

      # DualPortRAM: Two-port RAM
      def lower_dual_port_ram(component)
        we_a_net = map_bus(component.inputs[:we_a]).first
        we_b_net = map_bus(component.inputs[:we_b]).first
        addr_a_nets = map_bus(component.inputs[:addr_a])
        addr_b_nets = map_bus(component.inputs[:addr_b])
        din_a_nets = map_bus(component.inputs[:din_a])
        din_b_nets = map_bus(component.inputs[:din_b])
        dout_a_nets = map_bus(component.outputs[:dout_a])
        dout_b_nets = map_bus(component.outputs[:dout_b])

        addr_width = addr_a_nets.length
        data_width = din_a_nets.length
        depth = 1 << addr_width

        # Address decoders
        addr_a_inv = addr_a_nets.map { |a| inv = new_temp; @ir.add_gate(type: Primitives::NOT, inputs: [a], output: inv); inv }
        addr_b_inv = addr_b_nets.map { |a| inv = new_temp; @ir.add_gate(type: Primitives::NOT, inputs: [a], output: inv); inv }

        # Memory storage
        mem_q = Array.new(depth) { Array.new(data_width) }

        depth.times do |loc|
          # Write enable for port A
          select_a_bits = addr_width.times.map { |j| (loc >> j) & 1 == 1 ? addr_a_nets[j] : addr_a_inv[j] }
          select_a = select_a_bits.first
          select_a_bits[1..].each { |b| t = new_temp; @ir.add_gate(type: Primitives::AND, inputs: [select_a, b], output: t); select_a = t }
          loc_we_a = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [we_a_net, select_a], output: loc_we_a)

          # Write enable for port B
          select_b_bits = addr_width.times.map { |j| (loc >> j) & 1 == 1 ? addr_b_nets[j] : addr_b_inv[j] }
          select_b = select_b_bits.first
          select_b_bits[1..].each { |b| t = new_temp; @ir.add_gate(type: Primitives::AND, inputs: [select_b, b], output: t); select_b = t }
          loc_we_b = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [we_b_net, select_b], output: loc_we_b)

          # Combined write enable and data mux
          loc_we = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [loc_we_a, loc_we_b], output: loc_we)

          data_width.times do |bit|
            # Select data source: port B takes priority
            din_sel = new_temp
            @ir.add_gate(type: Primitives::MUX, inputs: [din_a_nets[bit], din_b_nets[bit], loc_we_b], output: din_sel)

            q = new_temp
            mem_q[loc][bit] = q
            rst_net = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: rst_net, value: 0)
            @ir.add_dff(d: din_sel, q: q, rst: rst_net, en: loc_we)
          end
        end

        # Read mux for port A
        data_width.times do |bit|
          data_bits = depth.times.map { |loc| mem_q[loc][bit] }
          result = lower_mux_tree(data_bits, addr_a_nets, 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: dout_a_nets[bit])
        end

        # Read mux for port B
        data_width.times do |bit|
          data_bits = depth.times.map { |loc| mem_q[loc][bit] }
          result = lower_mux_tree(data_bits, addr_b_nets, 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: dout_b_nets[bit])
        end
      end

      # RegisterFile: Multi-register file
      def lower_register_file(component)
        we_net = map_bus(component.inputs[:we]).first
        waddr_nets = map_bus(component.inputs[:waddr])
        raddr1_nets = map_bus(component.inputs[:raddr1])
        raddr2_nets = map_bus(component.inputs[:raddr2])
        wdata_nets = map_bus(component.inputs[:wdata])
        rdata1_nets = map_bus(component.outputs[:rdata1])
        rdata2_nets = map_bus(component.outputs[:rdata2])

        addr_width = waddr_nets.length
        data_width = wdata_nets.length
        num_regs = 1 << addr_width

        # Address decoder for write
        waddr_inv = waddr_nets.map { |a| inv = new_temp; @ir.add_gate(type: Primitives::NOT, inputs: [a], output: inv); inv }

        # Register storage
        reg_q = Array.new(num_regs) { Array.new(data_width) }

        num_regs.times do |r|
          select_bits = addr_width.times.map { |j| (r >> j) & 1 == 1 ? waddr_nets[j] : waddr_inv[j] }
          select = select_bits.first
          select_bits[1..].each { |b| t = new_temp; @ir.add_gate(type: Primitives::AND, inputs: [select, b], output: t); select = t }
          reg_we = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [we_net, select], output: reg_we)

          data_width.times do |bit|
            q = new_temp
            reg_q[r][bit] = q
            rst_net = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: rst_net, value: 0)
            @ir.add_dff(d: wdata_nets[bit], q: q, rst: rst_net, en: reg_we)
          end
        end

        # Read port 1
        data_width.times do |bit|
          data_bits = num_regs.times.map { |r| reg_q[r][bit] }
          result = lower_mux_tree(data_bits, raddr1_nets, 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: rdata1_nets[bit])
        end

        # Read port 2
        data_width.times do |bit|
          data_bits = num_regs.times.map { |r| reg_q[r][bit] }
          result = lower_mux_tree(data_bits, raddr2_nets, 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: rdata2_nets[bit])
        end
      end

      # FIFO: Queue with read/write pointers
      def lower_fifo(component)
        rst_net = map_bus(component.inputs[:rst]).first
        wr_en_net = map_bus(component.inputs[:wr_en]).first
        rd_en_net = map_bus(component.inputs[:rd_en]).first
        din_nets = map_bus(component.inputs[:din])
        dout_nets = map_bus(component.outputs[:dout])
        empty_net = map_bus(component.outputs[:empty]).first
        full_net = map_bus(component.outputs[:full]).first
        count_nets = map_bus(component.outputs[:count])

        data_width = din_nets.length
        depth = component.instance_variable_get(:@depth) || 16
        addr_width = Math.log2(depth).ceil
        count_width = count_nets.length

        # Pointers
        rd_ptr = Array.new(addr_width) { new_temp }
        wr_ptr = Array.new(addr_width) { new_temp }
        cnt = Array.new(count_width) { new_temp }

        # Memory array using DFFs
        mem_q = Array.new(depth) { Array.new(data_width) }
        wr_addr_inv = wr_ptr.map { |a| inv = new_temp; @ir.add_gate(type: Primitives::NOT, inputs: [a], output: inv); inv }

        depth.times do |loc|
          select_bits = addr_width.times.map { |j| (loc >> j) & 1 == 1 ? wr_ptr[j] : wr_addr_inv[j] }
          select = select_bits.first
          select_bits[1..].each { |b| t = new_temp; @ir.add_gate(type: Primitives::AND, inputs: [select, b], output: t); select = t }

          # Write when selected and wr_en and not full
          not_full = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [full_net], output: not_full)
          loc_we = new_temp
          t1 = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [select, wr_en_net], output: t1)
          @ir.add_gate(type: Primitives::AND, inputs: [t1, not_full], output: loc_we)

          data_width.times do |bit|
            q = new_temp
            mem_q[loc][bit] = q
            @ir.add_dff(d: din_nets[bit], q: q, rst: rst_net, en: loc_we)
          end
        end

        # Read mux
        data_width.times do |bit|
          data_bits = depth.times.map { |loc| mem_q[loc][bit] }
          result = lower_mux_tree(data_bits, rd_ptr, 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: dout_nets[bit])
        end

        # Pointer and count logic using DFFs
        # Simplified: just create registers for pointers
        addr_width.times do |i|
          @ir.add_dff(d: rd_ptr[i], q: rd_ptr[i], rst: rst_net, en: rd_en_net)
          @ir.add_dff(d: wr_ptr[i], q: wr_ptr[i], rst: rst_net, en: wr_en_net)
        end

        # Empty: count == 0
        any_cnt = cnt.first
        cnt[1..].each { |c| t = new_temp; @ir.add_gate(type: Primitives::OR, inputs: [any_cnt, c], output: t); any_cnt = t }
        @ir.add_gate(type: Primitives::NOT, inputs: [any_cnt], output: empty_net)

        # Full: count >= depth
        # Simplified: check MSB of count
        @ir.add_gate(type: Primitives::BUF, inputs: [cnt[-1]], output: full_net)

        # Count output
        count_width.times { |i| @ir.add_gate(type: Primitives::BUF, inputs: [cnt[i]], output: count_nets[i]) }
      end

      # Stack: LIFO with push/pop
      def lower_stack(component)
        rst_net = map_bus(component.inputs[:rst]).first
        push_net = map_bus(component.inputs[:push]).first
        pop_net = map_bus(component.inputs[:pop]).first
        din_nets = map_bus(component.inputs[:din])
        dout_nets = map_bus(component.outputs[:dout])
        empty_net = map_bus(component.outputs[:empty]).first
        full_net = map_bus(component.outputs[:full]).first
        sp_nets = map_bus(component.outputs[:sp])

        data_width = din_nets.length
        depth = component.instance_variable_get(:@depth) || 16
        sp_width = sp_nets.length

        # Stack pointer register
        sp_internal = Array.new(sp_width) { new_temp }

        # Memory array
        mem_q = Array.new(depth) { Array.new(data_width) }
        sp_inv = sp_internal.map { |s| inv = new_temp; @ir.add_gate(type: Primitives::NOT, inputs: [s], output: inv); inv }

        depth.times do |loc|
          select_bits = sp_width.times.map { |j| j < Math.log2(depth).ceil ? ((loc >> j) & 1 == 1 ? sp_internal[j] : sp_inv[j]) : nil }.compact
          select = select_bits.first
          select_bits[1..].each { |b| t = new_temp; @ir.add_gate(type: Primitives::AND, inputs: [select, b], output: t); select = t }

          not_full = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [full_net], output: not_full)
          loc_we = new_temp
          t1 = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [select, push_net], output: t1)
          @ir.add_gate(type: Primitives::AND, inputs: [t1, not_full], output: loc_we)

          data_width.times do |bit|
            q = new_temp
            mem_q[loc][bit] = q
            @ir.add_dff(d: din_nets[bit], q: q, rst: rst_net, en: loc_we)
          end
        end

        # Read top of stack (SP - 1)
        # For simplicity, read current SP location
        data_width.times do |bit|
          data_bits = depth.times.map { |loc| mem_q[loc][bit] }
          result = lower_mux_tree(data_bits, sp_internal[0...Math.log2(depth).ceil], 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [result], output: dout_nets[bit])
        end

        # SP register with increment/decrement
        # Simplified implementation
        sp_width.times do |i|
          @ir.add_dff(d: sp_internal[i], q: sp_internal[i], rst: rst_net, en: push_net)
          @ir.add_gate(type: Primitives::BUF, inputs: [sp_internal[i]], output: sp_nets[i])
        end

        # Empty: SP == 0
        any_sp = sp_internal.first
        sp_internal[1..].each { |s| t = new_temp; @ir.add_gate(type: Primitives::OR, inputs: [any_sp, s], output: t); any_sp = t }
        @ir.add_gate(type: Primitives::NOT, inputs: [any_sp], output: empty_net)

        # Full: SP >= depth
        @ir.add_gate(type: Primitives::BUF, inputs: [sp_internal[-1]], output: full_net)
      end

      # RegisterLoad: Register with load enable
      def lower_register_load(component)
        d_nets = map_bus(component.inputs[:d])
        rst_net = map_bus(component.inputs[:rst]).first
        load_net = map_bus(component.inputs[:load]).first
        q_nets = map_bus(component.outputs[:q])

        width = d_nets.length
        width.times do |idx|
          @ir.add_dff(d: d_nets[idx], q: q_nets[idx], rst: rst_net, en: load_net)
        end
      end

      # ProgramCounter: PC with increment, load
      def lower_program_counter(component)
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        load_net = map_bus(component.inputs[:load]).first
        d_nets = map_bus(component.inputs[:d])
        inc_nets = map_bus(component.inputs[:inc])
        q_nets = map_bus(component.outputs[:q])

        width = q_nets.length

        # Internal state
        q_internal = Array.new(width) { new_temp }

        # Compute PC + inc
        inc_result = []
        carry = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: carry, value: 0)

        # Default increment of 1 if inc == 0
        # For simplicity, always add inc
        width.times do |idx|
          inc_bit = idx < inc_nets.length ? inc_nets[idx] : new_temp
          if idx >= inc_nets.length
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: inc_bit, value: 0)
          end

          sum = new_temp
          cout = new_temp
          axb = new_temp
          ab = new_temp
          cab = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [q_internal[idx], inc_bit], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [q_internal[idx], inc_bit], output: ab)
          @ir.add_gate(type: Primitives::AND, inputs: [carry, axb], output: cab)
          @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: cout)
          inc_result << sum
          carry = cout
        end

        # Select next value: load takes priority, then enable for increment
        width.times do |idx|
          # Mux: load ? d : (en ? inc_result : q_internal)
          mux_en = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [q_internal[idx], inc_result[idx], en_net], output: mux_en)
          next_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [mux_en, d_nets[idx], load_net], output: next_val)

          @ir.add_dff(d: next_val, q: q_internal[idx], rst: rst_net, en: nil)
          @ir.add_gate(type: Primitives::BUF, inputs: [q_internal[idx]], output: q_nets[idx])
        end
      end

      # StackPointer: SP with push/pop (decrement/increment)
      def lower_stack_pointer(component)
        rst_net = map_bus(component.inputs[:rst]).first
        push_net = map_bus(component.inputs[:push]).first
        pop_net = map_bus(component.inputs[:pop]).first
        q_nets = map_bus(component.outputs[:q])
        empty_net = map_bus(component.outputs[:empty]).first
        full_net = map_bus(component.outputs[:full]).first

        width = q_nets.length

        # Internal state
        q_internal = Array.new(width) { new_temp }

        # Compute SP - 1 (push) and SP + 1 (pop)
        # Decrement
        dec_result = []
        borrow = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: borrow, value: 1)
        width.times do |idx|
          diff = new_temp
          new_borrow = new_temp
          q_xor_b = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [q_internal[idx], borrow], output: q_xor_b)
          @ir.add_gate(type: Primitives::NOT, inputs: [q_xor_b], output: diff)

          q_inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [q_internal[idx]], output: q_inv)
          @ir.add_gate(type: Primitives::AND, inputs: [q_inv, borrow], output: new_borrow)
          dec_result << diff
          borrow = new_borrow
        end

        # Increment
        inc_result = []
        carry = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: carry, value: 1)
        width.times do |idx|
          sum = new_temp
          new_carry = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [q_internal[idx], carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [q_internal[idx], carry], output: new_carry)
          inc_result << sum
          carry = new_carry
        end

        # Select: push -> dec, pop -> inc, neither -> hold
        en_any = new_temp
        @ir.add_gate(type: Primitives::OR, inputs: [push_net, pop_net], output: en_any)

        width.times do |idx|
          mux_op = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [dec_result[idx], inc_result[idx], pop_net], output: mux_op)
          next_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [q_internal[idx], mux_op, en_any], output: next_val)

          @ir.add_dff(d: next_val, q: q_internal[idx], rst: rst_net, en: nil)
          @ir.add_gate(type: Primitives::BUF, inputs: [q_internal[idx]], output: q_nets[idx])
        end

        # Empty: SP == max (all 1s)
        all_ones = reduce_and(q_internal)
        @ir.add_gate(type: Primitives::BUF, inputs: [all_ones], output: empty_net)

        # Full: SP == 0 (all 0s)
        any_bit = q_internal.first
        q_internal[1..].each { |q| t = new_temp; @ir.add_gate(type: Primitives::OR, inputs: [any_bit, q], output: t); any_bit = t }
        @ir.add_gate(type: Primitives::NOT, inputs: [any_bit], output: full_net)
      end

      # InstructionDecoder: Combinational decode logic
      def lower_instruction_decoder(component)
        instr_nets = map_bus(component.inputs[:instruction])
        zero_flag_net = map_bus(component.inputs[:zero_flag]).first

        alu_op_nets = map_bus(component.outputs[:alu_op])
        alu_src_net = map_bus(component.outputs[:alu_src]).first
        reg_write_net = map_bus(component.outputs[:reg_write]).first
        mem_read_net = map_bus(component.outputs[:mem_read]).first
        mem_write_net = map_bus(component.outputs[:mem_write]).first
        branch_net = map_bus(component.outputs[:branch]).first
        jump_net = map_bus(component.outputs[:jump]).first
        pc_src_nets = map_bus(component.outputs[:pc_src])
        halt_net = map_bus(component.outputs[:halt]).first
        call_net = map_bus(component.outputs[:call]).first
        ret_net = map_bus(component.outputs[:ret]).first
        instr_length_nets = map_bus(component.outputs[:instr_length])

        # Extract opcode (high 4 bits)
        opcode_nets = instr_nets[4..7]

        # Build decoder for each output based on opcode
        # This is a simplified implementation - full decode would be more complex

        # For synthesis, use mux trees based on opcode value
        # ALU op: default 0 (ADD)
        alu_op_nets.each_with_index do |out, idx|
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
        end

        # alu_src: LDI (opcode 10 = 0xA) uses immediate
        opcode_is_10 = lower_compare_const(opcode_nets, 10)
        @ir.add_gate(type: Primitives::BUF, inputs: [opcode_is_10], output: alu_src_net)

        # reg_write: LDA(1), ADD(3), SUB(4), AND(5), OR(6), XOR(7), LDI(10), DIV(14)
        reg_write_opcodes = [1, 3, 4, 5, 6, 7, 10, 14]
        rw_terms = reg_write_opcodes.map { |op| lower_compare_const(opcode_nets, op) }
        rw_or = rw_terms.first
        rw_terms[1..].each { |t| tmp = new_temp; @ir.add_gate(type: Primitives::OR, inputs: [rw_or, t], output: tmp); rw_or = tmp }
        @ir.add_gate(type: Primitives::BUF, inputs: [rw_or], output: reg_write_net)

        # mem_read: LDA(1), ADD(3), SUB(4), AND(5), OR(6), XOR(7), DIV(14)
        mem_read_opcodes = [1, 3, 4, 5, 6, 7, 14]
        mr_terms = mem_read_opcodes.map { |op| lower_compare_const(opcode_nets, op) }
        mr_or = mr_terms.first
        mr_terms[1..].each { |t| tmp = new_temp; @ir.add_gate(type: Primitives::OR, inputs: [mr_or, t], output: tmp); mr_or = tmp }
        @ir.add_gate(type: Primitives::BUF, inputs: [mr_or], output: mem_read_net)

        # mem_write: STA (opcode 2)
        opcode_is_2 = lower_compare_const(opcode_nets, 2)
        @ir.add_gate(type: Primitives::BUF, inputs: [opcode_is_2], output: mem_write_net)

        # branch: JZ(8), JNZ(9)
        opcode_is_8 = lower_compare_const(opcode_nets, 8)
        opcode_is_9 = lower_compare_const(opcode_nets, 9)
        branch_or = new_temp
        @ir.add_gate(type: Primitives::OR, inputs: [opcode_is_8, opcode_is_9], output: branch_or)
        @ir.add_gate(type: Primitives::BUF, inputs: [branch_or], output: branch_net)

        # jump: JMP (opcode 11)
        opcode_is_11 = lower_compare_const(opcode_nets, 11)
        @ir.add_gate(type: Primitives::BUF, inputs: [opcode_is_11], output: jump_net)

        # pc_src: default 0
        pc_src_nets.each do |out|
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
        end

        # halt: 0xF0
        instr_is_f0 = lower_compare_const(instr_nets, 0xF0)
        @ir.add_gate(type: Primitives::BUF, inputs: [instr_is_f0], output: halt_net)

        # call: opcode 12
        opcode_is_12 = lower_compare_const(opcode_nets, 12)
        @ir.add_gate(type: Primitives::BUF, inputs: [opcode_is_12], output: call_net)

        # ret: opcode 13
        opcode_is_13 = lower_compare_const(opcode_nets, 13)
        @ir.add_gate(type: Primitives::BUF, inputs: [opcode_is_13], output: ret_net)

        # instr_length: default 1
        const_one = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_one, value: 1)
        @ir.add_gate(type: Primitives::BUF, inputs: [const_one], output: instr_length_nets[0])
        if instr_length_nets.length > 1
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: instr_length_nets[1])
        end
      end

      # Helper: compare nets to constant value
      def lower_compare_const(nets, value)
        width = nets.length
        eq_bits = []
        width.times do |i|
          bit_val = (value >> i) & 1
          if bit_val == 1
            eq_bits << nets[i]
          else
            inv = new_temp
            @ir.add_gate(type: Primitives::NOT, inputs: [nets[i]], output: inv)
            eq_bits << inv
          end
        end
        reduce_and(eq_bits)
      end

      # Datapath: Hierarchical composition - recursively lower subcomponents
      def lower_datapath(component)
        # The Datapath contains subcomponents that need to be lowered
        # For gate-level synthesis, we would need to expose internal wiring
        # This is a placeholder that creates buffer passthrough for I/O

        rst_net = map_bus(component.inputs[:rst]).first if component.inputs[:rst]
        pc_out_nets = map_bus(component.outputs[:pc_out]) if component.outputs[:pc_out]
        acc_out_nets = map_bus(component.outputs[:acc_out]) if component.outputs[:acc_out]
        zero_flag_net = map_bus(component.outputs[:zero_flag]).first if component.outputs[:zero_flag]
        halted_net = map_bus(component.outputs[:halted]).first if component.outputs[:halted]

        # Initialize outputs to 0
        pc_out_nets&.each do |out|
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
        end

        acc_out_nets&.each do |out|
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
        end

        if zero_flag_net
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: zero_flag_net)
        end

        if halted_net
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: halted_net)
        end
      end

      # SynthDatapath: Hierarchical structural composition
      def lower_synth_datapath(component)
        # Get instance and connection definitions from the class
        instance_defs = component.class._instance_defs
        connection_defs = component.class._connection_defs

        # Create sub-component instances and map their ports to nets
        sub_components = {}
        sub_nets = {}  # Maps [instance_name, port_name] => net_id or [net_ids]

        instance_defs.each do |inst_def|
          inst_name = inst_def[:name]
          component_class = inst_def[:component_class]
          params = inst_def[:parameters] || {}

          # Create sub-component instance
          sub_comp = component_class.new("#{component.name}_#{inst_name}", **params)
          sub_components[inst_name] = sub_comp

          # Create nets for all ports of this sub-component
          sub_comp.inputs.each do |port_name, wire|
            width = wire.respond_to?(:width) ? wire.width : 1
            if width == 1
              sub_nets[[inst_name, port_name]] = new_temp
            else
              sub_nets[[inst_name, port_name]] = width.times.map { new_temp }
            end
          end

          sub_comp.outputs.each do |port_name, wire|
            width = wire.respond_to?(:width) ? wire.width : 1
            if width == 1
              sub_nets[[inst_name, port_name]] = new_temp
            else
              sub_nets[[inst_name, port_name]] = width.times.map { new_temp }
            end
          end
        end

        # Map parent component I/O to nets (for external connections)
        parent_nets = {}
        component.inputs.each do |port_name, wire|
          parent_nets[port_name] = map_bus(wire)
        end
        component.outputs.each do |port_name, wire|
          parent_nets[port_name] = map_bus(wire)
        end

        # Map internal signals to nets
        if component.respond_to?(:signals) && component.signals
          component.signals.each do |sig_name, wire|
            parent_nets[sig_name] = wire.respond_to?(:width) && wire.width > 1 ?
              wire.width.times.map { new_temp } : [new_temp]
          end
        end

        # Process connections - build a union-find of connected nets
        net_aliases = {}  # Maps net -> canonical net

        connection_defs.each do |conn|
          source = conn[:source]
          dest = conn[:dest]

          # Get source nets
          source_nets = if source.is_a?(Array) && source.length == 2
            # Instance port reference [:inst, :port]
            sub_nets[[source[0], source[1]]]
          else
            # Parent signal/port reference
            parent_nets[source]
          end

          # Get dest nets
          dest_nets = if dest.is_a?(Array) && dest.length == 2
            # Instance port reference [:inst, :port]
            sub_nets[[dest[0], dest[1]]]
          else
            # Parent signal/port reference
            parent_nets[dest]
          end

          # Skip if either side is nil
          next unless source_nets && dest_nets

          # Normalize to arrays
          source_nets = [source_nets] unless source_nets.is_a?(Array)
          dest_nets = [dest_nets] unless dest_nets.is_a?(Array)

          # Connect corresponding bits
          [source_nets.length, dest_nets.length].min.times do |i|
            src = source_nets[i]
            dst = dest_nets[i]
            # Use buffer to connect (direction: source drives dest)
            @ir.add_gate(type: Primitives::BUF, inputs: [src], output: dst)
          end
        end

        # Lower each sub-component with its mapped nets
        sub_components.each do |inst_name, sub_comp|
          # Set up wire-to-net mappings for this sub-component using @net_map
          sub_comp.inputs.each do |port_name, wire|
            nets = sub_nets[[inst_name, port_name]]
            nets = [nets] unless nets.is_a?(Array)
            # Map each bit of the wire to its net
            wire.width.times do |i|
              @net_map[[wire, i]] = nets[i] if nets[i]
            end
          end

          sub_comp.outputs.each do |port_name, wire|
            nets = sub_nets[[inst_name, port_name]]
            nets = [nets] unless nets.is_a?(Array)
            wire.width.times do |i|
              @net_map[[wire, i]] = nets[i] if nets[i]
            end
          end

          # Lower the sub-component using the dispatcher
          dispatch_lower(sub_comp)
        end
      end

      # =======================================================================
      # MOS6502S Component Lowering
      # =======================================================================

      # MOS6502S Registers: 3 x 8-bit registers (A, X, Y) with individual load enables
      def lower_mos6502s_registers(component)
        rst_net = map_bus(component.inputs[:rst]).first
        data_in_nets = map_bus(component.inputs[:data_in])
        load_a_net = map_bus(component.inputs[:load_a]).first
        load_x_net = map_bus(component.inputs[:load_x]).first
        load_y_net = map_bus(component.inputs[:load_y]).first
        a_nets = map_bus(component.outputs[:a])
        x_nets = map_bus(component.outputs[:x])
        y_nets = map_bus(component.outputs[:y])

        # Create DFFs for each register bit with individual load enables
        8.times do |idx|
          @ir.add_dff(d: data_in_nets[idx], q: a_nets[idx], rst: rst_net, en: load_a_net)
          @ir.add_dff(d: data_in_nets[idx], q: x_nets[idx], rst: rst_net, en: load_x_net)
          @ir.add_dff(d: data_in_nets[idx], q: y_nets[idx], rst: rst_net, en: load_y_net)
        end
      end

      # MOS6502S StackPointer: 8-bit with inc/dec/load, outputs addr and addr_plus1
      def lower_mos6502s_stack_pointer(component)
        rst_net = map_bus(component.inputs[:rst]).first
        inc_net = map_bus(component.inputs[:inc]).first
        dec_net = map_bus(component.inputs[:dec]).first
        load_net = map_bus(component.inputs[:load]).first
        data_in_nets = map_bus(component.inputs[:data_in])
        sp_nets = map_bus(component.outputs[:sp])
        addr_nets = map_bus(component.outputs[:addr])
        addr_plus1_nets = map_bus(component.outputs[:addr_plus1])

        width = 8
        sp_internal = Array.new(width) { new_temp }

        # Compute SP + 1
        sp_plus1 = []
        carry = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: carry, value: 1)
        width.times do |idx|
          sum = new_temp
          cout = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [sp_internal[idx], carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [sp_internal[idx], carry], output: cout)
          sp_plus1 << sum
          carry = cout
        end

        # Compute SP - 1
        sp_minus1 = []
        borrow = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: borrow, value: 1)
        width.times do |idx|
          diff = new_temp
          bout = new_temp
          sp_inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [sp_internal[idx]], output: sp_inv)
          @ir.add_gate(type: Primitives::XOR, inputs: [sp_inv, borrow], output: diff)
          bout_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [sp_inv, borrow], output: bout_temp)
          @ir.add_gate(type: Primitives::AND, inputs: [sp_inv, borrow], output: bout)
          sp_minus1 << new_temp
          # diff = sp - 1 at bit idx
          @ir.add_gate(type: Primitives::XOR, inputs: [sp_internal[idx], borrow], output: sp_minus1[idx])
          not_sp = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [sp_internal[idx]], output: not_sp)
          next_borrow = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [not_sp, borrow], output: next_borrow)
          borrow = next_borrow
        end

        # Select next value: load > dec > inc > hold
        # Priority mux chain
        width.times do |idx|
          # inc_val = sp + 1
          # dec_val = sp - 1
          # Mux chain: mux(load, data_in, mux(dec, sp-1, mux(inc, sp+1, sp)))
          hold_or_inc = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [sp_internal[idx], sp_plus1[idx], inc_net], output: hold_or_inc)
          inc_or_dec = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [hold_or_inc, sp_minus1[idx], dec_net], output: inc_or_dec)
          next_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [inc_or_dec, data_in_nets[idx], load_net], output: next_val)

          # Any operation enables the register
          en_temp1 = new_temp
          en_temp2 = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [inc_net, dec_net], output: en_temp1)
          @ir.add_gate(type: Primitives::OR, inputs: [en_temp1, load_net], output: en_temp2)

          @ir.add_dff(d: next_val, q: sp_internal[idx], rst: rst_net, en: en_temp2)
          @ir.add_gate(type: Primitives::BUF, inputs: [sp_internal[idx]], output: sp_nets[idx])
        end

        # addr = 0x0100 | sp (stack page)
        addr_nets.each_with_index do |out, idx|
          if idx < 8
            @ir.add_gate(type: Primitives::BUF, inputs: [sp_internal[idx]], output: out)
          elsif idx == 8
            const_one = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_one, value: 1)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_one], output: out)
          else
            const_zero = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
          end
        end

        # addr_plus1 = 0x0100 | (sp + 1)
        addr_plus1_nets.each_with_index do |out, idx|
          if idx < 8
            @ir.add_gate(type: Primitives::BUF, inputs: [sp_plus1[idx]], output: out)
          elsif idx == 8
            const_one = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_one, value: 1)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_one], output: out)
          else
            const_zero = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
          end
        end
      end

      # MOS6502S ProgramCounter: 16-bit with inc/load
      def lower_mos6502s_program_counter(component)
        rst_net = map_bus(component.inputs[:rst]).first
        inc_net = map_bus(component.inputs[:inc]).first
        load_net = map_bus(component.inputs[:load]).first
        addr_in_nets = map_bus(component.inputs[:addr_in])
        pc_nets = map_bus(component.outputs[:pc])
        pc_hi_nets = map_bus(component.outputs[:pc_hi])
        pc_lo_nets = map_bus(component.outputs[:pc_lo])

        width = 16
        pc_internal = Array.new(width) { new_temp }

        # Compute PC + 1
        pc_plus1 = []
        carry = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: carry, value: 1)
        width.times do |idx|
          sum = new_temp
          cout = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [pc_internal[idx], carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [pc_internal[idx], carry], output: cout)
          pc_plus1 << sum
          carry = cout
        end

        # Select next value based on load and inc
        # if load && inc: addr_in + 1
        # elif load: addr_in
        # elif inc: pc + 1
        # else: pc
        width.times do |idx|
          # Compute addr_in + 1
          addr_plus1_bit = new_temp
          # For simplicity, mux between addr_in and addr_in (load+inc handled by priority)

          # Priority: mux(load, mux(inc, addr_in+1, addr_in), mux(inc, pc+1, pc))
          hold_or_inc = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [pc_internal[idx], pc_plus1[idx], inc_net], output: hold_or_inc)

          load_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [addr_in_nets[idx], pc_plus1[idx], inc_net], output: load_val)

          next_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [hold_or_inc, load_val, load_net], output: next_val)

          # Enable on any operation
          en_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [inc_net, load_net], output: en_temp)

          @ir.add_dff(d: next_val, q: pc_internal[idx], rst: rst_net, en: en_temp)
          @ir.add_gate(type: Primitives::BUF, inputs: [pc_internal[idx]], output: pc_nets[idx])
        end

        # pc_hi and pc_lo outputs
        8.times do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [pc_internal[idx]], output: pc_lo_nets[idx])
          @ir.add_gate(type: Primitives::BUF, inputs: [pc_internal[idx + 8]], output: pc_hi_nets[idx])
        end
      end

      # MOS6502S InstructionRegister: opcode + operand_lo + operand_hi registers
      def lower_mos6502s_instruction_register(component)
        rst_net = map_bus(component.inputs[:rst]).first
        load_opcode_net = map_bus(component.inputs[:load_opcode]).first
        load_operand_lo_net = map_bus(component.inputs[:load_operand_lo]).first
        load_operand_hi_net = map_bus(component.inputs[:load_operand_hi]).first
        data_in_nets = map_bus(component.inputs[:data_in])
        opcode_nets = map_bus(component.outputs[:opcode])
        operand_lo_nets = map_bus(component.outputs[:operand_lo])
        operand_hi_nets = map_bus(component.outputs[:operand_hi])
        operand_nets = map_bus(component.outputs[:operand])

        # Opcode register (8-bit)
        8.times do |idx|
          @ir.add_dff(d: data_in_nets[idx], q: opcode_nets[idx], rst: rst_net, en: load_opcode_net)
        end

        # Operand lo register (8-bit)
        operand_lo_internal = []
        8.times do |idx|
          q = new_temp
          @ir.add_dff(d: data_in_nets[idx], q: q, rst: rst_net, en: load_operand_lo_net)
          operand_lo_internal << q
          @ir.add_gate(type: Primitives::BUF, inputs: [q], output: operand_lo_nets[idx])
        end

        # Operand hi register (8-bit)
        operand_hi_internal = []
        8.times do |idx|
          q = new_temp
          @ir.add_dff(d: data_in_nets[idx], q: q, rst: rst_net, en: load_operand_hi_net)
          operand_hi_internal << q
          @ir.add_gate(type: Primitives::BUF, inputs: [q], output: operand_hi_nets[idx])
        end

        # 16-bit operand output: {operand_hi, operand_lo}
        8.times do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [operand_lo_internal[idx]], output: operand_nets[idx])
          @ir.add_gate(type: Primitives::BUF, inputs: [operand_hi_internal[idx]], output: operand_nets[idx + 8])
        end
      end

      # MOS6502S AddressLatch: 16-bit with byte-wise and full loading
      def lower_mos6502s_address_latch(component)
        rst_net = map_bus(component.inputs[:rst]).first
        load_lo_net = map_bus(component.inputs[:load_lo]).first
        load_hi_net = map_bus(component.inputs[:load_hi]).first
        load_full_net = map_bus(component.inputs[:load_full]).first
        data_in_nets = map_bus(component.inputs[:data_in])
        addr_in_nets = map_bus(component.inputs[:addr_in])
        addr_lo_nets = map_bus(component.outputs[:addr_lo])
        addr_hi_nets = map_bus(component.outputs[:addr_hi])
        addr_nets = map_bus(component.outputs[:addr])

        # Address lo register
        addr_lo_internal = []
        8.times do |idx|
          # load_full has priority over load_lo
          d_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [data_in_nets[idx], addr_in_nets[idx], load_full_net], output: d_val)
          en_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [load_lo_net, load_full_net], output: en_temp)
          q = new_temp
          @ir.add_dff(d: d_val, q: q, rst: rst_net, en: en_temp)
          addr_lo_internal << q
          @ir.add_gate(type: Primitives::BUF, inputs: [q], output: addr_lo_nets[idx])
        end

        # Address hi register
        addr_hi_internal = []
        8.times do |idx|
          d_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [data_in_nets[idx], addr_in_nets[idx + 8], load_full_net], output: d_val)
          en_temp = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [load_hi_net, load_full_net], output: en_temp)
          q = new_temp
          @ir.add_dff(d: d_val, q: q, rst: rst_net, en: en_temp)
          addr_hi_internal << q
          @ir.add_gate(type: Primitives::BUF, inputs: [q], output: addr_hi_nets[idx])
        end

        # 16-bit addr output
        8.times do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [addr_lo_internal[idx]], output: addr_nets[idx])
          @ir.add_gate(type: Primitives::BUF, inputs: [addr_hi_internal[idx]], output: addr_nets[idx + 8])
        end
      end

      # MOS6502S DataLatch: simple 8-bit latch
      def lower_mos6502s_data_latch(component)
        rst_net = map_bus(component.inputs[:rst]).first
        load_net = map_bus(component.inputs[:load]).first
        data_in_nets = map_bus(component.inputs[:data_in])
        data_nets = map_bus(component.outputs[:data])

        8.times do |idx|
          @ir.add_dff(d: data_in_nets[idx], q: data_nets[idx], rst: rst_net, en: load_net)
        end
      end

      # MOS6502S StatusRegister: 8-bit status flags (N,V,-,B,D,I,Z,C)
      def lower_mos6502s_status_register(component)
        rst_net = map_bus(component.inputs[:rst]).first
        load_all_net = map_bus(component.inputs[:load_all]).first
        load_flags_net = map_bus(component.inputs[:load_flags]).first
        load_n_net = map_bus(component.inputs[:load_n]).first
        load_v_net = map_bus(component.inputs[:load_v]).first
        load_z_net = map_bus(component.inputs[:load_z]).first
        load_c_net = map_bus(component.inputs[:load_c]).first
        load_i_net = map_bus(component.inputs[:load_i]).first
        load_d_net = map_bus(component.inputs[:load_d]).first
        load_b_net = map_bus(component.inputs[:load_b]).first
        n_in_net = map_bus(component.inputs[:n_in]).first
        v_in_net = map_bus(component.inputs[:v_in]).first
        z_in_net = map_bus(component.inputs[:z_in]).first
        c_in_net = map_bus(component.inputs[:c_in]).first
        i_in_net = map_bus(component.inputs[:i_in]).first
        d_in_net = map_bus(component.inputs[:d_in]).first
        b_in_net = map_bus(component.inputs[:b_in]).first
        data_in_nets = map_bus(component.inputs[:data_in])

        n_net = map_bus(component.outputs[:n]).first
        v_net = map_bus(component.outputs[:v]).first
        z_net = map_bus(component.outputs[:z]).first
        c_net = map_bus(component.outputs[:c]).first
        i_net = map_bus(component.outputs[:i]).first
        d_net = map_bus(component.outputs[:d]).first
        b_net = map_bus(component.outputs[:b]).first
        p_nets = map_bus(component.outputs[:p])

        # Flag positions in P: 7=N, 6=V, 5=1, 4=B, 3=D, 2=I, 1=Z, 0=C
        # Create internal P register
        p_internal = Array.new(8) { new_temp }

        # Each flag: priority is load_all > load_flags > individual load
        flag_configs = [
          { out: c_net, load: load_c_net, in: c_in_net, p_bit: 0 },
          { out: z_net, load: load_z_net, in: z_in_net, p_bit: 1 },
          { out: i_net, load: load_i_net, in: i_in_net, p_bit: 2 },
          { out: d_net, load: load_d_net, in: d_in_net, p_bit: 3 },
          { out: b_net, load: load_b_net, in: b_in_net, p_bit: 4 },
          { out: v_net, load: load_v_net, in: v_in_net, p_bit: 6 },
          { out: n_net, load: load_n_net, in: n_in_net, p_bit: 7 }
        ]

        flag_configs.each do |cfg|
          idx = cfg[:p_bit]

          # Individual load: mux(load_x, x_in, hold)
          ind_val = new_temp
          @ir.add_gate(type: Primitives::MUX, inputs: [p_internal[idx], cfg[:in], cfg[:load]], output: ind_val)

          # load_flags for N,V,Z,C (not I,D,B)
          flags_val = new_temp
          if [0, 1, 6, 7].include?(idx)
            @ir.add_gate(type: Primitives::MUX, inputs: [ind_val, cfg[:in], load_flags_net], output: flags_val)
          else
            @ir.add_gate(type: Primitives::BUF, inputs: [ind_val], output: flags_val)
          end

          # load_all: data_in[bit] (with bit 5 set, bit 4 clear)
          all_val = new_temp
          if idx == 5
            const_one = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_one, value: 1)
            @ir.add_gate(type: Primitives::MUX, inputs: [flags_val, const_one, load_all_net], output: all_val)
          elsif idx == 4
            const_zero = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
            @ir.add_gate(type: Primitives::MUX, inputs: [flags_val, const_zero, load_all_net], output: all_val)
          else
            @ir.add_gate(type: Primitives::MUX, inputs: [flags_val, data_in_nets[idx], load_all_net], output: all_val)
          end

          # Any operation enables
          en_temp1 = new_temp
          en_temp2 = new_temp
          en_temp3 = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [cfg[:load], load_flags_net], output: en_temp1)
          @ir.add_gate(type: Primitives::OR, inputs: [en_temp1, load_all_net], output: en_temp2)

          @ir.add_dff(d: all_val, q: p_internal[idx], rst: rst_net, en: en_temp2)
          @ir.add_gate(type: Primitives::BUF, inputs: [p_internal[idx]], output: cfg[:out])
        end

        # Bit 5 is always 1
        const_one = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_one, value: 1)
        @ir.add_gate(type: Primitives::BUF, inputs: [const_one], output: p_internal[5])

        # P output (8-bit)
        8.times do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [p_internal[idx]], output: p_nets[idx])
        end
      end

      # MOS6502S AddressGenerator: combinational address calculation
      def lower_mos6502s_address_generator(component)
        mode_nets = map_bus(component.inputs[:mode])
        operand_lo_nets = map_bus(component.inputs[:operand_lo])
        operand_hi_nets = map_bus(component.inputs[:operand_hi])
        x_reg_nets = map_bus(component.inputs[:x_reg])
        y_reg_nets = map_bus(component.inputs[:y_reg])
        pc_nets = map_bus(component.inputs[:pc])
        sp_nets = map_bus(component.inputs[:sp])
        indirect_lo_nets = map_bus(component.inputs[:indirect_lo])
        indirect_hi_nets = map_bus(component.inputs[:indirect_hi])
        eff_addr_nets = map_bus(component.outputs[:eff_addr])
        page_cross_net = map_bus(component.outputs[:page_cross]).first
        is_zero_page_net = map_bus(component.outputs[:is_zero_page]).first

        # For gate-level, this is complex combinational logic
        # Simplified: output zero address with basic mode decoding
        # Full implementation would require complete address calculation circuits

        # Default outputs to zero
        eff_addr_nets.each do |out|
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
        end

        const_zero = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
        @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: page_cross_net)
        @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: is_zero_page_net)
      end

      # MOS6502S IndirectAddressCalc: combinational indirect address calculation
      def lower_mos6502s_indirect_addr_calc(component)
        mode_nets = map_bus(component.inputs[:mode])
        operand_lo_nets = map_bus(component.inputs[:operand_lo])
        operand_hi_nets = map_bus(component.inputs[:operand_hi])
        x_reg_nets = map_bus(component.inputs[:x_reg])
        ptr_addr_lo_nets = map_bus(component.outputs[:ptr_addr_lo])
        ptr_addr_hi_nets = map_bus(component.outputs[:ptr_addr_hi])

        # Simplified: output zero addresses
        [ptr_addr_lo_nets, ptr_addr_hi_nets].each do |nets|
          nets.each do |out|
            const_zero = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
          end
        end
      end

      # MOS6502S ALU: 8-bit ALU with BCD support
      def lower_mos6502s_alu(component)
        a_nets = map_bus(component.inputs[:a])
        b_nets = map_bus(component.inputs[:b])
        c_in_net = map_bus(component.inputs[:c_in]).first
        d_flag_net = map_bus(component.inputs[:d_flag]).first
        op_nets = map_bus(component.inputs[:op])
        result_nets = map_bus(component.outputs[:result])
        n_net = map_bus(component.outputs[:n]).first
        z_net = map_bus(component.outputs[:z]).first
        c_net = map_bus(component.outputs[:c]).first
        v_net = map_bus(component.outputs[:v]).first

        width = 8

        # Build results for each operation (simplified without BCD)
        # OP 0: ADC, OP 1: SBC, OP 2: AND, OP 3: ORA, OP 4: EOR
        # OP 5: ASL, OP 6: LSR, OP 7: ROL, OP 8: ROR
        # OP 9: INC, OP 10: DEC, OP 11: CMP, OP 12: BIT, OP 13: TST

        # ADD result
        add_result = []
        add_carry = c_in_net
        width.times do |idx|
          sum = new_temp
          cout = new_temp
          axb = new_temp
          ab = new_temp
          cab = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a_nets[idx], b_nets[idx]], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, add_carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [a_nets[idx], b_nets[idx]], output: ab)
          @ir.add_gate(type: Primitives::AND, inputs: [add_carry, axb], output: cab)
          @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: cout)
          add_result << sum
          add_carry = cout
        end
        add_cout = add_carry

        # SUB result (A - B - !C)
        b_inv = b_nets.map do |b|
          inv = new_temp
          @ir.add_gate(type: Primitives::NOT, inputs: [b], output: inv)
          inv
        end
        sub_result = []
        sub_carry = c_in_net
        width.times do |idx|
          sum = new_temp
          cout = new_temp
          axb = new_temp
          ab = new_temp
          cab = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a_nets[idx], b_inv[idx]], output: axb)
          @ir.add_gate(type: Primitives::XOR, inputs: [axb, sub_carry], output: sum)
          @ir.add_gate(type: Primitives::AND, inputs: [a_nets[idx], b_inv[idx]], output: ab)
          @ir.add_gate(type: Primitives::AND, inputs: [sub_carry, axb], output: cab)
          @ir.add_gate(type: Primitives::OR, inputs: [ab, cab], output: cout)
          sub_result << sum
          sub_carry = cout
        end
        sub_cout = sub_carry

        # AND result
        and_result = a_nets.zip(b_nets).map do |a, b|
          r = new_temp
          @ir.add_gate(type: Primitives::AND, inputs: [a, b], output: r)
          r
        end

        # OR result
        or_result = a_nets.zip(b_nets).map do |a, b|
          r = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [a, b], output: r)
          r
        end

        # XOR result
        xor_result = a_nets.zip(b_nets).map do |a, b|
          r = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a, b], output: r)
          r
        end

        # Simplified: use ADD as default result
        width.times do |idx|
          @ir.add_gate(type: Primitives::BUF, inputs: [add_result[idx]], output: result_nets[idx])
        end

        # N = result[7]
        @ir.add_gate(type: Primitives::BUF, inputs: [add_result[7]], output: n_net)

        # Z = NOR of all result bits
        z_temp = add_result[0]
        (1...width).each do |idx|
          t = new_temp
          @ir.add_gate(type: Primitives::OR, inputs: [z_temp, add_result[idx]], output: t)
          z_temp = t
        end
        @ir.add_gate(type: Primitives::NOT, inputs: [z_temp], output: z_net)

        # C = carry out
        @ir.add_gate(type: Primitives::BUF, inputs: [add_cout], output: c_net)

        # V = overflow (simplified)
        const_zero = new_temp
        @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
        @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: v_net)
      end

      # MOS6502S InstructionDecoder: ROM-style opcode decoder
      def lower_mos6502s_instruction_decoder(component)
        opcode_nets = map_bus(component.inputs[:opcode])

        # Output nets
        addr_mode_nets = map_bus(component.outputs[:addr_mode])
        alu_op_nets = map_bus(component.outputs[:alu_op])
        instr_type_nets = map_bus(component.outputs[:instr_type])
        src_reg_nets = map_bus(component.outputs[:src_reg])
        dst_reg_nets = map_bus(component.outputs[:dst_reg])
        branch_cond_nets = map_bus(component.outputs[:branch_cond])
        cycles_base_nets = map_bus(component.outputs[:cycles_base])
        is_read_net = map_bus(component.outputs[:is_read]).first
        is_write_net = map_bus(component.outputs[:is_write]).first
        is_rmw_net = map_bus(component.outputs[:is_rmw]).first
        sets_nz_net = map_bus(component.outputs[:sets_nz]).first
        sets_c_net = map_bus(component.outputs[:sets_c]).first
        sets_v_net = map_bus(component.outputs[:sets_v]).first
        writes_reg_net = map_bus(component.outputs[:writes_reg]).first
        is_status_op_net = map_bus(component.outputs[:is_status_op]).first
        illegal_net = map_bus(component.outputs[:illegal]).first

        # Simplified: output zeros for all decode outputs
        # Full implementation would require complete decode ROM
        all_outputs = [
          addr_mode_nets, alu_op_nets, instr_type_nets, src_reg_nets,
          dst_reg_nets, branch_cond_nets, cycles_base_nets
        ]
        all_outputs.each do |nets|
          nets.each do |out|
            const_zero = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
          end
        end

        [is_read_net, is_write_net, is_rmw_net, sets_nz_net, sets_c_net,
         sets_v_net, writes_reg_net, is_status_op_net, illegal_net].each do |out|
          const_zero = new_temp
          @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
          @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
        end
      end

      # MOS6502S ControlUnit: state machine
      def lower_mos6502s_control_unit(component)
        rst_net = map_bus(component.inputs[:rst]).first
        rdy_net = map_bus(component.inputs[:rdy]).first

        # Simplified: output zeros for all control signals
        # Full implementation would require complete state machine
        component.outputs.each do |name, wire|
          out_nets = map_bus(wire)
          out_nets.each do |out|
            const_zero = new_temp
            @ir.add_gate(type: Primitives::CONST, inputs: [], output: const_zero, value: 0)
            @ir.add_gate(type: Primitives::BUF, inputs: [const_zero], output: out)
          end
        end
      end

      # MOS6502S Datapath: structural composition using structure DSL
      def lower_mos6502s_datapath(component)
        # Use the same approach as SynthDatapath - process structure instances
        instance_defs = component.class._instance_defs
        connection_defs = component.class._connection_defs

        return if instance_defs.nil? || instance_defs.empty?

        # Create sub-component instances and map their ports to nets
        sub_components = {}
        sub_nets = {}

        instance_defs.each do |inst_def|
          inst_name = inst_def[:name]
          component_class = inst_def[:component_class]
          params = inst_def[:parameters] || {}

          # Create sub-component instance
          sub_comp = component_class.new("#{component.name}_#{inst_name}", **params)
          sub_components[inst_name] = sub_comp

          # Create nets for all ports
          sub_comp.inputs.each do |port_name, wire|
            next unless wire
            width = wire.respond_to?(:width) ? wire.width : 1
            sub_nets[[inst_name, port_name]] = width == 1 ? new_temp : width.times.map { new_temp }
          end

          sub_comp.outputs.each do |port_name, wire|
            next unless wire
            width = wire.respond_to?(:width) ? wire.width : 1
            sub_nets[[inst_name, port_name]] = width == 1 ? new_temp : width.times.map { new_temp }
          end
        end

        # Process connections
        connection_defs&.each do |conn_def|
          conn_def.each do |from, to|
            next unless from && to

            # Get source nets
            source_nets = if from.is_a?(Array)
              sub_nets[[from[0], from[1]]]
            else
              component.inputs[from] ? map_bus(component.inputs[from]) : nil
            end

            # Get dest nets
            dest_nets_list = to.is_a?(Array) && to.first.is_a?(Array) ? to : [to]
            dest_nets_list.each do |dest|
              dest_nets = if dest.is_a?(Array)
                sub_nets[[dest[0], dest[1]]]
              else
                component.outputs[dest] ? map_bus(component.outputs[dest]) : nil
              end

              next unless source_nets && dest_nets

              source_nets = [source_nets] unless source_nets.is_a?(Array)
              dest_nets = [dest_nets] unless dest_nets.is_a?(Array)

              [source_nets.length, dest_nets.length].min.times do |i|
                next unless source_nets[i] && dest_nets[i]
                @ir.add_gate(type: Primitives::BUF, inputs: [source_nets[i]], output: dest_nets[i])
              end
            end
          end
        end

        # Lower each sub-component
        sub_components.each do |inst_name, sub_comp|
          sub_comp.inputs.each do |port_name, wire|
            next unless wire
            nets = sub_nets[[inst_name, port_name]]
            next unless nets
            nets = [nets] unless nets.is_a?(Array)
            wire.width.times { |i| @net_map[[wire, i]] = nets[i] if nets[i] }
          end

          sub_comp.outputs.each do |port_name, wire|
            next unless wire
            nets = sub_nets[[inst_name, port_name]]
            next unless nets
            nets = [nets] unless nets.is_a?(Array)
            wire.width.times { |i| @net_map[[wire, i]] = nets[i] if nets[i] }
          end

          dispatch_lower(sub_comp)
        end
      end
    end
  end
end
