require 'spec_helper'

RSpec.describe 'Verilog Export' do
  describe 'SignalRef' do
    let(:signal) { RHDL::DSL::SignalRef.new(:data, width: 8) }

    it 'converts to Verilog' do
      expect(signal.to_verilog).to eq('data')
    end
  end

  describe 'BitSelect' do
    let(:signal) { RHDL::DSL::SignalRef.new(:data, width: 8) }

    it 'generates Verilog bit selection' do
      bit = signal[3]
      expect(bit.to_verilog).to eq('data[3]')
    end
  end

  describe 'BitSlice' do
    let(:signal) { RHDL::DSL::SignalRef.new(:data, width: 8) }

    it 'generates Verilog bit range' do
      slice = signal[3..7]
      expect(slice.to_verilog).to eq('data[7:3]')
    end
  end

  describe 'BinaryOp' do
    let(:a) { RHDL::DSL::SignalRef.new(:a, width: 8) }
    let(:b) { RHDL::DSL::SignalRef.new(:b, width: 8) }

    it 'generates Verilog arithmetic operators' do
      expect((a + b).to_verilog).to eq('(a + b)')
      expect((a - b).to_verilog).to eq('(a - b)')
      expect((a * b).to_verilog).to eq('(a * b)')
      expect((a / b).to_verilog).to eq('(a / b)')
    end

    it 'generates Verilog bitwise operators' do
      expect((a & b).to_verilog).to eq('(a & b)')
      expect((a | b).to_verilog).to eq('(a | b)')
      expect((a ^ b).to_verilog).to eq('(a ^ b)')
    end

    it 'generates Verilog shift operators' do
      expect((a << 2).to_verilog).to eq('(a << 2)')
      expect((a >> 2).to_verilog).to eq('(a >> 2)')
    end

    it 'generates Verilog comparison operators' do
      expect((a == b).to_verilog).to eq('(a == b)')
      expect((a != b).to_verilog).to eq('(a != b)')
      expect((a < b).to_verilog).to eq('(a < b)')
      expect((a > b).to_verilog).to eq('(a > b)')
      expect((a <= b).to_verilog).to eq('(a <= b)')
      expect((a >= b).to_verilog).to eq('(a >= b)')
    end
  end

  describe 'UnaryOp' do
    let(:signal) { RHDL::DSL::SignalRef.new(:data, width: 8) }

    it 'generates Verilog NOT operator' do
      expr = ~signal
      expect(expr.to_verilog).to eq('~data')
    end
  end

  describe 'Concatenation' do
    let(:high) { RHDL::DSL::SignalRef.new(:high, width: 4) }
    let(:low) { RHDL::DSL::SignalRef.new(:low, width: 4) }

    it 'generates Verilog concatenation' do
      expr = high.concat(low)
      expect(expr.to_verilog).to eq('{high, low}')
    end
  end

  describe 'Replication' do
    let(:bit) { RHDL::DSL::SignalRef.new(:sign, width: 1) }

    it 'generates Verilog replication' do
      expr = bit.replicate(4)
      expect(expr.to_verilog).to eq('{4{sign}}')
    end
  end

  describe 'Port' do
    it 'generates Verilog single-bit input port' do
      port = RHDL::DSL::Port.new(:clk, :in, 1)
      expect(port.to_verilog).to eq('input clk')
    end

    it 'generates Verilog multi-bit input port' do
      port = RHDL::DSL::Port.new(:data, :in, 8)
      expect(port.to_verilog).to eq('input [7:0] data')
    end

    it 'generates Verilog output port' do
      port = RHDL::DSL::Port.new(:result, :out, 16)
      expect(port.to_verilog).to eq('output [15:0] result')
    end
  end

  describe 'Signal' do
    it 'generates Verilog single-bit reg' do
      sig = RHDL::DSL::Signal.new(:flag, 1)
      expect(sig.to_verilog).to eq('reg flag;')
    end

    it 'generates Verilog multi-bit reg' do
      sig = RHDL::DSL::Signal.new(:counter, 8)
      expect(sig.to_verilog).to eq('reg [7:0] counter;')
    end

    it 'generates Verilog reg with default value' do
      sig = RHDL::DSL::Signal.new(:counter, 8, default: 0)
      expect(sig.to_verilog).to eq("reg [7:0] counter = 8'b00000000;")
    end

    it 'generates single-bit reg with default' do
      sig = RHDL::DSL::Signal.new(:flag, 1, default: 1)
      expect(sig.to_verilog).to eq("reg flag = 1'b1;")
    end
  end

  describe 'Constant' do
    it 'generates Verilog localparam' do
      const = RHDL::DSL::Constant.new(:MAX_VALUE, 8, 255)
      expect(const.to_verilog).to eq("localparam [7:0] MAX_VALUE = 8'b11111111;")
    end

    it 'generates single-bit localparam' do
      const = RHDL::DSL::Constant.new(:HIGH, 1, 1)
      expect(const.to_verilog).to eq("localparam HIGH = 1'b1;")
    end
  end

  describe 'Assignment' do
    let(:target) { RHDL::DSL::SignalRef.new(:result, width: 8) }
    let(:source) { RHDL::DSL::SignalRef.new(:input, width: 8) }

    it 'generates Verilog continuous assignment' do
      assign = RHDL::DSL::Assignment.new(target, source)
      expect(assign.to_verilog).to eq('assign result = input;')
    end

    it 'generates Verilog conditional assignment' do
      cond = RHDL::DSL::SignalRef.new(:enable, width: 1)
      assign = RHDL::DSL::Assignment.new(target, source, condition: cond)
      expect(assign.to_verilog).to eq('assign result = enable ? input : result;')
    end
  end

  describe 'ProcessBlock' do
    let(:clk) { RHDL::DSL::SignalRef.new(:clk, width: 1) }
    let(:data) { RHDL::DSL::SignalRef.new(:data, width: 8) }
    let(:result) { RHDL::DSL::SignalRef.new(:result, width: 8) }

    it 'generates Verilog combinational always block' do
      result_ref = result
      data_ref = data
      proc = RHDL::DSL::ProcessBlock.new(:main_proc, sensitivity_list: [clk]) do
        assign(result_ref, data_ref)
      end

      verilog = proc.to_verilog
      expect(verilog).to include('always @(clk)')
      expect(verilog).to include('begin')
      expect(verilog).to include('result <= data;')
      expect(verilog).to include('end')
    end

    it 'generates Verilog clocked always block' do
      result_ref = result
      data_ref = data
      proc = RHDL::DSL::ProcessBlock.new(:clk_proc, sensitivity_list: [clk], clocked: true) do
        assign(result_ref, data_ref)
      end

      verilog = proc.to_verilog
      expect(verilog).to include('always @(posedge clk)')
    end
  end

  describe 'IfStatement' do
    let(:cond) { RHDL::DSL::SignalRef.new(:enable, width: 1) == 1 }

    it 'generates Verilog if statement' do
      stmt = RHDL::DSL::IfStatement.new(cond)
      stmt.add_then(RHDL::DSL::SequentialAssignment.new(:output, 1))

      verilog = stmt.to_verilog
      expect(verilog).to include('if ((enable == 1)) begin')
      expect(verilog).to include('output <= 1;')
      expect(verilog).to include('end')
    end

    it 'generates Verilog if-else statement' do
      stmt = RHDL::DSL::IfStatement.new(cond)
      stmt.add_then(RHDL::DSL::SequentialAssignment.new(:output, 1))
      stmt.add_else(RHDL::DSL::SequentialAssignment.new(:output, 0))

      verilog = stmt.to_verilog
      expect(verilog).to include('else begin')
      expect(verilog).to include('output <= 0;')
    end

    it 'generates Verilog if-else if-else statement' do
      cond2 = RHDL::DSL::SignalRef.new(:mode, width: 1) == 1
      stmt = RHDL::DSL::IfStatement.new(cond)
      stmt.add_then(RHDL::DSL::SequentialAssignment.new(:output, 1))
      stmt.add_elsif(cond2, [RHDL::DSL::SequentialAssignment.new(:output, 2)])
      stmt.add_else(RHDL::DSL::SequentialAssignment.new(:output, 0))

      verilog = stmt.to_verilog
      expect(verilog).to include('else if ((mode == 1)) begin')
      expect(verilog).to include('output <= 2;')
    end
  end

  describe 'CaseStatement' do
    let(:selector) { RHDL::DSL::SignalRef.new(:opcode, width: 4) }

    it 'generates Verilog case statement' do
      stmt = RHDL::DSL::CaseStatement.new(selector)
      stmt.add_when(0, [RHDL::DSL::SequentialAssignment.new(:output, 10)])
      stmt.add_when(1, [RHDL::DSL::SequentialAssignment.new(:output, 20)])
      stmt.add_default([RHDL::DSL::SequentialAssignment.new(:output, 0)])

      verilog = stmt.to_verilog
      expect(verilog).to include('case (opcode)')
      expect(verilog).to include('0: begin')
      expect(verilog).to include('output <= 10;')
      expect(verilog).to include('1: begin')
      expect(verilog).to include('default: begin')
      expect(verilog).to include('endcase')
    end
  end

  describe 'ForLoop' do
    it 'generates Verilog for loop' do
      loop_stmt = RHDL::DSL::ForLoop.new(:i, 0..7)
      loop_stmt.add_statement(RHDL::DSL::SequentialAssignment.new(:data, :i))

      verilog = loop_stmt.to_verilog
      expect(verilog).to include('for (i = 0; i <= 7; i = i + 1) begin')
      expect(verilog).to include('data <= i;')
      expect(verilog).to include('end')
    end
  end

  describe 'Edge conditions' do
    let(:clk) { RHDL::DSL::SignalRef.new(:clk, width: 1) }

    it 'generates posedge condition' do
      edge = RHDL::DSL::RisingEdge.new(clk)
      expect(edge.to_verilog).to eq('posedge clk')
    end

    it 'generates negedge condition' do
      edge = RHDL::DSL::FallingEdge.new(clk)
      expect(edge.to_verilog).to eq('negedge clk')
    end
  end

  describe 'ComponentInstance' do
    it 'generates Verilog module instantiation' do
      a = RHDL::DSL::SignalRef.new(:a_sig, width: 8)
      b = RHDL::DSL::SignalRef.new(:b_sig, width: 8)
      y = RHDL::DSL::SignalRef.new(:y_sig, width: 8)

      inst = RHDL::DSL::ComponentInstance.new(:adder1, :adder8bit, port_map: {
        a: a, b: b, y: y
      })

      verilog = inst.to_verilog
      expect(verilog).to include('adder8bit adder1 (')
      expect(verilog).to include('.a(a_sig)')
      expect(verilog).to include('.b(b_sig)')
      expect(verilog).to include('.y(y_sig)')
      expect(verilog).to include(');')
    end

    it 'generates Verilog instance with parameters' do
      inst = RHDL::DSL::ComponentInstance.new(:reg1, :register,
        port_map: { d: :data_in, q: :data_out },
        generic_map: { width: 16 }
      )

      verilog = inst.to_verilog
      expect(verilog).to include('register #(.width(16)) reg1 (')
      expect(verilog).to include('.d(data_in)')
      expect(verilog).to include('.q(data_out)')
    end
  end

  describe 'Full component Verilog generation' do
    # Define a test component for Verilog export
    before(:all) do
      # Remove existing class if defined (for test isolation)
      Object.send(:remove_const, :VerilogTestAdder) if defined?(VerilogTestAdder)

      class VerilogTestAdder
        include RHDL::DSL

        generic :width, type: :integer, default: 8

        input :a, width: 8
        input :b, width: 8
        input :cin, width: 1

        output :sum, width: 8
        output :cout, width: 1

        signal :temp_sum, width: 9
      end
    end

    it 'generates complete Verilog module' do
      verilog = VerilogTestAdder.to_verilog

      expect(verilog).to include('module verilog_test_adder')
      expect(verilog).to include('#(')
      expect(verilog).to include('parameter width = 8')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('input cin')
      expect(verilog).to include('output [7:0] sum')
      expect(verilog).to include('output cout')
      expect(verilog).to include('reg [8:0] temp_sum;')
      expect(verilog).to include('endmodule')
    end

    it 'generates valid Verilog syntax' do
      verilog = VerilogTestAdder.to_verilog

      # Check for proper module structure
      expect(verilog).to match(/module\s+\w+/)
      expect(verilog).to match(/endmodule/)

      # Check parameters before ports
      param_pos = verilog.index('parameter')
      port_pos = verilog.index('input')
      expect(param_pos).to be < port_pos
    end
  end

  describe 'Component with no generics' do
    before(:all) do
      Object.send(:remove_const, :SimpleVerilogMux) if defined?(SimpleVerilogMux)

      class SimpleVerilogMux
        include RHDL::DSL

        input :a, width: 8
        input :b, width: 8
        input :sel, width: 1
        output :y, width: 8
      end
    end

    it 'generates module without parameter block' do
      verilog = SimpleVerilogMux.to_verilog

      expect(verilog).to include('module simple_verilog_mux')
      expect(verilog).not_to include('#(')
      expect(verilog).not_to include('parameter')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] y')
    end
  end
end
