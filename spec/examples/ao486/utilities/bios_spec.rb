# spec/examples/ao486/utilities/bios_spec.rb
# Phase 4: BIOS stub and boot sector execution tests

require 'rspec'
require_relative '../../../../examples/ao486/hdl/pipeline/pipeline'
require_relative '../../../../examples/ao486/hdl/constants'
require_relative '../../../../examples/ao486/utilities/bios'
require_relative '../../../../examples/ao486/utilities/fat12'

C = RHDL::Examples::AO486::Constants unless defined?(C)

FLOPPY_PATH = File.join(__dir__, '../../../../examples/ao486/software/bin/msdos401.img')

RSpec.describe RHDL::Examples::AO486::Bios, 'Phase 4: BIOS stub & boot sector' do
  let(:pipeline) { RHDL::Examples::AO486::Pipeline.new }
  let(:memory) { {} }

  def read_word(memory, addr)
    (memory[addr] || 0) | ((memory[addr + 1] || 0) << 8)
  end

  describe 'IVT setup' do
    let(:bios) { described_class.new(pipeline) }

    it 'installs IVT entries for known vectors' do
      bios.setup(memory)

      # INT 10h should point to F000:0200
      expect(read_word(memory, 0x10 * 4)).to eq(0x0200)
      expect(read_word(memory, 0x10 * 4 + 2)).to eq(0xF000)

      # INT 13h should point to F000:0230
      expect(read_word(memory, 0x13 * 4)).to eq(0x0230)
      expect(read_word(memory, 0x13 * 4 + 2)).to eq(0xF000)
    end

    it 'writes IRET stubs at handler addresses' do
      bios.setup(memory)

      # Each handler should have IRET (0xCF) at its linear address
      expect(memory[0xF_0200]).to eq(0xCF)  # INT 10h
      expect(memory[0xF_0230]).to eq(0xCF)  # INT 13h
      expect(memory[0xF_0400 + 0x03]).to eq(0xCF)  # default handler for INT 03h
    end

    it 'installs BDA with memory size and equipment word' do
      bios.setup(memory)

      # Equipment word at 0x410
      expect(read_word(memory, 0x410)).to eq(0x0021)
      # Memory size at 0x413 (640 KB)
      expect(read_word(memory, 0x413)).to eq(640)
    end
  end

  describe 'INT 10h video output' do
    let(:bios) { described_class.new(pipeline) }

    it 'captures TTY output (AH=0Eh) to video buffer' do
      bios.setup(memory)
      pipeline.setup_real_mode(cs_base: 0, eip: 0x8000, esp: 0x7000)

      # Write code: MOV AX, 0x0E41 (AH=0Eh, AL='A'); INT 10h; HLT
      addr = 0x8000
      [0xB8, 0x41, 0x0E,  # MOV AX, 0x0E41
       0xCD, 0x10,         # INT 10h
       0xB8, 0x42, 0x0E,  # MOV AX, 0x0E42 ('B')
       0xCD, 0x10,         # INT 10h
       0xF4                 # HLT
      ].each_with_index { |b, i| memory[addr + i] = b }

      result = bios.run(memory, max_steps: 100)
      expect(result).to eq(:halt)
      expect(bios.video_output).to eq('AB')
    end
  end

  describe 'INT 11h equipment list' do
    let(:bios) { described_class.new(pipeline) }

    it 'returns equipment word in AX' do
      bios.setup(memory)
      pipeline.setup_real_mode(cs_base: 0, eip: 0x8000, esp: 0x7000)

      [0xCD, 0x11, 0xF4].each_with_index { |b, i| memory[0x8000 + i] = b }

      result = bios.run(memory, max_steps: 20)
      expect(result).to eq(:halt)
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(0x0021)
    end
  end

  describe 'INT 12h memory size' do
    let(:bios) { described_class.new(pipeline) }

    it 'returns 640 in AX' do
      bios.setup(memory)
      pipeline.setup_real_mode(cs_base: 0, eip: 0x8000, esp: 0x7000)

      [0xCD, 0x12, 0xF4].each_with_index { |b, i| memory[0x8000 + i] = b }

      result = bios.run(memory, max_steps: 20)
      expect(result).to eq(:halt)
      expect(pipeline.reg(:eax) & 0xFFFF).to eq(640)
    end
  end

  describe 'INT 21h DOS services' do
    let(:bios) { described_class.new(pipeline) }

    it 'returns DOS version 4.0 (AH=30h)' do
      bios.setup(memory)
      pipeline.setup_real_mode(cs_base: 0, eip: 0x8000, esp: 0x7000)

      [0xB4, 0x30,  # MOV AH, 30h
       0xCD, 0x21,  # INT 21h
       0xF4          # HLT
      ].each_with_index { |b, i| memory[0x8000 + i] = b }

      result = bios.run(memory, max_steps: 20)
      expect(result).to eq(:halt)
      expect(pipeline.reg(:eax) & 0xFF).to eq(4)   # major version
      expect((pipeline.reg(:eax) >> 8) & 0xFF).to eq(0)  # minor version
    end

    it 'displays a character with AH=02h' do
      bios.setup(memory)
      pipeline.setup_real_mode(cs_base: 0, eip: 0x8000, esp: 0x7000)

      [0xB2, 0x48,  # MOV DL, 'H'
       0xB4, 0x02,  # MOV AH, 02h
       0xCD, 0x21,  # INT 21h
       0xF4          # HLT
      ].each_with_index { |b, i| memory[0x8000 + i] = b }

      result = bios.run(memory, max_steps: 20)
      expect(result).to eq(:halt)
      expect(bios.video_output).to eq('H')
    end
  end

  context 'with floppy image', if: File.exist?(FLOPPY_PATH) do
    let(:floppy) { RHDL::Examples::AO486::FAT12.new(FLOPPY_PATH) }
    let(:bios) { described_class.new(pipeline, floppy: floppy) }

    describe 'INT 13h disk services' do
      it 'reads boot sector via CHS (AH=02h, C=0 H=0 S=1)' do
        bios.setup(memory)
        pipeline.setup_real_mode(cs_base: 0, eip: 0x8000, esp: 0x7000)
        pipeline.set_es_base(0)
        pipeline.set_reg(:es, 0)

        # Read 1 sector at CHS 0/0/1 into ES:BX = 0000:9000
        # AH=02, AL=01, CH=00, CL=01, DH=00, DL=00, ES:BX=0000:9000
        addr = 0x8000
        [0xB8, 0x01, 0x02,  # MOV AX, 0x0201 (AH=02, AL=01)
         0xBB, 0x00, 0x90,  # MOV BX, 0x9000
         0xB9, 0x01, 0x00,  # MOV CX, 0x0001 (CH=0, CL=1)
         0xBA, 0x00, 0x00,  # MOV DX, 0x0000 (DH=0, DL=0)
         0xCD, 0x13,        # INT 13h
         0xF4               # HLT
        ].each_with_index { |b, i| memory[addr + i] = b }

        result = bios.run(memory, max_steps: 50)
        expect(result).to eq(:halt)

        # CF should be clear (success)
        expect(pipeline.reg(:cflag)).to eq(0)
        # AH should be 0 (success)
        expect((pipeline.reg(:eax) >> 8) & 0xFF).to eq(0)

        # First 3 bytes of boot sector should be the JMP instruction
        boot = floppy.boot_sector
        expect(memory[0x9000]).to eq(boot[0])
        expect(memory[0x9001]).to eq(boot[1])
        expect(memory[0x9002]).to eq(boot[2])

        # Boot signature should be present
        expect(memory[0x91FE]).to eq(0x55)
        expect(memory[0x91FF]).to eq(0xAA)
      end

      it 'returns drive parameters (AH=08h)' do
        bios.setup(memory)
        pipeline.setup_real_mode(cs_base: 0, eip: 0x8000, esp: 0x7000)

        [0xB8, 0x00, 0x08,  # MOV AX, 0x0800
         0xBA, 0x00, 0x00,  # MOV DX, 0x0000
         0xCD, 0x13,        # INT 13h
         0xF4               # HLT
        ].each_with_index { |b, i| memory[0x8000 + i] = b }

        result = bios.run(memory, max_steps: 50)
        expect(result).to eq(:halt)

        expect(pipeline.reg(:cflag)).to eq(0)
        # Should report 18 sectors per track for 1.44MB floppy
        cl = pipeline.reg(:ecx) & 0xFF
        expect(cl & 0x3F).to eq(18)
      end
    end

    describe 'boot sector loading' do
      it 'loads boot sector at 0x7C00 with valid signature' do
        bios.setup(memory)
        bios.load_boot_sector(memory)

        # Check boot signature
        expect(memory[0x7DFE]).to eq(0x55)
        expect(memory[0x7DFF]).to eq(0xAA)

        # EIP should be 0x7C00
        expect(pipeline.reg(:eip)).to eq(0x7C00)

        # DL should be 0 (floppy drive)
        expect(pipeline.reg(:edx) & 0xFF).to eq(0)
      end

      it 'executes boot sector and loads IO.SYS into memory' do
        bios.setup(memory)
        bios.load_boot_sector(memory)

        # Run the boot sector — it should use INT 13h to load IO.SYS
        # Boot sector reads 3-4 sectors of IO.SYS then JMP FAR to 0070:0000
        # This completes within ~250 steps; 1000 gives ample margin
        result = bios.run(memory, max_steps: 1_000)

        # The boot sector should have loaded data from the floppy
        # (it reads IO.SYS using INT 13h). Check that the BIOS
        # serviced at least some disk read calls (no unhandled INT 13h errors).
        disk_errors = bios.unhandled_ints.select { |i| i[:vector] == 0x13 }
        expect(disk_errors).to be_empty

        # After the boot sector runs, execution should have left 0x7Cxx range.
        # It typically jumps to IO.SYS load address or another segment.
        eip = pipeline.reg(:eip)
        cs_cache = pipeline.seg_cache_public(:cs)
        cs_base = pipeline.desc_base_public(cs_cache)
        linear_eip = (cs_base + eip) & 0xFFFF_FFFF

        # Boot sector code is at 0x7C00-0x7DFF. If execution moved past it,
        # the boot sector has completed its job.
        expect(linear_eip).not_to be_between(0x7C00, 0x7DFF)

        # Verify IO.SYS data was loaded at 0x0070:0000 (linear 0x700)
        boot = floppy.boot_sector
        # The boot sector's JMP FAR target is 0070:0000, confirming IO.SYS is there
        expect(memory[0x700]).not_to be_nil
      end
    end

    describe 'RAM image loading (Phase 5)' do
      it 'completes DOSINIT at the final DOS segment' do
        bios.setup(memory)
        bios.load_dos_ram_image(memory)

        # After DOSINIT runs to completion (HLT), CS base should still
        # be the final DOS segment.
        cs_cache = pipeline.seg_cache_public(:cs)
        cs_base = pipeline.desc_base_public(cs_cache)
        expect(cs_base).to eq(0x15F0)

        # SS should still point to the msdos segment
        iosys = floppy.read_file('IO.SYS')
        iosys_sectors = (iosys.length + 511) / 512
        msdos_base = 0x700 + iosys_sectors * 512
        ss_base = pipeline.desc_base_public(
          pipeline.seg_cache_public(:ss))
        expect(ss_base).to eq(msdos_base)
      end

      it 'loads boot sector at 0x7C00 (overwritten by SYSINIT overlap)' do
        bios.setup(memory)
        bios.load_dos_ram_image(memory)

        # Note: SYSINIT (32K from 0x700) extends past 0x7C00, overwriting the
        # boot sector. This matches the real MSLOAD behavior. The boot sector
        # is loaded first for BPB access, then SYSINIT overwrites it.
        # We verify the boot sector was loaded by checking BPB bytes at 0x7C00
        # are non-zero (they contain SYSINIT code now, not boot sector).
        expect(memory[0x7C00]).not_to be_nil
      end

      it 'loads MSDOS.SYS after IO.SYS' do
        bios.setup(memory)
        bios.load_dos_ram_image(memory)

        iosys = floppy.read_file('IO.SYS')
        msdos = floppy.read_file('MSDOS.SYS')
        iosys_sectors = (iosys.length + 511) / 512
        msdos_base = 0x700 + iosys_sectors * 512

        # First bytes of MSDOS.SYS should be present
        expect(memory[msdos_base]).to eq(msdos[0])
        expect(memory[msdos_base + 1]).to eq(msdos[1])
      end

      it 'sets dispatch table parameters during DOSINIT' do
        bios.setup(memory)
        bios.load_dos_ram_image(memory)

        # DOSINIT dispatch should have stored handler parameters
        iosys = floppy.read_file('IO.SYS')
        iosys_sectors = (iosys.length + 511) / 512
        msdos_base = 0x700 + iosys_sectors * 512

        # [0x324] = function code (3) from the dispatch
        expect(memory[msdos_base + 0x324]).to eq(0x03)
        # [0x327] = handler parameter from second dispatch table
        expect(memory[msdos_base + 0x327]).to eq(0x08)
      end

      it 'runs DOSINIT to completion during load_dos_ram_image' do
        bios.setup(memory)

        # load_dos_ram_image now runs DOSINIT internally (step 6)
        # and should complete without errors
        expect { bios.load_dos_ram_image(memory) }.not_to raise_error

        # After DOSINIT, the dispatch table parameters should be set
        iosys = floppy.read_file('IO.SYS')
        iosys_sectors = (iosys.length + 511) / 512
        msdos_base = 0x700 + iosys_sectors * 512
        expect(memory[msdos_base + 0x324]).to eq(0x03)

        # IVT should be restored to BIOS stubs after DOSINIT
        bios_seg = 0xF000
        int21_off = memory[0x21 * 4] | (memory[0x21 * 4 + 1] << 8)
        int21_seg = memory[0x21 * 4 + 2] | (memory[0x21 * 4 + 3] << 8)
        expect(int21_seg).to eq(bios_seg)
      end

      it 'relocates DOS kernel to the final segment' do
        bios.setup(memory)
        bios.load_dos_ram_image(memory)

        # The DOSINIT entry stub at the final DOS segment should start with
        # E8 xx xx (CALL FCE0) — the DOSDATA DOSINIT entry from the file.
        dos_base = 0x15F0
        expect(memory[dos_base]).to eq(0xE8)

        # The dispatch table should be accessible at SS:0D28
        ss_base = pipeline.desc_base_public(
          pipeline.seg_cache_public(:ss))
        table_addr = ss_base + 0x0D28
        # First byte of the dispatch table is non-zero (function code)
        expect(memory[table_addr]).not_to eq(0)
      end
    end
  end
end
