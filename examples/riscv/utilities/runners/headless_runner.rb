# frozen_string_literal: true

require_relative '../../hdl/ir_harness'
require_relative '../../hdl/pipeline/ir_harness'
require_relative '../assembler'

module RHDL
  module Examples
    module RISCV
      # Headless runner factory for RISC-V simulation.
      # Provides the same core lifecycle APIs as interactive tasks but without terminal UI.
      class HeadlessRunner
        XV6_RESET_PC = 0x8000_0000
        LINUX_KERNEL_LOAD_ADDR = 0x8040_0000
        LINUX_INITRAMFS_LOAD_ADDR = 0x8400_0000
        LINUX_DTB_LOAD_ADDR = 0x87F0_0000
        DEFAULT_MEM_SIZE = 128 * 1024 * 1024
        LINUX_BOOTSTRAP_OFFSET = 0x1000
        LINUX_BOOT_HART_ID = 0
        LINUX_PIPELINE_COMPAT_ISA = 'rv32imafdcsu_zicsr_zifencei'
        LINUX_PIPELINE_BOOTARGS = 'console=ttyS0 rdinit=/sbin/init quiet'
        FDT_MAGIC = 0xD00D_FEED
        FDT_BEGIN_NODE = 0x0000_0001
        FDT_END_NODE = 0x0000_0002
        FDT_PROP = 0x0000_0003
        FDT_NOP = 0x0000_0004
        FDT_END = 0x0000_0009

        attr_reader :cpu, :mode, :sim_backend, :effective_mode, :core

        def initialize(mode: :ir, sim: nil, core: :single, mem_size: nil)
          @mode = (mode || :ir).to_sym
          @effective_mode = normalize_mode(@mode)
          @sim_backend = (sim || default_backend(@mode)).to_sym
          @core = normalize_core(core)

          backend, allow_fallback = map_backend(@effective_mode, @sim_backend)
          resolved_mem_size = mem_size || DEFAULT_MEM_SIZE
          @cpu = build_cpu(core: @core, mem_size: resolved_mem_size, backend: backend, allow_fallback: allow_fallback)
        end

        def native?
          @cpu.native?
        end

        def simulator_type
          @cpu.simulator_type
        end

        def backend
          @cpu.backend
        end

        def reset
          @cpu.reset!
        end

        def run_steps(steps)
          @cpu.run_cycles(steps.to_i)
        end

        def cycle_count
          @cpu.clock_count
        end

        def cpu_state
          return @cpu.state if @cpu.respond_to?(:state)

          {
            pc: safe_cpu_pc,
            x1: safe_cpu_reg(1),
            x2: safe_cpu_reg(2),
            x10: safe_cpu_reg(10),
            x11: safe_cpu_reg(11),
            inst: safe_cpu_inst,
            cycles: cycle_count
          }
        end

        def load_program(path_or_bytes, base_addr: 0)
          bytes = path_or_bytes.is_a?(String) && File.exist?(path_or_bytes) ? File.binread(path_or_bytes) : path_or_bytes
          load_program_bytes(bytes, base_addr: base_addr)
        end

        def load_program_bytes(bytes, base_addr: 0)
          reset
          @cpu.clear_uart_tx_bytes
          load_instruction_bytes(bytes, base_addr.to_i)
        end

        def set_pc(value)
          pc = value.to_i & 0xFFFF_FFFF
          if supports_runner_reset_vector?
            begin
              if @cpu.sim.runner_set_reset_vector(pc)
                reset
                return
              end
            rescue StandardError
              # Fall through to direct PC write.
            end
          end

          @cpu.write_pc(pc)
          return if current_pc == pc
        rescue StandardError => primary_error
          return if current_pc == pc
          raise primary_error
        end

        def load_xv6(kernel:, fs:, pc: XV6_RESET_PC)
          unless native? && @cpu.sim.runner_kind == :riscv
            raise 'xv6 mode requires native RISC-V IR runner support (build native backends first).'
          end

          kernel_bytes = File.binread(kernel)
          fs_bytes = File.binread(fs)
          patch_phystop_for_fast_boot!(kernel_bytes)

          reset
          @cpu.clear_uart_tx_bytes
          load_instruction_bytes(kernel_bytes, XV6_RESET_PC)
          @cpu.load_virtio_disk(fs_bytes.bytes, offset: 0)
          set_pc(pc)
        end

        def load_linux(
          kernel:,
          initramfs: nil,
          dtb: nil,
          kernel_addr: LINUX_KERNEL_LOAD_ADDR,
          initramfs_addr: LINUX_INITRAMFS_LOAD_ADDR,
          dtb_addr: LINUX_DTB_LOAD_ADDR,
          pc: nil
        )
          unless native? && @cpu.sim.runner_kind == :riscv
            raise 'Linux mode requires native RISC-V IR runner support (build native backends first).'
          end

          if kernel.nil? || kernel.empty?
            raise 'Linux kernel path is required.'
          end

          unless File.file?(kernel)
            raise "Linux kernel not found: #{kernel}"
          end

          if initramfs && !File.file?(initramfs)
            raise "Linux initramfs not found: #{initramfs}"
          end

          if dtb && !File.file?(dtb)
            raise "Linux DTB not found: #{dtb}"
          end

          kernel_bytes = File.binread(kernel)
          initramfs_bytes = initramfs ? File.binread(initramfs) : nil
          dtb_bytes = dtb ? File.binread(dtb) : nil
          if dtb_bytes && initramfs_bytes
            dtb_bytes = patch_dtb_initrd_bounds(
              dtb_bytes,
              initramfs_addr.to_i,
              initramfs_bytes.bytesize
            )
          end
          if dtb_bytes && @core == :pipeline
            dtb_bytes = patch_dtb_cpu_isa(dtb_bytes, LINUX_PIPELINE_COMPAT_ISA)
            dtb_bytes = patch_dtb_bootargs(dtb_bytes, LINUX_PIPELINE_BOOTARGS)
          end
          kernel_base = kernel_addr.to_i & 0xFFFF_FFFF
          entry_pc = (pc.nil? ? kernel_base : pc.to_i) & 0xFFFF_FFFF
          dtb_pointer = dtb_bytes ? (dtb_addr.to_i & 0xFFFF_FFFF) : 0
          bootstrap_addr = linux_bootstrap_addr(kernel_base)
          bootstrap_bytes = build_linux_bootstrap_program(
            hart_id: LINUX_BOOT_HART_ID,
            dtb_pointer: dtb_pointer,
            entry_pc: entry_pc
          )

          previous_force_word_instruction_load = @force_word_instruction_load
          @force_word_instruction_load = true
          reset
          @cpu.clear_uart_tx_bytes
          load_instruction_bytes(kernel_bytes, kernel_base)
          load_data_bytes(initramfs_bytes, initramfs_addr.to_i) if initramfs_bytes
          load_data_bytes(dtb_bytes, dtb_addr.to_i) if dtb_bytes
          load_instruction_bytes(bootstrap_bytes, bootstrap_addr)
          set_pc(bootstrap_addr)
        ensure
          @force_word_instruction_load = previous_force_word_instruction_load
        end

        private

        def safe_cpu_pc
          return 0 unless @cpu.respond_to?(:read_pc)

          @cpu.read_pc & 0xFFFF_FFFF
        rescue StandardError
          0
        end

        def safe_cpu_reg(index)
          return 0 unless @cpu.respond_to?(:read_reg)

          @cpu.read_reg(index) & 0xFFFF_FFFF
        rescue StandardError
          0
        end

        def safe_cpu_inst
          return 0 unless @cpu.respond_to?(:current_inst)

          @cpu.current_inst & 0xFFFF_FFFF
        rescue StandardError
          0
        end

        def normalize_mode(mode)
          case mode
          when :ruby, :ir
            mode
          when :netlist, :verilog
            warn "Mode #{mode.inspect} is not implemented for RISC-V yet; falling back to :ir."
            :ir
          else
            raise ArgumentError, "Unsupported mode #{mode.inspect}. Use ruby, ir, netlist, or verilog."
          end
        end

        def normalize_core(core)
          value = (core || :single).to_sym
          return value if %i[single pipeline].include?(value)

          raise ArgumentError, "Unsupported core #{core.inspect}. Use single or pipeline."
        end

        def build_cpu(core:, mem_size:, backend:, allow_fallback:)
          case core
          when :single
            IRHarness.new(mem_size: mem_size, backend: backend, allow_fallback: allow_fallback)
          when :pipeline
            Pipeline::IRHarness.new('riscv_pipeline_ir', mem_size: mem_size, backend: backend, allow_fallback: allow_fallback)
          else
            raise ArgumentError, "Unsupported core #{core.inspect}. Use single or pipeline."
          end
        end

        def current_pc
          @cpu.read_pc
        rescue StandardError
          nil
        end

        def supports_runner_reset_vector?
          return false unless @cpu.respond_to?(:sim) && @cpu.respond_to?(:native?)
          return false unless @cpu.native?
          return false unless @cpu.sim.respond_to?(:runner_kind) && @cpu.sim.runner_kind == :riscv

          @cpu.sim.respond_to?(:runner_set_reset_vector)
        end

        def map_backend(mode, sim_backend)
          case sim_backend
          when :ruby
            [:interpreter, mode == :ruby]
          when :interpret
            [:interpreter, mode == :ruby]
          when :jit
            [:jit, mode == :ruby]
          when :compile
            [:compiler, mode == :ruby]
          else
            raise ArgumentError, "Unsupported sim backend #{sim_backend.inspect}. Use ruby, interpret, jit, or compile."
          end
        end

        def default_backend(mode)
          case mode
          when :ruby
            :ruby
          when :ir, :netlist
            :compile
          when :verilog
            :ruby
          else
            raise "Unknown mode: #{mode}. Valid modes: ruby, ir, netlist, verilog"
          end
        end

        def load_instruction_bytes(bytes, base_addr)
          if native? && @cpu.sim.respond_to?(:runner_load_rom) && !@force_word_instruction_load
            @cpu.sim.runner_load_rom(bytes, base_addr)
          else
            words = bytes_to_words(bytes)
            @cpu.load_program(words, base_addr)
          end
        end

        def load_data_bytes(bytes, base_addr)
          payload = bytes.is_a?(String) ? bytes : bytes.pack('C*')
          if native? && @cpu.sim.respond_to?(:runner_write_memory)
            @cpu.sim.runner_write_memory(base_addr.to_i, payload, mapped: false)
          else
            words = bytes_to_words(payload)
            @cpu.load_data(words, base_addr)
          end
        end

        def patch_dtb_initrd_bounds(dtb_bytes, initramfs_addr, initramfs_size)
          return dtb_bytes if dtb_bytes.nil? || dtb_bytes.bytesize < 40

          blob = dtb_bytes.dup
          return dtb_bytes unless read_fdt_be32(blob, 0) == FDT_MAGIC

          totalsize = read_fdt_be32(blob, 4)
          off_dt_struct = read_fdt_be32(blob, 8)
          off_dt_strings = read_fdt_be32(blob, 12)
          size_dt_strings = read_fdt_be32(blob, 32)
          size_dt_struct = read_fdt_be32(blob, 36)

          return dtb_bytes if totalsize <= 0 || totalsize > blob.bytesize

          struct_limit = off_dt_struct + size_dt_struct
          strings_limit = off_dt_strings + size_dt_strings
          return dtb_bytes if off_dt_struct.negative? || off_dt_strings.negative?
          return dtb_bytes if struct_limit > totalsize || strings_limit > totalsize

          strings = blob.byteslice(off_dt_strings, size_dt_strings)
          return dtb_bytes if strings.nil?

          initrd_start = initramfs_addr.to_i & 0xFFFF_FFFF_FFFF_FFFF
          initrd_end = (initrd_start + initramfs_size.to_i) & 0xFFFF_FFFF_FFFF_FFFF

          cursor = off_dt_struct
          depth = 0
          in_chosen = false

          while (cursor + 4) <= struct_limit
            token = read_fdt_be32(blob, cursor)
            cursor += 4

            case token
            when FDT_BEGIN_NODE
              name, consumed = read_fdt_struct_name(blob, cursor, struct_limit)
              return dtb_bytes if name.nil? || consumed.nil?

              cursor += consumed
              depth += 1
              in_chosen = (depth == 2 && name == 'chosen')
            when FDT_END_NODE
              in_chosen = false if in_chosen && depth == 2
              depth -= 1
              return dtb_bytes if depth.negative?
            when FDT_PROP
              return dtb_bytes if (cursor + 8) > struct_limit

              value_len = read_fdt_be32(blob, cursor)
              cursor += 4
              nameoff = read_fdt_be32(blob, cursor)
              cursor += 4

              value_offset = cursor
              value_padded_len = (value_len + 3) & ~0x3
              return dtb_bytes if (cursor + value_padded_len) > struct_limit

              if in_chosen
                prop_name = read_fdt_strings_name(strings, nameoff)
                if prop_name == 'linux,initrd-start'
                  write_fdt_address_prop(blob, value_offset, value_len, initrd_start)
                elsif prop_name == 'linux,initrd-end'
                  write_fdt_address_prop(blob, value_offset, value_len, initrd_end)
                end
              end

              cursor += value_padded_len
            when FDT_NOP
              next
            when FDT_END
              break
            else
              return dtb_bytes
            end
          end

          blob
        rescue StandardError
          dtb_bytes
        end

        def patch_dtb_cpu_isa(dtb_bytes, isa_string)
          return dtb_bytes if dtb_bytes.nil? || dtb_bytes.bytesize < 40
          return dtb_bytes if isa_string.nil? || isa_string.empty?

          blob = dtb_bytes.dup
          return dtb_bytes unless read_fdt_be32(blob, 0) == FDT_MAGIC

          totalsize = read_fdt_be32(blob, 4)
          off_dt_struct = read_fdt_be32(blob, 8)
          off_dt_strings = read_fdt_be32(blob, 12)
          size_dt_strings = read_fdt_be32(blob, 32)
          size_dt_struct = read_fdt_be32(blob, 36)

          return dtb_bytes if totalsize <= 0 || totalsize > blob.bytesize

          struct_limit = off_dt_struct + size_dt_struct
          strings_limit = off_dt_strings + size_dt_strings
          return dtb_bytes if off_dt_struct.negative? || off_dt_strings.negative?
          return dtb_bytes if struct_limit > totalsize || strings_limit > totalsize

          strings = blob.byteslice(off_dt_strings, size_dt_strings)
          return dtb_bytes if strings.nil?

          cursor = off_dt_struct
          depth = 0
          path = []
          patched = false

          while (cursor + 4) <= struct_limit
            token = read_fdt_be32(blob, cursor)
            cursor += 4

            case token
            when FDT_BEGIN_NODE
              name, consumed = read_fdt_struct_name(blob, cursor, struct_limit)
              return dtb_bytes if name.nil? || consumed.nil?

              cursor += consumed
              depth += 1
              path << name
            when FDT_END_NODE
              depth -= 1
              return dtb_bytes if depth.negative?

              path.pop
            when FDT_PROP
              return dtb_bytes if (cursor + 8) > struct_limit

              value_len = read_fdt_be32(blob, cursor)
              cursor += 4
              nameoff = read_fdt_be32(blob, cursor)
              cursor += 4

              value_offset = cursor
              value_padded_len = (value_len + 3) & ~0x3
              return dtb_bytes if (cursor + value_padded_len) > struct_limit

              if !patched && path == ['', 'cpus', 'cpu@0']
                prop_name = read_fdt_strings_name(strings, nameoff)
                if prop_name == 'riscv,isa'
                  replacement = "#{isa_string}\x00".b
                  if replacement.bytesize <= value_len
                    replacement.bytes.each_with_index do |byte, idx|
                      blob.setbyte(value_offset + idx, byte)
                    end
                    replacement.bytesize.upto(value_len - 1) do |idx|
                      blob.setbyte(value_offset + idx, 0)
                    end
                    patched = true
                  end
                end
              end

              cursor += value_padded_len
            when FDT_NOP
              next
            when FDT_END
              break
            else
              return dtb_bytes
            end
          end

          patched ? blob : dtb_bytes
        rescue StandardError
          dtb_bytes
        end

        def patch_dtb_bootargs(dtb_bytes, bootargs)
          return dtb_bytes if dtb_bytes.nil? || dtb_bytes.bytesize < 40
          return dtb_bytes if bootargs.nil? || bootargs.empty?

          blob = dtb_bytes.dup
          return dtb_bytes unless read_fdt_be32(blob, 0) == FDT_MAGIC

          totalsize = read_fdt_be32(blob, 4)
          off_dt_struct = read_fdt_be32(blob, 8)
          off_dt_strings = read_fdt_be32(blob, 12)
          size_dt_strings = read_fdt_be32(blob, 32)
          size_dt_struct = read_fdt_be32(blob, 36)

          return dtb_bytes if totalsize <= 0 || totalsize > blob.bytesize

          struct_limit = off_dt_struct + size_dt_struct
          strings_limit = off_dt_strings + size_dt_strings
          return dtb_bytes if off_dt_struct.negative? || off_dt_strings.negative?
          return dtb_bytes if struct_limit > totalsize || strings_limit > totalsize

          strings = blob.byteslice(off_dt_strings, size_dt_strings)
          return dtb_bytes if strings.nil?

          replacement = "#{bootargs}\x00".b
          cursor = off_dt_struct
          depth = 0
          in_chosen = false

          while (cursor + 4) <= struct_limit
            token = read_fdt_be32(blob, cursor)
            cursor += 4

            case token
            when FDT_BEGIN_NODE
              name, consumed = read_fdt_struct_name(blob, cursor, struct_limit)
              return dtb_bytes if name.nil? || consumed.nil?

              cursor += consumed
              depth += 1
              in_chosen = (depth == 2 && name == 'chosen')
            when FDT_END_NODE
              in_chosen = false if in_chosen && depth == 2
              depth -= 1
              return dtb_bytes if depth.negative?
            when FDT_PROP
              return dtb_bytes if (cursor + 8) > struct_limit

              value_len = read_fdt_be32(blob, cursor)
              cursor += 4
              nameoff = read_fdt_be32(blob, cursor)
              cursor += 4

              value_offset = cursor
              value_padded_len = (value_len + 3) & ~0x3
              return dtb_bytes if (cursor + value_padded_len) > struct_limit

              if in_chosen
                prop_name = read_fdt_strings_name(strings, nameoff)
                if prop_name == 'bootargs' && replacement.bytesize <= value_len
                  replacement.bytes.each_with_index do |byte, idx|
                    blob.setbyte(value_offset + idx, byte)
                  end
                  replacement.bytesize.upto(value_len - 1) do |idx|
                    blob.setbyte(value_offset + idx, 0)
                  end
                  return blob
                end
              end

              cursor += value_padded_len
            when FDT_NOP
              next
            when FDT_END
              break
            else
              return dtb_bytes
            end
          end

          dtb_bytes
        rescue StandardError
          dtb_bytes
        end

        def read_fdt_be32(bytes, offset)
          chunk = bytes.byteslice(offset, 4)
          raise ArgumentError, 'FDT u32 read out of bounds' if chunk.nil? || chunk.bytesize != 4

          chunk.unpack1('N')
        end

        def write_fdt_be32(bytes, offset, value)
          v = value.to_i & 0xFFFF_FFFF
          bytes.setbyte(offset + 0, (v >> 24) & 0xFF)
          bytes.setbyte(offset + 1, (v >> 16) & 0xFF)
          bytes.setbyte(offset + 2, (v >> 8) & 0xFF)
          bytes.setbyte(offset + 3, v & 0xFF)
        end

        def read_fdt_struct_name(bytes, offset, struct_limit)
          idx = offset
          idx += 1 while idx < struct_limit && bytes.getbyte(idx) != 0
          return [nil, nil] if idx >= struct_limit

          name = bytes.byteslice(offset, idx - offset)
          consumed = (idx - offset + 1 + 3) & ~0x3
          [name, consumed]
        end

        def read_fdt_strings_name(strings, nameoff)
          return nil if nameoff.negative? || nameoff >= strings.bytesize

          idx = nameoff
          idx += 1 while idx < strings.bytesize && strings.getbyte(idx) != 0
          return nil if idx >= strings.bytesize

          strings.byteslice(nameoff, idx - nameoff)
        end

        def write_fdt_address_prop(bytes, value_offset, value_len, value)
          value_u64 = value.to_i & 0xFFFF_FFFF_FFFF_FFFF

          if value_len >= 8
            write_fdt_be32(bytes, value_offset, (value_u64 >> 32) & 0xFFFF_FFFF)
            write_fdt_be32(bytes, value_offset + 4, value_u64 & 0xFFFF_FFFF)
          elsif value_len >= 4
            write_fdt_be32(bytes, value_offset, value_u64 & 0xFFFF_FFFF)
          end
        end

        def patch_phystop_for_fast_boot!(bytes)
          return 0 if bytes.nil? || bytes.bytesize < 4

          patches = 0
          0.step(bytes.bytesize - 4, 4) do |offset|
            word = bytes.byteslice(offset, 4).unpack1('V')
            next unless (word & 0x7F) == 0x37

            imm20 = (word >> 12) & 0xFFFFF
            next unless imm20 == 0x88000

            rd = (word >> 7) & 0x1F
            new_word = (0x80200 << 12) | (rd << 7) | 0x37
            bytes.setbyte(offset + 0, new_word & 0xFF)
            bytes.setbyte(offset + 1, (new_word >> 8) & 0xFF)
            bytes.setbyte(offset + 2, (new_word >> 16) & 0xFF)
            bytes.setbyte(offset + 3, (new_word >> 24) & 0xFF)
            patches += 1
          end

          patches
        end

        def bytes_to_words(bytes)
          array = bytes.is_a?(String) ? bytes.bytes : bytes.to_a
          padding = (4 - (array.length % 4)) % 4
          array.concat([0] * padding)
          array.each_slice(4).map do |b0, b1, b2, b3|
            (b0 & 0xFF) |
              ((b1 & 0xFF) << 8) |
              ((b2 & 0xFF) << 16) |
              ((b3 & 0xFF) << 24)
          end
        end

        def linux_bootstrap_addr(kernel_addr)
          value = kernel_addr.to_i
          if value < LINUX_BOOTSTRAP_OFFSET
            raise ArgumentError, format(
              'Linux kernel address 0x%08x is too low for bootstrap trampoline placement.',
              value & 0xFFFF_FFFF
            )
          end

          (value - LINUX_BOOTSTRAP_OFFSET) & 0xFFFF_FFFF
        end

        def build_linux_bootstrap_program(hart_id:, dtb_pointer:, entry_pc:)
          words = []
          labels = {}
          patches = []

          emit = ->(word) { words << (word & 0xFFFF_FFFF) }
          emit_words = ->(seq) { seq.each { |word| emit.call(word) } }
          mark = ->(name) { labels[name] = words.length }
          emit_branch = lambda do |type, rs1, rs2, target|
            patches << { index: words.length, type: type, rs1: rs1, rs2: rs2, target: target }
            emit.call(0)
          end
          emit_jump = lambda do |target|
            patches << { index: words.length, type: :j, target: target }
            emit.call(0)
          end

          emit.call(Assembler.auipc(5, 0))
          emit.call(Assembler.addi(5, 5, 16))
          emit.call(Assembler.csrrw(0, 0x305, 5))
          emit_jump.call(:boot_entry)

          mark.call(:sbi_trap)
          emit.call(Assembler.csrrs(5, 0x342, 0))
          emit_words.call(load_immediate_words(rd: 6, value: 9))
          emit_branch.call(:bne, 5, 6, :trap_return)
          emit.call(Assembler.csrrs(5, 0x341, 0))
          emit.call(Assembler.addi(5, 5, 4))
          emit.call(Assembler.csrrw(0, 0x341, 5))

          emit_words.call(load_immediate_words(rd: 5, value: 0x10))
          emit_branch.call(:beq, 17, 5, :sbi_base)
          emit_words.call(load_immediate_words(rd: 5, value: 0x5449_4D45))
          emit_branch.call(:beq, 17, 5, :sbi_time)
          emit_words.call(load_immediate_words(rd: 5, value: 0))
          emit_branch.call(:beq, 17, 5, :sbi_legacy_set_timer)
          emit_words.call(load_immediate_words(rd: 5, value: 1))
          emit_branch.call(:beq, 17, 5, :sbi_legacy_putchar)
          emit_words.call(load_immediate_words(rd: 5, value: 2))
          emit_branch.call(:beq, 17, 5, :sbi_legacy_getchar)
          emit_jump.call(:sbi_not_supported)

          mark.call(:sbi_base)
          emit_words.call(load_immediate_words(rd: 5, value: 0))
          emit_branch.call(:beq, 16, 5, :sbi_base_get_spec_version)
          emit_words.call(load_immediate_words(rd: 5, value: 1))
          emit_branch.call(:beq, 16, 5, :sbi_base_get_impl_id)
          emit_words.call(load_immediate_words(rd: 5, value: 2))
          emit_branch.call(:beq, 16, 5, :sbi_base_get_impl_version)
          emit_words.call(load_immediate_words(rd: 5, value: 3))
          emit_branch.call(:beq, 16, 5, :sbi_base_probe_extension)
          emit_words.call(load_immediate_words(rd: 5, value: 4))
          emit_branch.call(:beq, 16, 5, :sbi_base_get_mvendorid)
          emit_words.call(load_immediate_words(rd: 5, value: 5))
          emit_branch.call(:beq, 16, 5, :sbi_base_get_marchid)
          emit_words.call(load_immediate_words(rd: 5, value: 6))
          emit_branch.call(:beq, 16, 5, :sbi_base_get_mimpid)
          emit_jump.call(:sbi_not_supported)

          mark.call(:sbi_base_get_spec_version)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit_words.call(load_immediate_words(rd: 11, value: 2))
          emit.call(Assembler.mret)

          mark.call(:sbi_base_get_impl_id)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit_words.call(load_immediate_words(rd: 11, value: 0))
          emit.call(Assembler.mret)

          mark.call(:sbi_base_get_impl_version)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit_words.call(load_immediate_words(rd: 11, value: 1))
          emit.call(Assembler.mret)

          mark.call(:sbi_base_probe_extension)
          emit_words.call(load_immediate_words(rd: 5, value: 0x10))
          emit_branch.call(:beq, 10, 5, :sbi_probe_yes)
          emit_words.call(load_immediate_words(rd: 5, value: 0x5449_4D45))
          emit_branch.call(:beq, 10, 5, :sbi_probe_yes)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit_words.call(load_immediate_words(rd: 11, value: 0))
          emit.call(Assembler.mret)

          mark.call(:sbi_probe_yes)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit_words.call(load_immediate_words(rd: 11, value: 1))
          emit.call(Assembler.mret)

          mark.call(:sbi_base_get_mvendorid)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit.call(Assembler.csrrs(11, 0xF11, 0))
          emit.call(Assembler.mret)

          mark.call(:sbi_base_get_marchid)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit.call(Assembler.csrrs(11, 0xF12, 0))
          emit.call(Assembler.mret)

          mark.call(:sbi_base_get_mimpid)
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit.call(Assembler.csrrs(11, 0xF13, 0))
          emit.call(Assembler.mret)

          mark.call(:sbi_time)
          emit_branch.call(:bne, 16, 0, :sbi_not_supported)
          emit_jump.call(:sbi_program_timer)

          mark.call(:sbi_legacy_set_timer)
          emit_jump.call(:sbi_program_timer)

          mark.call(:sbi_program_timer)
          emit_words.call(load_immediate_words(rd: 5, value: 0x0200_4000))
          emit_words.call(load_immediate_words(rd: 6, value: 0xFFFF_FFFF))
          emit.call(Assembler.sw(6, 5, 4))
          emit.call(Assembler.sw(10, 5, 0))
          emit.call(Assembler.sw(11, 5, 4))
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit_words.call(load_immediate_words(rd: 11, value: 0))
          emit.call(Assembler.mret)

          mark.call(:sbi_legacy_putchar)
          emit_words.call(load_immediate_words(rd: 5, value: 0x1000_0000))
          emit.call(Assembler.sb(10, 5, 0))
          emit_words.call(load_immediate_words(rd: 10, value: 0))
          emit.call(Assembler.mret)

          mark.call(:sbi_legacy_getchar)
          emit_words.call(load_immediate_words(rd: 10, value: 0xFFFF_FFFF))
          emit.call(Assembler.mret)

          mark.call(:sbi_not_supported)
          emit_words.call(load_immediate_words(rd: 10, value: 0xFFFF_FFFE))
          emit_words.call(load_immediate_words(rd: 11, value: 0))
          emit.call(Assembler.mret)

          mark.call(:trap_return)
          emit.call(Assembler.mret)

          mark.call(:boot_entry)
          emit_words.call(load_immediate_words(rd: 5, value: 0xFFFF_FFFF))
          emit.call(Assembler.csrrw(0, 0x306, 5))
          emit.call(Assembler.csrrw(0, 0x106, 5))
          emit_words.call(load_immediate_words(rd: 5, value: 0x0000_B1FF))
          emit.call(Assembler.csrrw(0, 0x302, 5))
          # Delegate software/timer/external interrupts to S-mode for Linux.
          emit_words.call(load_immediate_words(rd: 5, value: 0x0000_0888))
          emit.call(Assembler.csrrw(0, 0x303, 5))
          emit_words.call(load_immediate_words(rd: 5, value: 0x0000_0800))
          emit.call(Assembler.csrrw(0, 0x300, 5))
          emit_words.call(load_immediate_words(rd: 5, value: entry_pc))
          emit.call(Assembler.csrrw(0, 0x341, 5))
          emit_words.call(load_immediate_words(rd: 10, value: hart_id))
          emit_words.call(load_immediate_words(rd: 11, value: dtb_pointer))
          emit.call(Assembler.mret)

          patches.each do |patch|
            target_index = labels.fetch(patch[:target]) do
              raise ArgumentError, "Missing bootstrap label #{patch[:target].inspect}"
            end
            offset = (target_index - patch[:index]) * 4
            words[patch[:index]] = case patch[:type]
                                   when :beq then Assembler.beq(patch[:rs1], patch[:rs2], offset)
                                   when :bne then Assembler.bne(patch[:rs1], patch[:rs2], offset)
                                   when :j then Assembler.j(offset)
                                   else
                                     raise ArgumentError, "Unsupported bootstrap patch type #{patch[:type].inspect}"
                                   end
          end

          words.pack('V*')
        end

        def load_immediate_words(rd:, value:)
          value_u32 = value.to_i & 0xFFFF_FFFF
          hi20 = ((value_u32 + 0x800) >> 12) & 0xFFFFF
          base = (hi20 << 12) & 0xFFFF_FFFF
          lo12 = (value_u32 - base) & 0xFFF
          lo12 -= 0x1000 if lo12 >= 0x800

          [
            lui_word(rd: rd, imm20: hi20),
            addi_word(rd: rd, rs1: rd, imm: lo12)
          ]
        end

        def lui_word(rd:, imm20:)
          (((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37) & 0xFFFF_FFFF
        end

        def addi_word(rd:, rs1:, imm:)
          (((imm.to_i & 0xFFF) << 20) |
            ((rs1 & 0x1F) << 15) |
            ((rd & 0x1F) << 7) |
            0x13) & 0xFFFF_FFFF
        end

        def jalr_word(rd:, rs1:, imm:)
          (((imm.to_i & 0xFFF) << 20) |
            ((rs1 & 0x1F) << 15) |
            ((rd & 0x1F) << 7) |
            0x67) & 0xFFFF_FFFF
        end
      end
    end
  end
end
