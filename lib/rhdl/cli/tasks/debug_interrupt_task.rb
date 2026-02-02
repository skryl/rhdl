# frozen_string_literal: true

module RHDL
  module CLI
    module Tasks
      # Debug task for investigating Game Boy interrupt handling
      class DebugInterruptTask < Task
        def run
          require_relative '../../../../examples/gameboy/utilities/gameboy_ir'

          # Create test ROM that enables VBlank interrupt and waits
          rom = create_test_rom

          runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
          runner.load_rom(rom.pack('C*'))
          runner.reset

          sim = runner.sim

          # Set up VCD tracing
          sim.trace_add_signals_matching('ie_r')
          sim.trace_add_signals_matching('if_r')
          sim.trace_add_signals_matching('irq_n')
          sim.trace_add_signals_matching('vblank_irq')
          sim.trace_add_signals_matching('int_n')
          sim.trace_add_signals_matching('int_e_ff1')
          sim.trace_add_signals_matching('int_e_ff2')
          sim.trace_add_signals_matching('int_cycle')
          sim.trace_add_signals_matching('v_cnt')
          sim.trace_add_signals_matching('cpu__debug_pc')
          sim.trace_add_signals_matching('set_ei')
          sim.trace_add_signals_matching('set_di')
          sim.trace_add_signals_matching('t_state')
          sim.trace_add_signals_matching('m_cycle')
          sim.trace_add_signals_matching('cpu_clken')
          sim.trace_add_signals_matching('ir')

          vcd_path = '/tmp/interrupt_debug.vcd'
          sim.trace_start_streaming(vcd_path)

          puts "Tracing to #{vcd_path}..."
          puts "Running boot ROM in small batches..."

          # Run boot ROM in small batches, checking frequently
          last_pc = 0
          while runner.cycle_count < 310_000
            runner.run_steps(100)  # Much smaller batches
            sim.trace_capture

            pc = runner.cpu_state[:pc]
            ir = sim.peek('gb_core__cpu__ir') rescue 0
            set_ei = sim.peek('gb_core__cpu__set_ei') rescue 0
            ime = sim.peek('gb_core__cpu__int_e_ff1') rescue 0

            # Check if we see the EI instruction or if IME changes
            if ir == 0xFB || set_ei == 1
              ie = sim.peek('gb_core__ie_r') rescue 0
              t_state = sim.peek('gb_core__cpu__t_state') rescue 0
              m_cycle = sim.peek('gb_core__cpu__m_cycle') rescue 0
              puts "*** EI DETECTED: Cycle #{runner.cycle_count}: PC=0x#{pc.to_s(16)}, IR=0x#{ir.to_s(16)}, M=#{m_cycle}, T=#{t_state}, set_ei=#{set_ei}, IME=#{ime}, IE=0x#{ie.to_s(16)}"
            end

            # Also check around 0x0158 (where EI should be)
            if (pc >= 0x0155 && pc <= 0x015B) && pc != last_pc
              ie = sim.peek('gb_core__ie_r') rescue 0
              t_state = sim.peek('gb_core__cpu__t_state') rescue 0
              m_cycle = sim.peek('gb_core__cpu__m_cycle') rescue 0
              puts "Near EI: Cycle #{runner.cycle_count}: PC=0x#{pc.to_s(16)}, IR=0x#{ir.to_s(16)}, M=#{m_cycle}, T=#{t_state}, set_ei=#{set_ei}, IME=#{ime}, IE=0x#{ie.to_s(16)}"
              last_pc = pc
            end

            # Print progress every 50K cycles
            if runner.cycle_count % 50_000 == 0
              puts "Progress: #{runner.cycle_count} cycles, PC=0x#{pc.to_s(16)}, IME=#{ime}"
            end
          end

          puts "\nFinal state: cycles=#{runner.cycle_count}"

          puts "\nContinuing with coarse capture..."
          20.times do |i|
            runner.run_steps(5000)
            sim.trace_capture

            pc = runner.cpu_state[:pc]
            ie = sim.peek('gb_core__ie_r') rescue 0
            if_reg = sim.peek('gb_core__if_r') rescue 0
            ime = sim.peek('gb_core__cpu__int_e_ff1') rescue 0
            v_cnt = sim.peek('gb_core__video_unit__v_cnt') rescue 0

            puts "Cycle #{runner.cycle_count}: PC=0x#{pc.to_s(16)}, IE=0x#{ie.to_s(16)}, IF=0x#{if_reg.to_s(16)}, IME=#{ime}, V=#{v_cnt}"
          end

          sim.trace_stop
          puts "\nVCD saved to #{vcd_path}"

          # Check result
          zpram_80 = sim.read_zpram(0)  # Flag at 0xFF80
          puts "\nResult: 0xFF80 = #{zpram_80} (expected 0x42 if interrupt worked)"
        end

        private

        def create_test_rom
          rom = Array.new(32 * 1024, 0x00)

          # Nintendo logo (required for boot)
          nintendo_logo = [
            0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
            0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
            0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
            0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
            0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
            0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
          ]
          nintendo_logo.each_with_index { |b, i| rom[0x104 + i] = b }

          # Title
          "INTTEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

          # Header checksum
          checksum = 0
          (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
          rom[0x14D] = checksum

          # VBlank interrupt handler at 0x0040
          handler_code = [
            0x3E, 0x42,        # LD A, 0x42
            0xE0, 0x80,        # LDH (0x80), A - store flag
            0xD9               # RETI
          ]
          handler_code.each_with_index { |b, i| rom[0x0040 + i] = b }

          # Entry point at 0x0100: JP 0x0150
          rom[0x100] = 0xC3
          rom[0x101] = 0x50
          rom[0x102] = 0x01

          # Main code at 0x0150
          code_at_150 = [
            0x3E, 0x00,        # LD A, 0x00
            0xE0, 0x80,        # LDH (0x80), A - clear flag
            0x3E, 0x01,        # LD A, 0x01 (VBlank enable bit)
            0xE0, 0xFF,        # LDH (0xFF), A - IE = 0x01 (enable VBlank)
            0xFB,              # EI - enable interrupts
            # Wait loop
            0x01, 0x00, 0x08,  # LD BC, 0x0800
            # wait_loop:
            0x0B,              # DEC BC
            0x78,              # LD A, B
            0xB1,              # OR C
            0x20, 0xFB,        # JR NZ, wait_loop
            # Check result
            0xF0, 0x80,        # LDH A, (0x80) - load flag
            0xE0, 0x81,        # LDH (0x81), A
            0x76               # HALT
          ]
          code_at_150.each_with_index { |b, i| rom[0x0150 + i] = b }

          rom
        end
      end
    end
  end
end
