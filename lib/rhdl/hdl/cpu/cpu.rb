# Declarative CPU - combines all CPU components
# Generates Verilog module with full CPU structure

module RHDL
  module HDL
    module CPU
      class CPU < SimComponent
        attr_reader :decoder, :alu, :pc, :acc, :sp

        # Clock and reset
        input :clk
        input :rst

        # Memory interface
        input :mem_data_in, width: 8
        output :mem_data_out, width: 8
        output :mem_addr, width: 16
        output :mem_write_en
        output :mem_read_en

        # Status outputs
        output :pc_out, width: 16
        output :acc_out, width: 8
        output :sp_out, width: 8
        output :zero_flag
        output :halt

        # Internal wires - control signals
        wire :instruction, width: 8
        wire :operand, width: 8
        wire :alu_result, width: 8
        wire :alu_op, width: 4
        wire :alu_zero
        wire :reg_write
        wire :alu_src
        wire :mem_read
        wire :mem_write
        wire :branch
        wire :jump
        wire :pc_src, width: 2
        wire :halt_signal
        wire :call_signal
        wire :ret_signal
        wire :instr_length, width: 2
        wire :sp_empty

        # Declarative structure for synthesis
        instance :decoder, InstructionDecoder
        port :instruction => [:decoder, :instruction]
        port :zero_flag => [:decoder, :zero_flag]
        port [:decoder, :alu_op] => :alu_op
        port [:decoder, :alu_src] => :alu_src
        port [:decoder, :reg_write] => :reg_write
        port [:decoder, :mem_read] => :mem_read
        port [:decoder, :mem_write] => :mem_write
        port [:decoder, :branch] => :branch
        port [:decoder, :jump] => :jump
        port [:decoder, :pc_src] => :pc_src
        port [:decoder, :halt] => :halt_signal
        port [:decoder, :call] => :call_signal
        port [:decoder, :ret] => :ret_signal
        port [:decoder, :instr_length] => :instr_length

        instance :alu, ALU, width: 8
        port :acc_out => [:alu, :a]
        port :mem_data_in => [:alu, :b]
        port :alu_op => [:alu, :op]
        port [:alu, :result] => :alu_result
        port [:alu, :zero] => :alu_zero

        instance :pc, ProgramCounter, width: 16
        port :clk => [:pc, :clk]
        port :rst => [:pc, :rst]
        port [:pc, :q] => :pc_out

        instance :acc, Register, width: 8
        port :clk => [:acc, :clk]
        port :rst => [:acc, :rst]
        port :alu_result => [:acc, :d]
        port [:acc, :q] => :acc_out

        instance :sp, StackPointer, width: 8, initial: 0xFF
        port :clk => [:sp, :clk]
        port :rst => [:sp, :rst]
        port [:sp, :q] => :sp_out
        port [:sp, :empty] => :sp_empty

        port :halt_signal => :halt
        port :mem_read => :mem_read_en
        port :mem_write => :mem_write_en

        def initialize(name = nil)
          super(name)
          # Instantiate components for behavioral simulation
          @decoder = InstructionDecoder.new("#{name}_decoder")
          @alu = ALU.new("#{name}_alu", width: 8)
          @pc = ProgramCounter.new("#{name}_pc", width: 16)
          @acc = Register.new("#{name}_acc", width: 8)
          @sp = StackPointer.new("#{name}_sp", width: 8, initial: 0xFF)
        end
      end
    end
  end
end
