# frozen_string_literal: true

require_relative '../../hdl/ir_harness'

module RHDL
  module Examples
    module RISCV
      # Headless runner factory for RISC-V simulation.
      # Provides the same core lifecycle APIs as interactive tasks but without terminal UI.
      class HeadlessRunner
        XV6_RESET_PC = 0x8000_0000
        LINUX_KERNEL_LOAD_ADDR = 0x8020_0000
        LINUX_INITRAMFS_LOAD_ADDR = 0x8400_0000
        LINUX_DTB_LOAD_ADDR = 0x87F0_0000
        LINUX_BOOTSTRAP_OFFSET = 0x1000
        LINUX_BOOT_HART_ID = 0

        attr_reader :cpu, :mode, :sim_backend, :effective_mode

        def initialize(mode: :ir, sim: nil)
          @mode = (mode || :ir).to_sym
          @effective_mode = normalize_mode(@mode)
          @sim_backend = (sim || default_backend(@mode)).to_sym

          backend, allow_fallback = map_backend(@effective_mode, @sim_backend)
          @cpu = IRHarness.new(backend: backend, allow_fallback: allow_fallback)
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
          @cpu.state
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
          @cpu.write_pc(pc)
        rescue StandardError => primary_error
          return if current_pc == pc

          if supports_runner_reset_vector?
            begin
              if @cpu.sim.runner_set_reset_vector(pc)
                reset
                return
              end
            rescue StandardError
              # Fall through to preserve the original write_pc error below.
            end
          end

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
          kernel_base = kernel_addr.to_i & 0xFFFF_FFFF
          entry_pc = (pc.nil? ? kernel_base : pc.to_i) & 0xFFFF_FFFF
          dtb_pointer = dtb_bytes ? (dtb_addr.to_i & 0xFFFF_FFFF) : 0
          bootstrap_addr = linux_bootstrap_addr(kernel_base)
          bootstrap_bytes = build_linux_bootstrap_program(
            hart_id: LINUX_BOOT_HART_ID,
            dtb_pointer: dtb_pointer,
            entry_pc: entry_pc
          )

          reset
          @cpu.clear_uart_tx_bytes
          load_instruction_bytes(kernel_bytes, kernel_base)
          load_data_bytes(initramfs_bytes, initramfs_addr.to_i) if initramfs_bytes
          load_data_bytes(dtb_bytes, dtb_addr.to_i) if dtb_bytes
          load_instruction_bytes(bootstrap_bytes, bootstrap_addr)
          set_pc(bootstrap_addr)
        end

        private

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
          if native? && @cpu.sim.respond_to?(:runner_load_rom)
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
          words.concat(load_immediate_words(rd: 10, value: hart_id))
          words.concat(load_immediate_words(rd: 11, value: dtb_pointer))
          words.concat(load_immediate_words(rd: 5, value: entry_pc))
          words << jalr_word(rd: 0, rs1: 5, imm: 0)
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
