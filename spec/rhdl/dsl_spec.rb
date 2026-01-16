require 'spec_helper'

RSpec.describe RHDL::DSL do
  describe 'SignalRef' do
    let(:signal) { RHDL::DSL::SignalRef.new(:data, width: 8) }

    describe 'basic properties' do
      it 'has a name and width' do
        expect(signal.name).to eq(:data)
        expect(signal.width).to eq(8)
      end

      it 'converts to VHDL' do
        expect(signal.to_vhdl).to eq('data')
      end
    end

    describe 'bit selection' do
      it 'selects a single bit' do
        bit = signal[3]
        expect(bit).to be_a(RHDL::DSL::BitSelect)
        expect(bit.index).to eq(3)
        expect(bit.to_vhdl).to eq('data(3)')
      end

      it 'selects a bit range' do
        slice = signal[3..7]
        expect(slice).to be_a(RHDL::DSL::BitSlice)
        expect(slice.range).to eq(3..7)
        expect(slice.to_vhdl).to eq('data(7 downto 3)')
      end
    end

    describe 'arithmetic operators' do
      let(:other) { RHDL::DSL::SignalRef.new(:other, width: 8) }

      it 'creates addition expression' do
        expr = signal + other
        expect(expr).to be_a(RHDL::DSL::BinaryOp)
        expect(expr.op).to eq(:+)
        expect(expr.to_vhdl).to eq('(data + other)')
      end

      it 'creates subtraction expression' do
        expr = signal - other
        expect(expr.op).to eq(:-)
        expect(expr.to_vhdl).to eq('(data - other)')
      end

      it 'creates multiplication expression' do
        expr = signal * other
        expect(expr.op).to eq(:*)
        expect(expr.to_vhdl).to eq('(data * other)')
      end

      it 'creates division expression' do
        expr = signal / other
        expect(expr.op).to eq(:/)
        expect(expr.to_vhdl).to eq('(data / other)')
      end

      it 'creates modulo expression' do
        expr = signal % other
        expect(expr.op).to eq(:%)
      end
    end

    describe 'bitwise operators' do
      let(:other) { RHDL::DSL::SignalRef.new(:mask, width: 8) }

      it 'creates AND expression' do
        expr = signal & other
        expect(expr.op).to eq(:&)
        expect(expr.to_vhdl).to eq('(data and mask)')
      end

      it 'creates OR expression' do
        expr = signal | other
        expect(expr.op).to eq(:|)
        expect(expr.to_vhdl).to eq('(data or mask)')
      end

      it 'creates XOR expression' do
        expr = signal ^ other
        expect(expr.op).to eq(:^)
        expect(expr.to_vhdl).to eq('(data xor mask)')
      end

      it 'creates NOT expression' do
        expr = ~signal
        expect(expr).to be_a(RHDL::DSL::UnaryOp)
        expect(expr.op).to eq(:~)
        expect(expr.to_vhdl).to eq('not data')
      end
    end

    describe 'shift operators' do
      it 'creates left shift expression' do
        expr = signal << 2
        expect(expr.op).to eq(:<<)
        expect(expr.to_vhdl).to eq('(data sll 2)')
      end

      it 'creates right shift expression' do
        expr = signal >> 2
        expect(expr.op).to eq(:>>)
        expect(expr.to_vhdl).to eq('(data srl 2)')
      end
    end

    describe 'comparison operators' do
      let(:other) { RHDL::DSL::SignalRef.new(:threshold, width: 8) }

      it 'creates equality expression' do
        expr = signal == other
        expect(expr.to_vhdl).to eq('(data = threshold)')
      end

      it 'creates inequality expression' do
        expr = signal != other
        expect(expr.to_vhdl).to eq('(data /= threshold)')
      end

      it 'creates less than expression' do
        expr = signal < other
        expect(expr.to_vhdl).to eq('(data < threshold)')
      end

      it 'creates greater than expression' do
        expr = signal > other
        expect(expr.to_vhdl).to eq('(data > threshold)')
      end

      it 'creates less or equal expression' do
        expr = signal <= other
        expect(expr.to_vhdl).to eq('(data <= threshold)')
      end

      it 'creates greater or equal expression' do
        expr = signal >= other
        expect(expr.to_vhdl).to eq('(data >= threshold)')
      end
    end

    describe 'concatenation and replication' do
      let(:high) { RHDL::DSL::SignalRef.new(:high, width: 4) }
      let(:low) { RHDL::DSL::SignalRef.new(:low, width: 4) }

      it 'concatenates signals' do
        expr = high.concat(low)
        expect(expr).to be_a(RHDL::DSL::Concatenation)
        expect(expr.to_vhdl).to eq('(high & low)')
      end

      it 'replicates a signal' do
        bit = RHDL::DSL::SignalRef.new(:sign, width: 1)
        expr = bit.replicate(4)
        expect(expr).to be_a(RHDL::DSL::Replication)
        expect(expr.to_vhdl).to eq('(sign & sign & sign & sign)')
      end
    end

    describe 'expression chaining' do
      let(:a) { RHDL::DSL::SignalRef.new(:a, width: 8) }
      let(:b) { RHDL::DSL::SignalRef.new(:b, width: 8) }
      let(:c) { RHDL::DSL::SignalRef.new(:c, width: 8) }

      it 'chains bitwise operations' do
        expr = (a & b) | c
        expect(expr.to_vhdl).to eq('((a and b) or c)')
      end

      it 'chains mixed operations' do
        expr = (a + b) & c
        expect(expr.to_vhdl).to eq('((a + b) and c)')
      end
    end
  end

  describe 'Port' do
    it 'creates single-bit input port' do
      port = RHDL::DSL::Port.new(:clk, :in, 1)
      expect(port.to_vhdl).to eq('clk : in std_logic')
    end

    it 'creates multi-bit input port' do
      port = RHDL::DSL::Port.new(:data, :in, 8)
      expect(port.to_vhdl).to eq('data : in std_logic_vector(7 downto 0)')
    end

    it 'creates output port' do
      port = RHDL::DSL::Port.new(:result, :out, 16)
      expect(port.to_vhdl).to eq('result : out std_logic_vector(15 downto 0)')
    end

    it 'converts to signal ref' do
      port = RHDL::DSL::Port.new(:data, :in, 8)
      ref = port.to_signal_ref
      expect(ref.name).to eq(:data)
      expect(ref.width).to eq(8)
    end
  end

  describe 'Signal' do
    it 'creates single-bit signal' do
      sig = RHDL::DSL::Signal.new(:flag, 1)
      expect(sig.to_vhdl).to eq('signal flag : std_logic;')
    end

    it 'creates multi-bit signal' do
      sig = RHDL::DSL::Signal.new(:counter, 8)
      expect(sig.to_vhdl).to eq('signal counter : std_logic_vector(7 downto 0);')
    end

    it 'creates signal with default value' do
      sig = RHDL::DSL::Signal.new(:counter, 8, default: 0)
      expect(sig.to_vhdl).to eq('signal counter : std_logic_vector(7 downto 0) := "00000000";')
    end

    it 'creates single-bit signal with default' do
      sig = RHDL::DSL::Signal.new(:flag, 1, default: 1)
      expect(sig.to_vhdl).to eq("signal flag : std_logic := '1';")
    end
  end

  describe 'Constant' do
    it 'creates constant declaration' do
      const = RHDL::DSL::Constant.new(:MAX_VALUE, 8, 255)
      expect(const.to_vhdl).to eq('constant MAX_VALUE : std_logic_vector(7 downto 0) := "11111111";')
    end

    it 'creates single-bit constant' do
      const = RHDL::DSL::Constant.new(:HIGH, 1, 1)
      expect(const.to_vhdl).to eq("constant HIGH : std_logic := '1';")
    end
  end

  describe 'Assignment' do
    let(:target) { RHDL::DSL::SignalRef.new(:result, width: 8) }
    let(:source) { RHDL::DSL::SignalRef.new(:input, width: 8) }

    it 'creates simple assignment' do
      assign = RHDL::DSL::Assignment.new(target, source)
      expect(assign.to_vhdl).to eq('result <= input;')
    end

    it 'creates conditional assignment' do
      cond = RHDL::DSL::SignalRef.new(:enable, width: 1)
      assign = RHDL::DSL::Assignment.new(target, source, condition: cond)
      expect(assign.to_vhdl).to eq('result <= input when enable else result;')
    end
  end

  describe 'ProcessBlock' do
    let(:clk) { RHDL::DSL::SignalRef.new(:clk, width: 1) }
    let(:data) { RHDL::DSL::SignalRef.new(:data, width: 8) }
    let(:result) { RHDL::DSL::SignalRef.new(:result, width: 8) }

    it 'creates a simple process' do
      result_ref = result
      data_ref = data
      proc = RHDL::DSL::ProcessBlock.new(:main_proc, sensitivity_list: [clk]) do
        assign(result_ref, data_ref)
      end

      vhdl = proc.to_vhdl
      expect(vhdl).to include('main_proc: process(clk)')
      expect(vhdl).to include('begin')
      expect(vhdl).to include('result <= data;')
      expect(vhdl).to include('end process main_proc;')
    end

    it 'creates process with if statement' do
      enable = RHDL::DSL::SignalRef.new(:enable, width: 1)
      result_ref = result
      data_ref = data
      proc = RHDL::DSL::ProcessBlock.new(:cond_proc, sensitivity_list: [clk, enable]) do
        if_stmt(enable == 1) do
          assign(result_ref, data_ref)
        end
      end

      vhdl = proc.to_vhdl
      expect(vhdl).to include('if (enable = 1) then')
      expect(vhdl).to include('result <= data;')
      expect(vhdl).to include('end if;')
    end
  end

  describe 'IfStatement' do
    let(:cond) { RHDL::DSL::SignalRef.new(:enable, width: 1) == 1 }

    it 'creates simple if statement' do
      stmt = RHDL::DSL::IfStatement.new(cond)
      stmt.add_then(RHDL::DSL::SequentialAssignment.new(:output, 1))

      vhdl = stmt.to_vhdl
      expect(vhdl).to include('if (enable = 1) then')
      expect(vhdl).to include('output <= 1;')
      expect(vhdl).to include('end if;')
    end

    it 'creates if-else statement' do
      stmt = RHDL::DSL::IfStatement.new(cond)
      stmt.add_then(RHDL::DSL::SequentialAssignment.new(:output, 1))
      stmt.add_else(RHDL::DSL::SequentialAssignment.new(:output, 0))

      vhdl = stmt.to_vhdl
      expect(vhdl).to include('else')
      expect(vhdl).to include('output <= 0;')
    end

    it 'creates if-elsif-else statement' do
      cond2 = RHDL::DSL::SignalRef.new(:mode, width: 1) == 1
      stmt = RHDL::DSL::IfStatement.new(cond)
      stmt.add_then(RHDL::DSL::SequentialAssignment.new(:output, 1))
      stmt.add_elsif(cond2, [RHDL::DSL::SequentialAssignment.new(:output, 2)])
      stmt.add_else(RHDL::DSL::SequentialAssignment.new(:output, 0))

      vhdl = stmt.to_vhdl
      expect(vhdl).to include('elsif (mode = 1) then')
      expect(vhdl).to include('output <= 2;')
    end
  end

  describe 'CaseStatement' do
    let(:selector) { RHDL::DSL::SignalRef.new(:opcode, width: 4) }

    it 'creates case statement' do
      stmt = RHDL::DSL::CaseStatement.new(selector)
      stmt.add_when(0, [RHDL::DSL::SequentialAssignment.new(:output, 10)])
      stmt.add_when(1, [RHDL::DSL::SequentialAssignment.new(:output, 20)])
      stmt.add_default([RHDL::DSL::SequentialAssignment.new(:output, 0)])

      vhdl = stmt.to_vhdl
      expect(vhdl).to include('case opcode is')
      expect(vhdl).to include('when "0" =>')
      expect(vhdl).to include('output <= 10;')
      expect(vhdl).to include('when "1" =>')
      expect(vhdl).to include('when others =>')
      expect(vhdl).to include('end case;')
    end
  end

  describe 'ForLoop' do
    it 'creates for loop' do
      loop_stmt = RHDL::DSL::ForLoop.new(:i, 0..7)
      loop_stmt.add_statement(RHDL::DSL::SequentialAssignment.new(:data, :i))

      vhdl = loop_stmt.to_vhdl
      expect(vhdl).to include('for i in 0 to 7 loop')
      expect(vhdl).to include('data <= i;')
      expect(vhdl).to include('end loop;')
    end
  end

  describe 'Edge conditions' do
    let(:clk) { RHDL::DSL::SignalRef.new(:clk, width: 1) }

    it 'creates rising edge condition' do
      edge = RHDL::DSL::RisingEdge.new(clk)
      expect(edge.to_vhdl).to eq('rising_edge(clk)')
    end

    it 'creates falling edge condition' do
      edge = RHDL::DSL::FallingEdge.new(clk)
      expect(edge.to_vhdl).to eq('falling_edge(clk)')
    end
  end

  describe 'ComponentInstance' do
    it 'creates simple component instance' do
      a = RHDL::DSL::SignalRef.new(:a_sig, width: 8)
      b = RHDL::DSL::SignalRef.new(:b_sig, width: 8)
      y = RHDL::DSL::SignalRef.new(:y_sig, width: 8)

      inst = RHDL::DSL::ComponentInstance.new(:adder1, :adder8bit, port_map: {
        a: a, b: b, y: y
      })

      vhdl = inst.to_vhdl
      expect(vhdl).to include('adder1: adder8bit')
      expect(vhdl).to include('port map(a => a_sig, b => b_sig, y => y_sig);')
    end

    it 'creates instance with generics' do
      inst = RHDL::DSL::ComponentInstance.new(:reg1, :register,
        port_map: { d: :data_in, q: :data_out },
        generic_map: { width: 16 }
      )

      vhdl = inst.to_vhdl
      expect(vhdl).to include('generic map(width => 16)')
      expect(vhdl).to include('port map(d => data_in, q => data_out);')
    end
  end

  describe 'DSL module inclusion' do
    # Create a test component using the DSL
    class TestAdder
      include RHDL::DSL

      generic :width, type: :integer, default: 8

      input :a, width: 8
      input :b, width: 8
      input :cin, width: 1

      output :sum, width: 8
      output :cout, width: 1

      signal :temp_sum, width: 9
    end

    it 'defines ports as methods returning SignalRef' do
      adder = TestAdder.new
      expect(adder.a).to be_a(RHDL::DSL::SignalRef)
      expect(adder.a.name).to eq(:a)
      expect(adder.a.width).to eq(8)
    end

    it 'defines signals as methods' do
      adder = TestAdder.new
      expect(adder.temp_sum).to be_a(RHDL::DSL::SignalRef)
      expect(adder.temp_sum.width).to eq(9)
    end

    it 'tracks port definitions' do
      expect(TestAdder._ports.size).to eq(5)
      expect(TestAdder._ports.map(&:name)).to include(:a, :b, :cin, :sum, :cout)
    end

    it 'tracks signal definitions' do
      expect(TestAdder._signals.size).to eq(1)
      expect(TestAdder._signals.first.name).to eq(:temp_sum)
    end

    it 'generates VHDL entity' do
      vhdl = TestAdder.to_vhdl
      expect(vhdl).to include('library IEEE;')
      expect(vhdl).to include('use IEEE.STD_LOGIC_1164.ALL;')
      expect(vhdl).to include('entity test_adder is')
      expect(vhdl).to include('generic(')
      expect(vhdl).to include('width : integer := 8')
      expect(vhdl).to include('port(')
      expect(vhdl).to include('a : in std_logic_vector(7 downto 0)')
      expect(vhdl).to include('end test_adder;')
      expect(vhdl).to include('architecture rtl of test_adder is')
      expect(vhdl).to include('signal temp_sum : std_logic_vector(8 downto 0);')
    end
  end

  describe 'Component with processes' do
    class TestCounter
      include RHDL::DSL

      input :clk, width: 1
      input :rst, width: 1
      input :en, width: 1
      output :count, width: 8

      signal :counter_reg, width: 8, default: 0
    end

    it 'generates VHDL with signals having defaults' do
      vhdl = TestCounter.to_vhdl
      expect(vhdl).to include('signal counter_reg : std_logic_vector(7 downto 0) := "00000000";')
    end
  end

  describe 'runtime simulation interface' do
    class TestMux
      include RHDL::DSL

      input :a, width: 8
      input :b, width: 8
      input :sel, width: 1
      output :y, width: 8
    end

    it 'allows setting and getting port values' do
      mux = TestMux.new
      mux.set_input(:a, 0x42)
      mux.set_input(:b, 0xFF)
      mux.set_input(:sel, 1)

      expect(mux.get_output(:y)).to eq(0)  # Default value
    end

    it 'initializes with generic values' do
      class GenericComp
        include RHDL::DSL
        generic :width, type: :integer, default: 8
        generic :depth, type: :integer, default: 16
      end

      comp = GenericComp.new(width: 32, depth: 64)
      expect(comp.width).to eq(32)
      expect(comp.depth).to eq(64)
    end
  end
end
