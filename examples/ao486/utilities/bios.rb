# frozen_string_literal: true

require_relative 'fat12'

module RHDL
  module Examples
    module AO486
      # Minimal BIOS stub for MS-DOS boot testing.
      # Installs IVT handlers as IRET stubs in the F000 segment,
      # intercepts INT calls via EIP detection, and dispatches to
      # Ruby handlers that modify CPU state before IRET returns.
      class Bios
        C = Constants

        BIOS_SEG  = 0xF000
        BIOS_BASE = 0xF_0000  # BIOS_SEG << 4

        # Handler offsets within BIOS segment (each stub is just IRET)
        HANDLER_OFFSETS = {
          0x00 => 0x0100,  # Divide error
          0x08 => 0x0110,  # IRQ0 (timer)
          0x09 => 0x0120,  # IRQ1 (keyboard)
          0x10 => 0x0200,  # Video services
          0x11 => 0x0210,  # Equipment list
          0x12 => 0x0220,  # Memory size
          0x13 => 0x0230,  # Disk services
          0x14 => 0x0290,  # Serial port services
          0x15 => 0x0240,  # System services
          0x16 => 0x0250,  # Keyboard services
          0x17 => 0x02A0,  # Printer services
          0x19 => 0x0260,  # Bootstrap loader
          0x1A => 0x0270,  # Time services
          0x21 => 0x0280,  # DOS services (will be replaced by IO.SYS)
        }.freeze

        # Default handlers: each vector gets a unique address 0x0400+vec
        # so we can identify which vector triggered the handler.
        DEFAULT_HANDLER_BASE = 0x0400

        # Offset of Total_Length label in MS-DOS 4.01 IO.SYS (MSLOAD/SYSINIT boundary).
        # MSLOAD occupies bytes 0..MSLOAD_SIZE-1; SYSINIT starts at MSLOAD_SIZE.
        # Determined by searching for the Keep_Loaded_BIO relocation pattern:
        #   B8 70 00 8E D8 8E C0 BE [Total_Length LE16]
        MSLOAD_SIZE = 0x55F

        attr_reader :video_buffer, :unhandled_ints, :pipeline, :floppy

        def initialize(pipeline, floppy: nil)
          @pipeline = pipeline
          @floppy = floppy.is_a?(FAT12) ? floppy : (floppy ? FAT12.new(floppy) : nil)
          @video_buffer = []
          @tick_count = 0
          @unhandled_ints = []
          @handler_linear_addrs = {}
          @msdos_range = nil
        end

        # Install IVT, BDA, and BIOS stubs into memory.
        def setup(memory)
          install_ivt(memory)
          install_bda(memory)
        end

        # Load the floppy boot sector at 0x7C00 and set initial boot state.
        def load_boot_sector(memory, drive: 0x00)
          raise 'No floppy image loaded' unless @floppy

          boot = @floppy.boot_sector
          boot.each_with_index { |b, i| memory[0x7C00 + i] = b & 0xFF }

          # Standard boot state: CS:IP = 0:7C00, DL = drive, stack below boot sector
          @pipeline.setup_real_mode(cs_base: 0, eip: 0x7C00, esp: 0x7C00)
          @pipeline.set_reg(:edx, drive & 0xFF)
          # DS = ES = SS = 0
          @pipeline.set_ds_base(0)
          @pipeline.set_es_base(0)
          @pipeline.set_reg(:ds, 0)
          @pipeline.set_reg(:es, 0)
          @pipeline.set_reg(:ss, 0)
        end

        # Pre-load DOS system files into memory as a RAM image, bypassing
        # the MSLOAD disk-reading loop.  Sets CPU state to begin execution
        # at IO.SYS SYSINIT entry point (0x0070:0000).
        #
        # This replicates what MSLOAD's Keep_Loaded_BIO procedure does:
        #   1. Copy IO.SYS[MSLOAD_SIZE..] (the SYSINIT/MSBIO code) to 0x70:0
        #   2. Load MSDOS.SYS right after the full IO.SYS position
        #   3. Set registers per GO_IBMBIO and JMP FAR 0070:0000
        #
        # Memory layout (matches post-MSLOAD state):
        #   0x0000:0000 - 0x0000:03FF  IVT
        #   0x0000:0400 - 0x0000:04FF  BDA
        #   0x0000:7C00 - 0x0000:7DFF  Boot sector (for BPB access)
        #   0x0070:0000 -              SYSINIT code (IO.SYS minus MSLOAD)
        #   0x0070:xxxx -              MSDOS.SYS (at full IO.SYS length offset)
        def load_dos_ram_image(memory, drive: 0x00)
          raise 'No floppy image loaded' unless @floppy

          # 1. Load boot sector at 0x7C00 (SYSINIT reads BPB values from here)
          boot = @floppy.boot_sector
          boot.each_with_index { |b, i| memory[0x7C00 + i] = b & 0xFF }

          # 2. Load IO.SYS SYSINIT portion at 0x0070:0000 (linear 0x700)
          #    MSLOAD's Keep_Loaded_BIO copies from offset Total_Length to 0x70:0,
          #    effectively stripping the MSLOAD loader and placing SYSINIT at 0x70:0.
          iosys = @floppy.read_file('IO.SYS')
          raise 'IO.SYS not found on floppy' unless iosys
          sysinit = iosys[MSLOAD_SIZE..]
          sysinit.each_with_index { |b, i| memory[0x700 + i] = b & 0xFF }

          # 3. Load MSDOS.SYS where MSLOAD would have placed it:
          #    right after the full IO.SYS, sector-aligned.
          #    MSLOAD reads IO.SYS by sectors, so the in-memory size is
          #    ceil(IO.SYS / 512) * 512.  MSDOS.SYS follows immediately.
          msdos = @floppy.read_file('MSDOS.SYS')
          if msdos
            iosys_sectors = (iosys.length + 511) / 512
            msdos_base = 0x700 + iosys_sectors * 512
            msdos.each_with_index { |b, i| memory[msdos_base + i] = b & 0xFF }
            @msdos_range = msdos_base..(msdos_base + msdos.length - 1)
          end

          # 3a. Run MSDOS.SYS first-phase init.
          #
          #     In the real boot, MSLOAD CALL FARs to the MSDOS.SYS entry point
          #     (file offset 0x8D31).  The first-phase init sets up the NUL device
          #     header, SysVars, MSBIO flags, the shadow code region for the REP
          #     MOVSW relocation, and device driver dispatch tables, then RETFs
          #     back to MSLOAD.
          #
          #     We run this init natively instead of emulating its side-effects.
          #     A far return address on the initial stack points to a BIOS sentinel
          #     (HLT at BIOS_BASE + INIT_DONE_OFFSET).  When the init RETFs, we
          #     detect the HLT and proceed to step 4.
          #
          #     The init uses SS=CS=msdos_base and writes data at msdos_base+offset,
          #     but the DOS relocation reads from msdos_base+0x4900+offset.  We
          #     snapshot before init and relay only the changed bytes afterward.
          data_seg_offset = 0x4900
          pre_init_snapshot = nil
          if msdos
            # Snapshot the data area range before init so we can detect changes.
            pre_init_snapshot = Array.new(data_seg_offset) { |i| memory[msdos_base + i] || 0 }

            msdos_seg = msdos_base >> 4
            init_entry = 0x8D31
            init_sp = 0x7C00

            # Place a far return address on the stack: BIOS_SEG:INIT_DONE_OFFSET.
            # The init saves this SS:SP and restores it before RETF.
            init_done_offset = 0x02B0
            init_done_linear = BIOS_BASE + init_done_offset
            memory[init_done_linear] = 0xF4  # HLT sentinel
            ss_linear = msdos_base + init_sp
            memory[ss_linear + 0] = init_done_offset & 0xFF        # return IP low
            memory[ss_linear + 1] = (init_done_offset >> 8) & 0xFF # return IP high
            memory[ss_linear + 2] = BIOS_SEG & 0xFF                # return CS low
            memory[ss_linear + 3] = (BIOS_SEG >> 8) & 0xFF         # return CS high

            # CPU state for the entry point (mirrors MSLOAD's CALL FAR context):
            #   CS  = MSDOS.SYS segment
            #   EIP = 0x8D31 (file offset of entry point)
            #   DS  = 0x0070 (MSBIO/SYSINIT segment)
            #   SI  = 0x016E (offset of CONHEADER in MSBIO segment)
            #   DX  = drive number
            #   SS  = MSDOS.SYS segment, SP = 0x7C00
            @pipeline.setup_real_mode(cs_base: msdos_base, eip: init_entry,
                                      esp: init_sp)
            @pipeline.set_reg(:edx, drive & 0xFF)
            @pipeline.set_reg(:esi, 0x016E)
            @pipeline.set_reg(:ds, 0x0070)
            @pipeline.set_ds_base(0x700)
            @pipeline.set_reg(:es, 0x0070)
            @pipeline.set_es_base(0x700)
            @pipeline.set_reg(:ss, msdos_seg)
            @pipeline.send(:set_seg_base, :ss, C::SEGMENT_SS, msdos_base)

            # Run the first-phase init until it RETFs to the sentinel.
            10_000.times do
              result = step(memory)
              eip_now = @pipeline.reg(:eip)
              cs_now = @pipeline.desc_base_public(
                @pipeline.seg_cache_public(:cs))
              break if (cs_now + eip_now) & 0xFFFF_FFFF == init_done_linear
              break if result == :halt
            end

            # The first-phase init rewrites IVT entries to point at the
            # pre-relocation DOS kernel.  SYSINIT later uses INT 21h for
            # file operations (opening CONFIG.SYS).  Restore IVT to our
            # BIOS stubs so our Ruby handlers return clean errors.
            HANDLER_OFFSETS.each_key do |vec|
              write_ivt_entry(memory, vec, BIOS_SEG, HANDLER_OFFSETS[vec])
            end
          end

          # 3b. Pre-populate the relocation source for the REP MOVSW.
          #
          #     The DOS relocation copies 0xA000 bytes from DS:0 to ES:0 (the
          #     final DOS segment at ~0x15F0).  DS is set to msdos_base + 0x4900.
          #
          #     The relocation source low offsets (0x0000-0x48FF) keep the
          #     original DOSDATA code — the DOSINIT entry stub plus the full
          #     DOSINIT code body.  FCE0 (in the code shadow) calls into these
          #     offsets expecting DOSDATA functions (e.g. 1E32, 1A15), NOT the
          #     resident kernel DOSCODE code.  The DOSINIT dispatches themselves
          #     populate the SysVars/config data area; replacing it prematurely
          #     with DOSCODE templates would overwrite DOSINIT code and break
          #     the init call chain.
          #
          #     However, init-modified bytes at msdos_base (the DOSCODE area)
          #     must be relayed to the relocation source so that the DOSINIT
          #     entry stub (offsets 0x00-0x18) and other init-patched fields
          #     are present.
          if msdos
            # Relay first-phase init changes to the relocation source.
            # The init writes to msdos_base+offset (the DOSCODE area); the
            # relocation reads from msdos_base+0x4900+offset (DOSDATA area).
            if pre_init_snapshot
              data_seg_offset.times do |i|
                current = memory[msdos_base + i] || 0
                if current != pre_init_snapshot[i]
                  memory[msdos_base + data_seg_offset + i] = current
                end
              end
            end

            # Patch specific DOSCODE data fields that the code shadow reads
            # via CS: override.  The code shadow dispatch handler at CS:8DE5
            # executes `LDS SI, CS:[0584]` to load a device-driver chain
            # pointer.  In the DOSCODE template this is 00 00 00 00 (null),
            # but the DOSDATA area has init code bytes there.  Zero it so
            # the LDS loads a null pointer instead of garbage.
            4.times { |j| memory[msdos_base + data_seg_offset + 0x584 + j] = 0 }

            # Code area shadow: fill high DOS offsets from current memory.
            # The code shadow occupies relocation source offsets 0x7510+
            # (= msdos_base - 0x15F0).  After the REP MOVSW relocation,
            # CS:7510+ holds the resident kernel code from the DOSCODE area.
            ds_linear = msdos_base + data_seg_offset
            code_ip_start = msdos_base - 0x15F0
            shadow_base = ds_linear + code_ip_start
            code_len = [0xA000 - code_ip_start, msdos.length].min
            code_len.times do |i|
              memory[shadow_base + i] = memory[msdos_base + i] || 0
            end
          end

          # 4. Manual relocation (replaces SYSINIT's REP MOVSW).
          #
          #    In the real boot, SYSINIT relocates itself to high memory, then
          #    executes REP MOVSW to copy 0xA000 bytes from the relocation
          #    source (DS = msdos_base + 0x4900) to the final DOS segment
          #    (ES = 0x015F, linear 0x15F0).  SYSINIT sets SS to its own high
          #    segment before calling DOSINIT, but the DOSCODE dispatch code
          #    (in the code shadow at CS:8F25) does PUSH SS / POP DS to access
          #    data structures at SS:0D28+.  This fails when SS != msdos_seg
          #    because the dispatch table is at msdos_base + 0x0D28.
          #
          #    By performing the relocation ourselves we can set SS = msdos_seg,
          #    ensuring the dispatch table lookup reads from the right location.
          dos_seg = 0x015F
          dos_base = dos_seg << 4          # 0x15F0
          reloc_src = msdos_base + data_seg_offset  # relocation source base
          0xA000.times { |i| memory[dos_base + i] = memory[reloc_src + i] || 0 }

          # 5. Set CPU state for direct DOSINIT entry.
          #
          #    CS = final DOS segment (015F, linear 0x15F0).
          #    EIP = 0 (entry stub: CALL FCE0, which jumps to the DOSINIT
          #           dispatcher via the code shadow).
          #    SS = msdos_seg (0x8B0) so PUSH SS / POP DS gives access to the
          #         dispatch table at msdos_base + 0x0D28.
          #    DL = drive number (FCE0 checks it).
          #    ES = DOS segment (some init paths reference ES).
          msdos_seg = msdos_base >> 4
          @pipeline.setup_real_mode(cs_base: dos_base, eip: 0, esp: 0x7C00)
          @pipeline.set_reg(:edx, (drive & 0xFF) | 0xA000)
          @pipeline.set_reg(:ds, 0x0070)
          @pipeline.set_ds_base(0x700)
          @pipeline.set_reg(:es, dos_seg)
          @pipeline.set_es_base(dos_base)
          @pipeline.set_reg(:ss, msdos_seg)
          @pipeline.send(:set_seg_base, :ss, C::SEGMENT_SS, msdos_base)
        end

        # Execute one step with BIOS interception.
        # Checks if EIP is at a BIOS handler address before executing.
        def step(memory)
          eip = @pipeline.reg(:eip)
          cs_cache = @pipeline.seg_cache_public(:cs)
          cs_base = @pipeline.desc_base_public(cs_cache)
          linear = (cs_base + eip) & 0xFFFF_FFFF

          # If we're at a BIOS handler stub, run the Ruby handler first
          if @handler_linear_addrs.key?(linear)
            vector = @handler_linear_addrs[linear]
            dispatch_bios_handler(memory, vector)
          end

          # Now execute the actual x86 instruction (IRET for handlers, or normal)
          @pipeline.step(memory)
        end

        # Run until halt or max_steps exceeded.
        def run(memory, max_steps: 1_000_000)
          max_steps.times do
            result = step(memory)
            return result if result == :halt
          end
          :timeout
        end

        # The video output as a string.
        def video_output
          @video_buffer.join
        end

        private

        # ========== IVT & Stubs ==========

        def install_ivt(memory)
          # Each vector gets a unique handler address so we can identify it
          256.times do |vec|
            offset = HANDLER_OFFSETS[vec] || (DEFAULT_HANDLER_BASE + vec)
            write_ivt_entry(memory, vec, BIOS_SEG, offset)
            linear = BIOS_BASE + offset
            @handler_linear_addrs[linear] = vec
          end

          # Write IRET (0xCF) at each handler stub address
          all_offsets = HANDLER_OFFSETS.values + (0..255).map { |v| DEFAULT_HANDLER_BASE + v }
          all_offsets.uniq.each do |off|
            memory[BIOS_BASE + off] = 0xCF  # IRET
          end
        end

        def write_ivt_entry(memory, vector, segment, offset)
          addr = vector * 4
          memory[addr]     = offset & 0xFF
          memory[addr + 1] = (offset >> 8) & 0xFF
          memory[addr + 2] = segment & 0xFF
          memory[addr + 3] = (segment >> 8) & 0xFF
        end

        # ========== BIOS Data Area ==========

        # Standard 1.44MB 3.5" floppy disk parameter table (11 bytes)
        DISK_PARAM_TABLE = [
          0xDF, # SRT=D (step rate 3ms), HUT=F (240ms)
          0x02, # HLT=01 (4ms), DMA=0
          0x25, # Motor off delay (ticks)
          0x02, # Bytes per sector (2 = 512 bytes)
          0x12, # Sectors per track (18)
          0x1B, # Gap length
          0xFF, # Data length
          0x54, # Format gap length
          0xF6, # Format fill byte
          0x0F, # Head settle time (ms)
          0x08, # Motor start time (1/8 seconds)
        ].freeze

        DISK_PARAM_TABLE_OFFSET = 0x0600  # Disk parameter table location in BIOS segment

        def install_bda(memory)
          # BDA at 0x0040:0000 = linear 0x0400
          # Equipment word at 0x410
          mem_write16(memory, 0x410, 0x0021)  # 1 floppy, 80x25 color
          # Base memory size at 0x413 (in KB)
          mem_write16(memory, 0x413, 640)
          # Video mode at 0x449
          memory[0x449] = 0x03  # 80x25 color text
          # Video columns at 0x44A
          mem_write16(memory, 0x44A, 80)
          # Active video page at 0x462
          memory[0x462] = 0x00

          # Install disk parameter table at F000:0600
          DISK_PARAM_TABLE.each_with_index do |b, i|
            memory[BIOS_BASE + DISK_PARAM_TABLE_OFFSET + i] = b
          end
          # Point INT 0x1E to the disk parameter table
          write_ivt_entry(memory, 0x1E, BIOS_SEG, DISK_PARAM_TABLE_OFFSET)
        end

        # ========== INT Dispatch ==========

        def dispatch_bios_handler(memory, vector)
          case vector
          when 0x10 then handle_int10h(memory)
          when 0x11 then handle_int11h(memory)
          when 0x12 then handle_int12h(memory)
          when 0x13 then handle_int13h(memory)
          when 0x14 then handle_int14h(memory)
          when 0x15 then handle_int15h(memory)
          when 0x16 then handle_int16h(memory)
          when 0x17 then handle_int17h(memory)
          when 0x1A then handle_int1ah(memory)
          when 0x20 then handle_int20h(memory)
          when 0x21 then handle_int21h(memory)
          when 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
               0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
               0x1B, 0x1C, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77
            # Common hardware/system vectors — silently ignore (IRET handles it)
          else
            @unhandled_ints << { vector: vector, eip: @pipeline.reg(:eip) }
          end
        end

        # ========== INT 10h: Video Services ==========

        def handle_int10h(memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x00  # Set video mode
            # NOP — just acknowledge
          when 0x01  # Set cursor shape
            # NOP
          when 0x02  # Set cursor position
            # NOP
          when 0x03  # Get cursor position
            @pipeline.set_reg(:ecx, 0x0607)  # CH=start line, CL=end line
            @pipeline.set_reg(:edx, 0x0000)  # DH=row, DL=col
          when 0x06, 0x07  # Scroll up/down
            # NOP
          when 0x08  # Read character/attribute at cursor
            @pipeline.set_reg(:eax, 0x0720)  # AH=attr(white on black), AL=space
          when 0x09  # Write character/attribute at cursor
            al = @pipeline.reg(:eax) & 0xFF
            @video_buffer << al.chr
          when 0x0E  # TTY write character
            al = @pipeline.reg(:eax) & 0xFF
            @video_buffer << al.chr
          when 0x0F  # Get video mode
            @pipeline.set_reg(:eax, 0x5003)  # AH=80 cols, AL=mode 3
            @pipeline.set_reg(:ebx, (@pipeline.reg(:ebx) & 0xFF) | 0x0000)  # BH=page 0
          end
        end

        # ========== INT 11h: Equipment List ==========

        def handle_int11h(_memory)
          @pipeline.set_reg(:eax, 0x0021)  # 1 floppy, 80x25 color
        end

        # ========== INT 12h: Memory Size ==========

        def handle_int12h(_memory)
          @pipeline.set_reg(:eax, 640)  # 640 KB
        end

        # ========== INT 13h: Disk Services ==========

        def handle_int13h(memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x00  # Reset disk system
            set_return_cf(memory, 0)
            eax = @pipeline.reg(:eax)
            @pipeline.set_reg(:eax, (eax & 0x00FF))  # AH=0 (success)
          when 0x02  # Read sectors
            handle_disk_read(memory)
          when 0x03  # Write sectors (NOP for read-only floppy)
            set_return_cf(memory, 0)
            eax = @pipeline.reg(:eax)
            @pipeline.set_reg(:eax, (eax & 0x00FF))  # AH=0
          when 0x04  # Verify sectors
            set_return_cf(memory, 0)
            eax = @pipeline.reg(:eax)
            @pipeline.set_reg(:eax, (eax & 0x00FF))  # AH=0
          when 0x08  # Get drive parameters
            handle_disk_params(memory)
          when 0x15  # Get disk type
            # AH=1 (floppy without change-line), CF=0
            eax = @pipeline.reg(:eax)
            @pipeline.set_reg(:eax, (eax & 0x00FF) | (0x01 << 8))
            set_return_cf(memory, 0)
          else
            @unhandled_ints << { vector: 0x13, ah: ah }
            set_return_cf(memory, 1)
          end
        end

        def handle_disk_read(memory)
          eax = @pipeline.reg(:eax)
          ecx = @pipeline.reg(:ecx)
          edx = @pipeline.reg(:edx)
          al = eax & 0xFF          # sector count
          cl = ecx & 0xFF          # sector number (bits 0-5), cyl high (bits 6-7)
          ch = (ecx >> 8) & 0xFF   # cylinder low
          dh = (edx >> 8) & 0xFF   # head
          dl = edx & 0xFF          # drive

          sector   = cl & 0x3F
          cylinder = ch | ((cl & 0xC0) << 2)
          head     = dh

          if @floppy && dl == 0
            # Compute destination address
            es_base = @pipeline.desc_base_public(@pipeline.seg_cache_public(:es))
            bx = @pipeline.reg(:ebx) & 0xFFFF
            dest = (es_base + bx) & 0xFFFF_FFFF
            nbytes = al * 512

            # If destination overlaps pre-loaded MSDOS.SYS, skip the write —
            # the correct data is already in memory from load_dos_ram_image.
            unless @msdos_range && dest < (@msdos_range.end + 1) && (dest + nbytes) > @msdos_range.begin
              data = @floppy.read_sectors_chs(cylinder, head, sector, al)
              data.each_with_index { |b, i| memory[dest + i] = b & 0xFF }
            end

            # Success: AH=0, AL=sectors read
            @pipeline.set_reg(:eax, al & 0xFF)
            set_return_cf(memory, 0)
          else
            # Error: AH=0x80 (timeout), CF=1
            @pipeline.set_reg(:eax, (eax & 0x00FF) | (0x80 << 8))
            set_return_cf(memory, 1)
          end
        end

        def handle_disk_params(memory)
          if @floppy
            bpb = @floppy.bpb
            total = bpb[:total_sectors]
            spt = bpb[:sectors_per_track]
            heads = bpb[:heads]
            max_cyl = (total / heads / spt) - 1
            max_head = heads - 1

            @pipeline.set_reg(:eax, 0x0000)  # AH=0 success
            @pipeline.set_reg(:ebx, 0x0004)  # BL=drive type (1.44MB = 4)
            cl = (spt & 0x3F) | ((max_cyl >> 2) & 0xC0)
            ch = max_cyl & 0xFF
            @pipeline.set_reg(:ecx, (ch << 8) | cl)
            @pipeline.set_reg(:edx, (max_head << 8) | 0x01)  # DH=max_head, DL=1 drive
            set_return_cf(memory, 0)
          else
            @pipeline.set_reg(:eax, 0x0700)  # AH=7 (error)
            set_return_cf(memory, 1)
          end
        end

        # ========== INT 15h: System Services ==========

        # ========== INT 14h: Serial Port Services ==========

        def handle_int14h(memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x00  # Initialize serial port
            # AH=0x80 (timeout), AL=0 — no serial ports
            @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0x00FF) | (0x80 << 8))
          when 0x03  # Get serial port status
            @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0x00FF) | (0x80 << 8))
          end
        end

        # ========== INT 15h: System Services ==========

        def handle_int15h(memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x88  # Get extended memory size
            @pipeline.set_reg(:eax, 0)  # 0 KB extended memory
            set_return_cf(memory, 0)
          else
            # Unsupported function
            set_return_cf(memory, 1)
          end
        end

        # ========== INT 16h: Keyboard Services ==========

        def handle_int16h(memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x00  # Wait for keystroke
            # Return Enter key
            @pipeline.set_reg(:eax, 0x1C0D)  # AH=scan code 0x1C (Enter), AL=0x0D
          when 0x01  # Check for keystroke
            # No key available: ZF=1
            modify_stacked_flag(memory, :zf, 1)
          when 0x02  # Get shift flags
            @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0xFF00))  # AL=0 (no shift keys)
          end
        end

        # ========== INT 17h: Printer Services ==========

        def handle_int17h(_memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x00  # Print character
            # AH=0x30 (not selected + timeout) — no printer
            @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0x00FF) | (0x30 << 8))
          when 0x01  # Initialize printer
            @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0x00FF) | (0x30 << 8))
          when 0x02  # Get printer status
            @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0x00FF) | (0x30 << 8))
          end
        end

        # ========== INT 1Ah: Time Services ==========

        def handle_int1ah(memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x00  # Get system time
            @tick_count += 18  # ~1 second worth of ticks
            @pipeline.set_reg(:ecx, (@tick_count >> 16) & 0xFFFF)
            @pipeline.set_reg(:edx, @tick_count & 0xFFFF)
            @pipeline.set_reg(:eax, 0)  # AL=0 (midnight flag not set)
          when 0x02  # Get RTC time
            # Return 12:00:00 in BCD
            @pipeline.set_reg(:ecx, 0x1200)  # CH=hours, CL=minutes
            @pipeline.set_reg(:edx, 0x0000)  # DH=seconds, DL=DST flag
            set_return_cf(memory, 0)
          when 0x04  # Get RTC date
            # Return 2026-02-25 in BCD
            @pipeline.set_reg(:ecx, 0x2026)  # CH=century, CL=year
            @pipeline.set_reg(:edx, 0x0225)  # DH=month, DL=day
            set_return_cf(memory, 0)
          end
        end

        # ========== INT 20h: Program Terminate ==========

        def handle_int20h(_memory)
          # Program termination — in a real DOS this returns to the parent.
          # For our purposes, we just note it happened.
          @unhandled_ints << { vector: 0x20, eip: @pipeline.reg(:eip), info: :program_terminate }
        end

        # ========== INT 21h: DOS Services ==========

        def handle_int21h(memory)
          ah = (@pipeline.reg(:eax) >> 8) & 0xFF
          case ah
          when 0x02  # Display character
            dl = @pipeline.reg(:edx) & 0xFF
            @video_buffer << dl.chr
          when 0x06  # Direct console I/O
            dl = @pipeline.reg(:edx) & 0xFF
            if dl == 0xFF
              # Input request: return no character (ZF=1)
              modify_stacked_flag(memory, :zf, 1)
              @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0xFF00))  # AL=0
            else
              @video_buffer << dl.chr
            end
          when 0x09  # Display string (DS:DX -> '$'-terminated string)
            ds_base = @pipeline.desc_base_public(@pipeline.seg_cache_public(:ds))
            dx = @pipeline.reg(:edx) & 0xFFFF
            addr = (ds_base + dx) & 0xFFFF_FFFF
            256.times do
              ch = memory[addr] || 0
              break if ch == 0x24  # '$'
              @video_buffer << ch.chr
              addr = (addr + 1) & 0xFFFF_FFFF
            end
          when 0x25  # Set interrupt vector (AL=int#, DS:DX=handler)
            al = @pipeline.reg(:eax) & 0xFF
            ds_val = @pipeline.reg(:ds) & 0xFFFF
            dx = @pipeline.reg(:edx) & 0xFFFF
            write_ivt_entry(memory, al, ds_val, dx)
            # Update handler_linear_addrs if the new address is in our BIOS area
            ds_base = @pipeline.desc_base_public(@pipeline.seg_cache_public(:ds))
            new_linear = (ds_base + dx) & 0xFFFF_FFFF
            if new_linear >= BIOS_BASE && new_linear < BIOS_BASE + 0x10000
              @handler_linear_addrs[new_linear] = al
            end
          when 0x30  # Get DOS version
            @pipeline.set_reg(:eax, 0x0004)  # AL=major 4, AH=minor 0
            @pipeline.set_reg(:ebx, 0x0000)  # BH=DOS OEM, BL=0
            @pipeline.set_reg(:ecx, 0x0000)
          when 0x33  # Get/Set break flag
            al = @pipeline.reg(:eax) & 0xFF
            if al == 0  # Get break flag
              @pipeline.set_reg(:edx, (@pipeline.reg(:edx) & 0xFF00))  # DL=0 (off)
            end
          when 0x35  # Get interrupt vector (AL=int#)
            al = @pipeline.reg(:eax) & 0xFF
            ivt_addr = al * 4
            offset = mem_read16(memory, ivt_addr)
            segment = mem_read16(memory, ivt_addr + 2)
            @pipeline.set_reg(:ebx, offset)
            set_es_with_base(segment)
          when 0x40  # Write to file handle
            bx = @pipeline.reg(:ebx) & 0xFFFF
            cx = @pipeline.reg(:ecx) & 0xFFFF
            ds_base = @pipeline.desc_base_public(@pipeline.seg_cache_public(:ds))
            dx = @pipeline.reg(:edx) & 0xFFFF
            if bx == 1 || bx == 2  # stdout or stderr
              addr = (ds_base + dx) & 0xFFFF_FFFF
              cx.times do |i|
                ch = memory[(addr + i) & 0xFFFF_FFFF] || 0
                @video_buffer << ch.chr
              end
              @pipeline.set_reg(:eax, cx)  # AX = bytes written
            else
              @pipeline.set_reg(:eax, cx)  # pretend success
            end
            set_return_cf(memory, 0)
          when 0x3C  # Create file
            # No file creation support — return "access denied"
            @pipeline.set_reg(:eax, 0x0005)
            set_return_cf(memory, 1)
          when 0x3D  # Open file
            # No files available — return "file not found"
            @pipeline.set_reg(:eax, 0x0002)
            set_return_cf(memory, 1)
          when 0x3E  # Close file handle
            set_return_cf(memory, 0)
          when 0x3F  # Read from file handle
            bx = @pipeline.reg(:ebx) & 0xFFFF
            if bx <= 2  # stdin/stdout/stderr
              @pipeline.set_reg(:eax, 0)  # 0 bytes read (EOF)
              set_return_cf(memory, 0)
            else
              @pipeline.set_reg(:eax, 0x0006)  # invalid handle
              set_return_cf(memory, 1)
            end
          when 0x42  # Seek (LSEEK)
            set_return_cf(memory, 0)
            @pipeline.set_reg(:eax, 0)
            @pipeline.set_reg(:edx, 0)
          when 0x44  # IOCTL
            al = @pipeline.reg(:eax) & 0xFF
            if al == 0x00  # Get device information
              bx = @pipeline.reg(:ebx) & 0xFFFF
              if bx <= 2  # stdin/stdout/stderr → character device
                @pipeline.set_reg(:edx, 0x80D3)  # ISDEV | ISCIN | ISCOT | ISNUL | BINARY
                set_return_cf(memory, 0)
              else
                @pipeline.set_reg(:eax, 0x0006)  # invalid handle
                set_return_cf(memory, 1)
              end
            else
              @pipeline.set_reg(:eax, 0x0001)  # invalid function
              set_return_cf(memory, 1)
            end
          when 0x48  # Allocate memory
            # Return error: not enough memory
            @pipeline.set_reg(:eax, (@pipeline.reg(:eax) & 0x00FF) | (0x08 << 8))
            @pipeline.set_reg(:ebx, 0x0000)  # BX = largest block available
            set_return_cf(memory, 1)
          when 0x4A  # Resize memory block
            set_return_cf(memory, 0)  # pretend success
          when 0x4C  # Terminate program with return code
            @unhandled_ints << { vector: 0x21, ah: 0x4C, info: :terminate }
          else
            # Unhandled DOS function — log but don't fail
            @unhandled_ints << { vector: 0x21, ah: ah, eip: @pipeline.reg(:eip) }
          end
        end

        def set_es_with_base(segment)
          @pipeline.set_reg(:es, segment)
          base = (segment & 0xFFFF) << 4
          @pipeline.set_es_base(base)
        end

        # ========== Flag Helpers ==========

        # Modify the CF (carry flag) in the FLAGS word pushed on the stack by INT.
        # Stack layout after INT: [SP]=IP, [SP+2]=CS, [SP+4]=FLAGS
        def set_return_cf(memory, value)
          ss_base = @pipeline.desc_base_public(@pipeline.seg_cache_public(:ss))
          sp = @pipeline.reg(:esp) & 0xFFFF
          flags_addr = (ss_base + ((sp + 4) & 0xFFFF)) & 0xFFFF_FFFF
          flags = mem_read16(memory, flags_addr)
          flags = value == 0 ? (flags & ~1) : (flags | 1)
          mem_write16(memory, flags_addr, flags)
        end

        # Modify the ZF in the stacked FLAGS.
        def modify_stacked_flag(memory, flag, value)
          ss_base = @pipeline.desc_base_public(@pipeline.seg_cache_public(:ss))
          sp = @pipeline.reg(:esp) & 0xFFFF
          flags_addr = (ss_base + ((sp + 4) & 0xFFFF)) & 0xFFFF_FFFF
          flags = mem_read16(memory, flags_addr)
          case flag
          when :zf
            flags = value == 0 ? (flags & ~0x40) : (flags | 0x40)
          when :cf
            flags = value == 0 ? (flags & ~1) : (flags | 1)
          end
          mem_write16(memory, flags_addr, flags)
        end

        # ========== Memory Helpers ==========

        def mem_read16(memory, addr)
          (memory[addr] || 0) | ((memory[(addr + 1) & 0xFFFF_FFFF] || 0) << 8)
        end

        def mem_write16(memory, addr, val)
          memory[addr] = val & 0xFF
          memory[(addr + 1) & 0xFFFF_FFFF] = (val >> 8) & 0xFF
        end
      end
    end
  end
end
