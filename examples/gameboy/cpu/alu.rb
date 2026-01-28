# SM83 ALU - Game Boy CPU ALU
# Corresponds to: reference/rtl/T80/T80_ALU.vhd
#
# The SM83 ALU handles:
# - 8-bit arithmetic (ADD, ADC, SUB, SBC)
# - 8-bit logic (AND, OR, XOR, CP)
# - Rotates and shifts (RL, RR, RLC, RRC, SLA, SRA, SRL, SWAP)
# - 16-bit add for HL
# - DAA (decimal adjust)
#
# Flag positions for Game Boy (Mode=3):
# - Bit 7: Z (Zero)
# - Bit 6: N (Subtract)
# - Bit 5: H (Half-carry)
# - Bit 4: C (Carry)
# - Bits 3-0: Always 0

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class SM83_ALU < RHDL::HDL::Component
    include RHDL::DSL::Behavior

    # ALU operation codes (from T80_Pack.vhd)
    ALU_ADD  = 0
    ALU_ADC  = 1
    ALU_SUB  = 2
    ALU_SBC  = 3
    ALU_AND  = 4
    ALU_XOR  = 5
    ALU_OR   = 6
    ALU_CP   = 7
    ALU_RLC  = 8
    ALU_RRC  = 9
    ALU_RL   = 10
    ALU_RR   = 11
    ALU_DAA  = 12
    ALU_CPL  = 13
    ALU_SCF  = 14
    ALU_CCF  = 15

    input :clk
    input :A, width: 8          # First operand
    input :B, width: 8          # Second operand
    input :Op, width: 4         # ALU operation
    input :F_In, width: 8       # Flags input
    input :Arith16, default: 0  # 16-bit arithmetic mode
    input :Z16, default: 0      # 16-bit zero flag mode

    output :Q, width: 8         # Result
    output :F_Out, width: 8     # Flags output

    # Internal signals
    wire :result, width: 9      # 9-bit for carry detection
    wire :half_result, width: 5 # 5-bit for half-carry detection
    wire :z_flag
    wire :n_flag
    wire :h_flag
    wire :c_flag

    behavior do
      # Extract input flags
      c_in = F_In[4]
      h_in = F_In[5]
      n_in = F_In[6]
      z_in = F_In[7]

      # ALU operations (combinational)
      result <= case_select(Op, {
        ALU_ADD => (cat(lit(0, width: 1), A) + cat(lit(0, width: 1), B)),
        ALU_ADC => (cat(lit(0, width: 1), A) + cat(lit(0, width: 1), B) + cat(lit(0, width: 8), F_In[4])),
        ALU_SUB => (cat(lit(0, width: 1), A) - cat(lit(0, width: 1), B)),
        ALU_SBC => (cat(lit(0, width: 1), A) - cat(lit(0, width: 1), B) - cat(lit(0, width: 8), F_In[4])),
        ALU_AND => cat(lit(0, width: 1), A & B),
        ALU_XOR => cat(lit(0, width: 1), A ^ B),
        ALU_OR  => cat(lit(0, width: 1), A | B),
        ALU_CP  => (cat(lit(0, width: 1), A) - cat(lit(0, width: 1), B)),
        ALU_RLC => cat(A[7], A[6..0], A[7]),
        ALU_RRC => cat(A[0], A[0], A[7..1]),
        ALU_RL  => cat(A[7], A[6..0], F_In[4]),
        ALU_RR  => cat(A[0], F_In[4], A[7..1]),
        ALU_DAA => cat(lit(0, width: 1), A),  # DAA handled separately
        ALU_CPL => cat(lit(0, width: 1), ~A),
        ALU_SCF => cat(lit(0, width: 1), A),
        ALU_CCF => cat(lit(0, width: 1), A)
      }, default: cat(lit(0, width: 1), A))

      # Half-carry calculation (for ADD/ADC/SUB/SBC)
      half_result <= case_select(Op, {
        ALU_ADD => (cat(lit(0, width: 1), A[3..0]) + cat(lit(0, width: 1), B[3..0])),
        ALU_ADC => (cat(lit(0, width: 1), A[3..0]) + cat(lit(0, width: 1), B[3..0]) + cat(lit(0, width: 4), F_In[4])),
        ALU_SUB => (cat(lit(0, width: 1), A[3..0]) - cat(lit(0, width: 1), B[3..0])),
        ALU_SBC => (cat(lit(0, width: 1), A[3..0]) - cat(lit(0, width: 1), B[3..0]) - cat(lit(0, width: 4), F_In[4])),
        ALU_CP  => (cat(lit(0, width: 1), A[3..0]) - cat(lit(0, width: 1), B[3..0]))
      }, default: lit(0, width: 5))

      # Result output (low 8 bits)
      Q <= result[7..0]

      # Flag calculation for Game Boy (Mode=3)
      # Z flag
      z_flag <= (result[7..0] == lit(0, width: 8))

      # N flag (set for subtraction operations)
      n_flag <= case_select(Op, {
        ALU_SUB => lit(1, width: 1),
        ALU_SBC => lit(1, width: 1),
        ALU_CP  => lit(1, width: 1),
        ALU_CPL => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # H flag
      h_flag <= case_select(Op, {
        ALU_ADD => half_result[4],
        ALU_ADC => half_result[4],
        ALU_SUB => half_result[4],
        ALU_SBC => half_result[4],
        ALU_CP  => half_result[4],
        ALU_AND => lit(1, width: 1),
        ALU_CPL => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # C flag
      c_flag <= case_select(Op, {
        ALU_ADD => result[8],
        ALU_ADC => result[8],
        ALU_SUB => result[8],
        ALU_SBC => result[8],
        ALU_CP  => result[8],
        ALU_RLC => result[8],
        ALU_RRC => result[8],
        ALU_RL  => result[8],
        ALU_RR  => result[8],
        ALU_SCF => lit(1, width: 1),
        ALU_CCF => ~F_In[4]
      }, default: F_In[4])

      # Assemble flags output (GB format: ZNHC0000)
      F_Out <= cat(z_flag, n_flag, h_flag, c_flag, lit(0, width: 4))
    end
  end
end
