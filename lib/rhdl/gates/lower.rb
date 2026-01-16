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
          when RHDL::HDL::BitwiseAnd
            lower_bitwise(component, Primitives::AND)
          when RHDL::HDL::BitwiseOr
            lower_bitwise(component, Primitives::OR)
          when RHDL::HDL::BitwiseXor
            lower_bitwise(component, Primitives::XOR)
          when RHDL::HDL::Mux2
            lower_mux2(component)
          when RHDL::HDL::HalfAdder
            lower_half_adder(component)
          when RHDL::HDL::FullAdder
            lower_full_adder(component)
          when RHDL::HDL::RippleCarryAdder
            lower_ripple_adder(component)
          when RHDL::HDL::DFlipFlop
            lower_dff(component, async_reset: false)
          when RHDL::HDL::DFlipFlopAsync
            lower_dff(component, async_reset: true)
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

      def lower_dff(component, async_reset: false)
        d_net = map_bus(component.inputs[:d]).first
        rst_net = map_bus(component.inputs[:rst]).first
        en_net = map_bus(component.inputs[:en]).first
        q_net = map_bus(component.outputs[:q]).first
        qn_net = map_bus(component.outputs[:qn]).first

        @ir.add_dff(d: d_net, q: q_net, rst: rst_net, en: en_net, async_reset: async_reset)
        @ir.add_gate(type: Primitives::NOT, inputs: [q_net], output: qn_net)
      end
    end
  end
end
