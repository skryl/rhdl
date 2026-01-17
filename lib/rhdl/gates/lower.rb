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
          else
            raise ArgumentError, "Unsupported component for gate-level lowering: #{component.class}"
          end
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

        # For increment: add 1
        # For decrement: subtract 1 = add all 1s + 1 = add 0 (two's complement of 1)
        # Using XOR to conditionally invert and add inc as carry

        # When inc=1: result = A + 1 (carry in = 1)
        # When inc=0: result = A + (-1) = A + 0xFF...F + 1 = A - 1 (carry in = 1, all bits inverted = subtract)
        # Actually: A - 1 = A + ~1 + 1 = A + 0xFE + 1 = A + 0xFF
        # Simpler: use A XOR inc for each bit, then ripple add

        # For inc/dec by 1:
        # inc=1: result = A + 1
        # inc=0: result = A - 1 = A + (-1) in two's complement

        # Increment chain: propagate carry through
        carry = inc_net  # Start with inc as carry-in for increment
        inc_inv = new_temp
        @ir.add_gate(type: Primitives::NOT, inputs: [inc_net], output: inc_inv)

        width.times do |idx|
          a_net = a_nets[idx]
          result_net = result_nets[idx]

          # For increment: half-adder chain (A + 1)
          # For decrement: A - 1 = A + ~0 + 1 but simpler as borrow chain

          # Combined: XOR a with inc_inv to flip for decrement mode
          a_xor = new_temp
          @ir.add_gate(type: Primitives::XOR, inputs: [a_net, inc_inv], output: a_xor)

          # Half adder: result = a_xor XOR carry, next_carry = a_xor AND carry
          @ir.add_gate(type: Primitives::XOR, inputs: [a_xor, carry], output: result_net)

          if idx < width - 1
            next_carry = new_temp
            @ir.add_gate(type: Primitives::AND, inputs: [a_xor, carry], output: next_carry)
            carry = next_carry
          else
            # Last bit: capture carry out
            final_carry = new_temp
            @ir.add_gate(type: Primitives::AND, inputs: [a_xor, carry], output: final_carry)
            carry = final_carry
          end
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
    end
  end
end
