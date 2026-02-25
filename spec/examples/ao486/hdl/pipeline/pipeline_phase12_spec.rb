# spec/examples/ao486/hdl/pipeline/pipeline_phase12_spec.rb
# RED spec for Phase 12 (MS-DOS boot prerequisites):
#   - Critical bug fixes (segment overrides, ES for string ops, CS in INT)
#   - Missing instructions (CALL indirect/far, RET far, JMP indirect, PUSH/POP seg, etc.)

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::Pipeline, 'Phase 12: DOS boot prerequisites' do
  let(:pipeline) { described_class.new }
  let(:memory) { {} }

  def write_code(memory, addr, *bytes)
    bytes.each_with_index { |b, i| memory[(addr + i) & 0xFFFF_FFFF] = b & 0xFF }
  end

  def write_word(memory, addr, val)
    memory[addr]     = val & 0xFF
    memory[addr + 1] = (val >> 8) & 0xFF
  end

  def write_dword(memory, addr, val)
    memory[addr]     = val & 0xFF
    memory[addr + 1] = (val >> 8) & 0xFF
    memory[addr + 2] = (val >> 16) & 0xFF
    memory[addr + 3] = (val >> 24) & 0xFF
  end

  def read_byte(memory, addr)
    memory[addr] || 0
  end

  def read_word(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8)
  end

  def read_dword(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8) |
      ((memory[addr + 2] || 0) << 16) | ((memory[addr + 3] || 0) << 24)
  end

  def run_until_halt(max_steps = 1000)
    max_steps.times do
      result = pipeline.step(memory)
      return result if result == :halt
    end
    :timeout
  end

  # --- Phase 2: Critical Bug Fixes ---

  describe 'bug fixes' do
    describe 'segment override prefix' do
      it 'ES override changes effective segment for MOV load' do
        # ES base = 0x2000, DS base = 0x1000
        # ES:[0x0010] should read from linear 0x2010, not 0x1010
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x1000)
        pipeline.set_es_base(0x2000)

        # Write different values at DS:[0x10] and ES:[0x10]
        write_word(memory, 0x1010, 0xAAAA) # DS:0x10
        write_word(memory, 0x2010, 0xBBBB) # ES:0x10

        write_code(memory, 0x0100,
          0x26, 0x8B, 0x06, 0x10, 0x00,  # MOV AX, ES:[0x0010]
          0xF4                              # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0xBBBB)
      end

      it 'CS override for data access reads from code segment' do
        pipeline.setup_real_mode(cs_base: 0x3000, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x1000)

        # Data at CS:[0x50] = linear 0x3050
        write_word(memory, 0x3050, 0xCCDD)
        # Data at DS:[0x50] = linear 0x1050
        write_word(memory, 0x1050, 0x1122)

        write_code(memory, 0x3100,  # CS base + EIP
          0x2E, 0x8B, 0x06, 0x50, 0x00,  # MOV AX, CS:[0x0050]
          0xF4                              # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0xCCDD)
      end
    end

    describe 'MOVS uses ES:DI for destination' do
      it 'copies from DS:SI to ES:DI with different segment bases' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x1000)
        pipeline.set_es_base(0x2000)
        pipeline.set_reg(:esi, 0x0050)
        pipeline.set_reg(:edi, 0x0080)
        # Clear direction flag
        pipeline.set_flag(:df, 0)

        # Source data at DS:SI = linear 0x1050
        write_code(memory, 0x1050, 0xAA, 0xBB, 0xCC, 0xDD)

        write_code(memory, 0x0100,
          0xF3, 0xA4,  # REP MOVSB (CX bytes from DS:SI to ES:DI)
          0xF4          # HLT
        )
        pipeline.set_reg(:ecx, 4)

        result = run_until_halt
        expect(result).to eq(:halt)

        # Destination should be at ES:DI = linear 0x2080
        expect(read_byte(memory, 0x2080)).to eq(0xAA)
        expect(read_byte(memory, 0x2081)).to eq(0xBB)
        expect(read_byte(memory, 0x2082)).to eq(0xCC)
        expect(read_byte(memory, 0x2083)).to eq(0xDD)

        # Should NOT have written to DS:0x80 = linear 0x1080
        expect(memory[0x1080]).to be_nil
      end
    end

    describe 'STOSB uses ES:DI for destination' do
      it 'stores AL to ES:DI, not DS:DI' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x1000)
        pipeline.set_es_base(0x2000)
        pipeline.set_reg(:eax, 0x42)
        pipeline.set_reg(:edi, 0x0090)
        pipeline.set_reg(:ecx, 3)
        pipeline.set_flag(:df, 0)

        write_code(memory, 0x0100,
          0xF3, 0xAA,  # REP STOSB
          0xF4          # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)

        # Should write to ES:DI = linear 0x2090
        expect(read_byte(memory, 0x2090)).to eq(0x42)
        expect(read_byte(memory, 0x2091)).to eq(0x42)
        expect(read_byte(memory, 0x2092)).to eq(0x42)
        # Should NOT write to DS:0x90 = linear 0x1090
        expect(memory[0x1090]).to be_nil
      end
    end

    describe 'SCASB uses ES:DI for comparison' do
      it 'compares AL against ES:DI, not DS:DI' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x1000)
        pipeline.set_es_base(0x2000)
        pipeline.set_reg(:eax, 0x42)
        pipeline.set_reg(:edi, 0x0050)
        pipeline.set_flag(:df, 0)

        # Put 0x42 at ES:DI=0x2050, different value at DS:DI=0x1050
        memory[0x2050] = 0x42
        memory[0x1050] = 0xFF

        write_code(memory, 0x0100,
          0xAE,  # SCASB
          0xF4   # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        # ZF should be set (AL == ES:[DI])
        expect(pipeline.reg(:zflag)).to eq(1)
      end
    end

    describe 'INT pushes correct CS selector' do
      it 'pushes the actual CS selector, not zero' do
        # Set CS selector to 0x1234 (CS base = 0x12340)
        pipeline.setup_real_mode(cs_base: 0x12340, eip: 0x0010, esp: 0xFFFE)
        pipeline.set_reg(:cs, 0x1234)

        # Set up IVT entry for INT 0x21 at vector 0x21*4 = 0x84
        # Handler at 0x0000:0x0200
        write_word(memory, 0x84, 0x0200)  # offset
        write_word(memory, 0x86, 0x0000)  # segment

        # Handler: IRET
        write_code(memory, 0x0200, 0xCF)  # IRET

        # Code at CS:IP = 0x12340 + 0x0010 = 0x12350
        write_code(memory, 0x12350,
          0xCD, 0x21,  # INT 21h
          0xF4          # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)

        # After IRET, should return to same CS:IP
        # Check that CS selector was restored correctly
        expect(pipeline.reg(:cs)).to eq(0x1234)

        # Verify the pushed CS was 0x1234 (check stack)
        # Stack was at 0xFFFE, after INT: SP -= 6 (FLAGS, CS, IP)
        # CS was pushed at SP+2 = 0xFFF8 + 2 = 0xFFFA
        # But with SS base = 0, stack is at linear 0xFFF8
        pushed_cs = read_word(memory, 0xFFFA)
        expect(pushed_cs).to eq(0x1234)
      end
    end
  end

  # --- Phase 3: Missing Instructions ---

  describe 'missing instructions' do
    describe 'CALL indirect near (0xFF /2)' do
      it 'calls through a register' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ebx, 0x0200)

        # Subroutine at 0x0200: MOV AX, 0x42; RET
        write_code(memory, 0x0200,
          0xB8, 0x42, 0x00,  # MOV AX, 0x42
          0xC3                # RET
        )

        write_code(memory, 0x0100,
          0xFF, 0xD3,  # CALL BX (FF /2 reg=BX)
          0xF4          # HLT (return target)
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x42)
      end

      it 'calls through a memory operand' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

        # Store target address 0x0300 at DS:[0x0050]
        write_word(memory, 0x0050, 0x0300)

        # Subroutine at 0x0300: MOV AX, 0x99; RET
        write_code(memory, 0x0300,
          0xB8, 0x99, 0x00,  # MOV AX, 0x99
          0xC3                # RET
        )

        write_code(memory, 0x0100,
          0xFF, 0x16, 0x50, 0x00,  # CALL [0x0050] (FF /2 with mod=00, rm=110 disp16)
          0xF4                      # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x99)
      end
    end

    describe 'CALL far direct (0x9A)' do
      it 'calls a far procedure and returns via RETF' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

        # Far procedure at 0x2000:0x0010 = linear 0x20010
        write_code(memory, 0x20010,
          0xB8, 0x77, 0x00,  # MOV AX, 0x77
          0xCB                # RETF
        )

        write_code(memory, 0x0100,
          0x9A, 0x10, 0x00, 0x00, 0x20,  # CALL FAR 2000:0010
          0xF4                             # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x77)
        expect(pipeline.reg(:cs)).to eq(0x0000)  # returned to original CS
      end
    end

    describe 'RET far (0xCB/0xCA)' do
      it 'returns from a far call restoring CS:IP' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

        # Simulate having CALL FAR pushed 0000:0105 (return address)
        # and we're now at 0x3000:0x0020 = linear 0x30020
        pipeline.setup_real_mode(cs_base: 0x30000, eip: 0x0020, esp: 0xFFFA)
        pipeline.set_reg(:cs, 0x3000)

        # Push return address onto stack: IP=0x0105, CS=0x0000
        write_word(memory, 0xFFFA, 0x0105)  # IP
        write_word(memory, 0xFFFC, 0x0000)  # CS

        # Code at 0x30020: RETF
        write_code(memory, 0x30020, 0xCB)  # RETF

        # Return target at 0x0000:0x0105 = linear 0x0105
        write_code(memory, 0x0105, 0xF4)  # HLT

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:cs)).to eq(0x0000)
      end
    end

    describe 'RET near with imm16 (0xC2)' do
      it 'pops IP and adjusts SP by imm16' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0200, esp: 0xFFF8)

        # Stack: return addr at 0xFFF8, then 4 bytes of args above
        write_word(memory, 0xFFF8, 0x0100)  # return IP

        # RET 4 — pop IP, then SP += 4
        write_code(memory, 0x0200,
          0xC2, 0x04, 0x00,  # RET 4
        )
        write_code(memory, 0x0100, 0xF4) # HLT at return target

        result = run_until_halt
        expect(result).to eq(:halt)
        # SP should be 0xFFF8 + 2 (pop IP) + 4 (imm16) = 0xFFFE
        expect(pipeline.reg(:esp) & 0xFFFF).to eq(0xFFFE)
      end
    end

    describe 'JMP indirect near (0xFF /4)' do
      it 'jumps to address in register' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ebx, 0x0200)

        write_code(memory, 0x0200,
          0xB8, 0x55, 0x00,  # MOV AX, 0x55
          0xF4                # HLT
        )

        write_code(memory, 0x0100,
          0xFF, 0xE3,  # JMP BX (FF /4 reg=BX)
          0xF4          # HLT (should not reach)
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x55)
      end

      it 'jumps to address in memory' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

        write_word(memory, 0x0050, 0x0300)

        write_code(memory, 0x0300,
          0xB8, 0x66, 0x00,  # MOV AX, 0x66
          0xF4                # HLT
        )

        write_code(memory, 0x0100,
          0xFF, 0x26, 0x50, 0x00,  # JMP [0x0050]
          0xF4                      # HLT (should not reach)
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x66)
      end
    end

    describe 'JMP far indirect (0xFF /5)' do
      it 'jumps to far address from memory' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)

        # Far pointer at [0x0050]: offset=0x0010, segment=0x2000
        write_word(memory, 0x0050, 0x0010)  # offset
        write_word(memory, 0x0052, 0x2000)  # segment

        write_code(memory, 0x20010,
          0xB8, 0x88, 0x00,  # MOV AX, 0x88
          0xF4                # HLT
        )

        write_code(memory, 0x0100,
          0xFF, 0x2E, 0x50, 0x00,  # JMP FAR [0x0050] (FF /5 mod=00 rm=110)
          0xF4                      # HLT (should not reach)
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x88)
        expect(pipeline.reg(:cs)).to eq(0x2000)
      end
    end

    describe 'PUSH/POP segment registers' do
      it 'PUSH ES + POP ES round-trips the segment selector' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:es, 0x1234)
        pipeline.set_es_base(0x12340)

        write_code(memory, 0x0100,
          0x06,        # PUSH ES
          0x31, 0xC0,  # XOR AX, AX — (just to take some steps)
          0x07,        # POP ES
          0xF4          # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:es)).to eq(0x1234)
      end

      it 'PUSH DS; POP ES transfers a segment selector' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ds, 0x5678)
        pipeline.set_ds_base(0x56780)
        pipeline.set_reg(:es, 0x0000)
        pipeline.set_es_base(0x0000)

        write_code(memory, 0x0100,
          0x1E,  # PUSH DS
          0x07,  # POP ES
          0xF4   # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:es)).to eq(0x5678)
      end

      it 'PUSH CS works' do
        pipeline.setup_real_mode(cs_base: 0xABCD0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:cs, 0xABCD)

        write_code(memory, 0xABCD0 + 0x0100,
          0x0E,  # PUSH CS
          0xF4   # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        # CS should be on the stack
        pushed = read_word(memory, 0xFFFC)
        expect(pushed).to eq(0xABCD)
      end

      it 'PUSH SS + POP SS round-trips' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ss, 0x4000)

        write_code(memory, 0x0100,
          0x16,  # PUSH SS
          0x17,  # POP SS
          0xF4   # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:ss)).to eq(0x4000)
      end
    end

    describe 'MOV from segment register (0x8C)' do
      it 'MOV AX, ES copies ES selector to AX' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:es, 0x9ABC)
        pipeline.set_es_base(0x9ABC0)

        write_code(memory, 0x0100,
          0x8C, 0xC0,  # MOV AX, ES (8C /0 mod=11 rm=000)
          0xF4          # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x9ABC)
      end

      it 'MOV [addr], DS stores DS selector to memory' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ds, 0x1111)
        pipeline.set_ds_base(0x11110)

        write_code(memory, 0x0100,
          0x8C, 0x1E, 0x00, 0x50,  # MOV [5000h], DS (8C /3 mod=00 rm=110 disp16)
          0xF4                      # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        # Read from DS:[5000h] = linear 0x11110 + 0x5000 = 0x16110
        expect(read_word(memory, 0x16110)).to eq(0x1111)
      end
    end

    describe 'LES (0xC4)' do
      it 'loads a far pointer into ES:reg' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x0000)

        # Far pointer at [0x0050]: offset=0x1234, segment=0x5678
        write_word(memory, 0x0050, 0x1234)
        write_word(memory, 0x0052, 0x5678)

        write_code(memory, 0x0100,
          0xC4, 0x3E, 0x50, 0x00,  # LES DI, [0x0050]
          0xF4                      # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:edi) & 0xFFFF).to eq(0x1234)
        expect(pipeline.reg(:es)).to eq(0x5678)
      end
    end

    describe 'LDS (0xC5)' do
      it 'loads a far pointer into DS:reg' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x0000)

        # Far pointer at [0x0060]: offset=0xAAAA, segment=0x3000
        write_word(memory, 0x0060, 0xAAAA)
        write_word(memory, 0x0062, 0x3000)

        write_code(memory, 0x0100,
          0xC5, 0x36, 0x60, 0x00,  # LDS SI, [0x0060]
          0xF4                      # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:esi) & 0xFFFF).to eq(0xAAAA)
        expect(pipeline.reg(:ds)).to eq(0x3000)
      end
    end

    describe 'TEST r/m, imm (0xF6/0xF7 /0)' do
      it 'TEST byte [mem], imm8 sets ZF when AND is zero' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_ds_base(0x0000)

        memory[0x0050] = 0xF0

        write_code(memory, 0x0100,
          0xF6, 0x06, 0x50, 0x00, 0x0F,  # TEST BYTE [0x50], 0x0F
          0xF4                             # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        # 0xF0 & 0x0F = 0, so ZF should be set
        expect(pipeline.reg(:zflag)).to eq(1) # ZF
      end

      it 'TEST word reg, imm16 clears ZF when AND is non-zero' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:eax, 0x1234)

        write_code(memory, 0x0100,
          0xF7, 0xC0, 0x04, 0x00,  # TEST AX, 0x0004
          0xF4                      # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        # 0x1234 & 0x0004 = 0x0004 != 0, ZF should be clear
        expect(pipeline.reg(:zflag)).to eq(0) # ZF clear
      end
    end

    describe 'IMUL two-operand (0x0F 0xAF)' do
      it 'IMUL BX, CX multiplies and stores in destination' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ebx, 7)
        pipeline.set_reg(:ecx, 6)

        write_code(memory, 0x0100,
          0x0F, 0xAF, 0xD9,  # IMUL BX, CX
          0xF4                # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:ebx) & 0xFFFF).to eq(42)
      end
    end

    describe 'IMUL three-operand (0x6B imm8, 0x69 imm16)' do
      it 'IMUL BX, CX, imm8 multiplies with immediate' do
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ecx, 10)

        write_code(memory, 0x0100,
          0x6B, 0xD9, 0x05,  # IMUL BX, CX, 5
          0xF4                # HLT
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:ebx) & 0xFFFF).to eq(50)
      end
    end

    describe 'end-to-end: real-mode far call with segment push/pop' do
      it 'simulates a BIOS-like far call and return' do
        # Set up CS=0, DS=0x1000, ES=0x2000, SS=0
        pipeline.setup_real_mode(cs_base: 0, eip: 0x0100, esp: 0xFFFE)
        pipeline.set_reg(:ds, 0x1000)
        pipeline.set_ds_base(0x10000)
        pipeline.set_reg(:es, 0x2000)
        pipeline.set_es_base(0x20000)

        # Main code at 0:0100
        # PUSH DS; PUSH ES; CALL FAR 3000:0010; POP ES; POP DS; HLT
        write_code(memory, 0x0100,
          0x1E,                              # PUSH DS
          0x06,                              # PUSH ES
          0x9A, 0x10, 0x00, 0x00, 0x30,      # CALL FAR 3000:0010
          0x07,                              # POP ES
          0x1F,                              # POP DS
          0xF4                               # HLT
        )

        # Far procedure at 3000:0010 = linear 0x30010
        # MOV AX, 0xBEEF; RETF
        write_code(memory, 0x30010,
          0xB8, 0xEF, 0xBE,  # MOV AX, 0xBEEF
          0xCB                # RETF
        )

        result = run_until_halt
        expect(result).to eq(:halt)
        expect(pipeline.reg(:eax) & 0xFFFF).to eq(0xBEEF)
        expect(pipeline.reg(:ds)).to eq(0x1000)
        expect(pipeline.reg(:es)).to eq(0x2000)
        expect(pipeline.reg(:cs)).to eq(0x0000)
      end
    end
  end
end
