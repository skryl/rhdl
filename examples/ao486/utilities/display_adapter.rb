# frozen_string_literal: true

module RHDL
  module Examples
    module AO486
      # Builds viewport and debug window text frames for AO486 interactive runs.
      class DisplayAdapter
        DEFAULT_VIEWPORT_WIDTH = 80
        DEFAULT_VIEWPORT_ROWS = 24

        def initialize(io_mode:, debug:, viewport_width: DEFAULT_VIEWPORT_WIDTH, viewport_rows: DEFAULT_VIEWPORT_ROWS)
          @io_mode = io_mode.to_sym
          @debug = !!debug
          @viewport_width = [Integer(viewport_width), 32].max
          @viewport_rows = [Integer(viewport_rows), 1].max
        rescue ArgumentError, TypeError
          @viewport_width = DEFAULT_VIEWPORT_WIDTH
          @viewport_rows = DEFAULT_VIEWPORT_ROWS
        end

        def render_trace_frame(
          mode:,
          sim_backend:,
          speed:,
          trace:,
          trace_cursor:,
          replay_length:,
          program_base_address:,
          boot_addr:,
          bios:,
          bios_system:,
          bios_video:,
          disk:,
          root_path:
        )
          replay_step = [Integer(trace_cursor), 0].max
          replay_total = [Integer(replay_length), 0].max
          index = [replay_step - 1, 0].max
          pcs = Array(trace.fetch("pc_sequence", []))
          instructions = Array(trace.fetch("instruction_sequence", []))
          writes = Array(trace.fetch("memory_writes", []))
          pc = u32(pcs[index] || 0)
          inst = u32(instructions[index] || 0)

          lines = []
          lines.concat(
            viewport_rows_for_trace(
              mode: mode,
              sim_backend: sim_backend,
              speed: speed,
              trace: trace,
              trace_cursor: replay_step,
              replay_length: replay_total,
              pc: pc,
              inst: inst,
              writes: writes.length
            )
          )
          if @debug
            lines << debug_panel_text(
              debug_lines(
                mode: mode,
                sim_backend: sim_backend,
                speed: speed,
                pc: pc,
                inst: inst,
                writes: writes.length,
                program_base_address: program_base_address,
                boot_addr: boot_addr,
                bios: bios,
                bios_system: bios_system,
                bios_video: bios_video,
                disk: disk,
                root_path: root_path
              )
            )
          end

          "#{lines.join("\n")}\n"
        end

        def render_live_frame(
          mode:,
          sim_backend:,
          speed:,
          state:,
          program_base_address:,
          boot_addr:,
          bios:,
          bios_system:,
          bios_video:,
          disk:,
          root_path:
        )
          snapshot = state.to_h
          pc = u32(snapshot.fetch("pc", 0))
          inst = u32(snapshot.fetch("instruction", 0))
          cycles = Integer(snapshot.fetch("cycles", 0))
          writes = Integer(snapshot.fetch("memory_write_count", 0))

          lines = []
          lines.concat(
            viewport_rows_for_live(
              mode: mode,
              sim_backend: sim_backend,
              speed: speed,
              state: snapshot,
              pc: pc,
              inst: inst,
              writes: writes,
              cycles: cycles
            )
          )
          if @debug
            lines << debug_panel_text(
              debug_lines(
                mode: mode,
                sim_backend: sim_backend,
                speed: speed,
                pc: pc,
                inst: inst,
                writes: writes,
                program_base_address: program_base_address,
                boot_addr: boot_addr,
                bios: bios,
                bios_system: bios_system,
                bios_video: bios_video,
                disk: disk,
                root_path: root_path,
                cycles: cycles
              )
            )
          end

          "#{lines.join("\n")}\n"
        end

        def memory_lines(memory:, limit:)
          sorted_memory_pairs(memory).first(Integer(limit)).map do |address, value|
            format("0x%08x => 0x%08x", address, u32(value))
          end
        rescue ArgumentError, TypeError
          []
        end

        private

        def viewport_rows_for_trace(mode:, sim_backend:, speed:, trace:, trace_cursor:, replay_length:, pc:, inst:, writes:)
          if @io_mode == :uart
            rows = trace_uart_rows(trace: trace, trace_cursor: trace_cursor)
            header = format(
              "AO486 UART View  mode=%s sim=%s step=%d/%d pc=0x%08x writes=%d",
              mode,
              sim_backend,
              trace_cursor,
              replay_length,
              pc,
              writes
            )
          else
            rows = trace_vga_rows(trace: trace)
            header = format(
              "AO486 MMAP View  mode=%s sim=%s step=%d/%d pc=0x%08x writes=%d",
              mode,
              sim_backend,
              trace_cursor,
              replay_length,
              pc,
              writes
            )
          end

          [normalize_viewport_row(header), *normalize_viewport_rows(rows)]
        end

        def viewport_rows_for_live(mode:, sim_backend:, speed:, state:, pc:, inst:, writes:, cycles:)
          if @io_mode == :uart
            rows = live_uart_rows(state: state)
            header = format(
              "AO486 UART View  mode=%s sim=%s cycles=%d pc=0x%08x writes=%d",
              mode,
              sim_backend,
              cycles,
              pc,
              writes
            )
          else
            rows = live_vga_rows(state: state)
            header = format(
              "AO486 MMAP View  mode=%s sim=%s cycles=%d pc=0x%08x writes=%d",
              mode,
              sim_backend,
              cycles,
              pc,
              writes
            )
          end

          [normalize_viewport_row(header), *normalize_viewport_rows(rows)]
        end

        def trace_vga_rows(trace:)
          text_rows = normalized_vga_rows(trace.fetch("vga_text_lines", nil))
          return text_rows if text_rows.any? { |line| !line.to_s.strip.empty? }

          rows = memory_lines(memory: trace.fetch("memory_contents", {}), limit: @viewport_rows)
          return ["(no memory contents)"] if rows.empty?

          rows
        end

        def live_vga_rows(state:)
          text_rows = normalized_vga_rows(state.fetch("vga_text_lines", nil))
          return text_rows if text_rows.any? { |line| !line.to_s.strip.empty? }

          rows = memory_lines(memory: state.fetch("memory_contents", {}), limit: @viewport_rows)
          return ["(no memory contents)"] if rows.empty?

          rows
        end

        def trace_uart_rows(trace:, trace_cursor:)
          instructions = Array(trace.fetch("instruction_sequence", []))
          pcs = Array(trace.fetch("pc_sequence", []))
          return ["(no trace events)"] if instructions.empty?

          start_idx = [trace_cursor - @viewport_rows, 0].max
          end_idx = [trace_cursor - 1, instructions.length - 1].min
          return ["(no trace events)"] if end_idx < start_idx

          rows = []
          (start_idx..end_idx).each do |idx|
            rows << format(
              "#%04d pc=0x%08x inst=0x%08x",
              idx,
              u32(pcs[idx] || 0),
              u32(instructions[idx] || 0)
            )
          end
          rows
        end

        def live_uart_rows(state:)
          serial = state.fetch("serial_output", "").to_s
          return ["(no serial output)"] if serial.empty?

          lines = serial.split(/\r?\n/).map(&:strip).reject(&:empty?)
          return ["(no serial output)"] if lines.empty?

          lines.last(@viewport_rows)
        end

        def debug_lines(
          mode:,
          sim_backend:,
          speed:,
          pc:,
          inst:,
          writes:,
          program_base_address:,
          boot_addr:,
          bios:,
          bios_system:,
          bios_video:,
          disk:,
          root_path:,
          cycles: nil
        )
          cycle_text = cycles.nil? ? "-" : Integer(cycles).to_s

          [
            format("PC:%08X INST:%08X Cycles:%s Writes:%d", pc, inst, cycle_text, writes),
            format("Sim:%-10s Mode:%s IO:%s Speed:%d BIOS:%s",
                   sim_backend.to_s.upcase,
                   mode.to_s.upcase,
                   @io_mode.to_s.upcase,
                   Integer(speed),
                   bios),
            format("Base:0x%08x Boot:0x%08x", u32(program_base_address), u32(boot_addr || 0)),
            format("BIOS0:%s", compact_path(bios_system, root_path: root_path)),
            format("BIOS1:%s", compact_path(bios_video, root_path: root_path)),
            format("Disk :%s", compact_path(disk, root_path: root_path))
          ]
        end

        def debug_panel_text(lines)
          width = @viewport_width
          clipped_lines = Array(lines).map do |line|
            line.to_s.ljust(width)[0, width]
          end
          panel = +"+" << ("-" * width) << "+\n"
          clipped_lines.each do |line|
            panel << "|" << line << "|\n"
          end
          panel << "+" << ("-" * width) << "+"
          panel
        end

        def sorted_memory_pairs(memory)
          Array(memory.to_h).map do |address, value|
            [parse_address(address), value]
          end.sort_by(&:first)
        end

        def parse_address(value)
          return Integer(value) if value.is_a?(Numeric)

          text = value.to_s.strip
          if text.match?(/\A[0-9a-fA-F]+\z/)
            Integer(text, 16)
          else
            Integer(text, 0)
          end
        rescue ArgumentError, TypeError
          0
        end

        def u32(value)
          Integer(value) & 0xFFFF_FFFF
        rescue ArgumentError, TypeError
          0
        end

        def present_or_default(value)
          text = value.to_s.strip
          text.empty? ? "(default)" : text
        end

        def compact_path(value, root_path:)
          text = present_or_default(value)
          return text if text == "(default)"

          expanded_root = begin
            File.expand_path(root_path.to_s)
          rescue StandardError
            nil
          end
          expanded_value = begin
            File.expand_path(text, expanded_root || Dir.pwd)
          rescue StandardError
            text
          end

          if expanded_root && expanded_value.start_with?("#{expanded_root}/")
            expanded_value.delete_prefix("#{expanded_root}/")
          else
            expanded_value
          end
        end

        def normalized_vga_rows(rows)
          Array(rows).map { |entry| entry.to_s.rstrip }
        end

        def normalize_viewport_rows(rows)
          text_rows = Array(rows).map { |line| normalize_viewport_row(line) }
          if text_rows.length < @viewport_rows
            text_rows + Array.new(@viewport_rows - text_rows.length, " " * @viewport_width)
          else
            text_rows.first(@viewport_rows)
          end
        end

        def normalize_viewport_row(line)
          line.to_s.ljust(@viewport_width)[0, @viewport_width]
        end
      end
    end
  end
end
