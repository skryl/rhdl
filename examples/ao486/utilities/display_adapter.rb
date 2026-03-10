# frozen_string_literal: true

module RHDL
  module Examples
    module AO486
      # Renders the AO486 text buffer and optional debug lines as plain text.
      class DisplayAdapter
        TEXT_BASE = 0xB8000
        DEFAULT_WIDTH = 80
        DEFAULT_HEIGHT = 25
        TEXT_COLUMNS = DEFAULT_WIDTH
        TEXT_ROWS = DEFAULT_HEIGHT
        DEFAULT_ROW_STRIDE = DEFAULT_WIDTH * 2
        CURSOR_BDA = 0x450

        attr_reader :width, :height, :text_base, :row_stride

        def initialize(width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT, text_base: TEXT_BASE, row_stride: DEFAULT_ROW_STRIDE)
          @width = width
          @height = height
          @text_base = text_base
          @row_stride = row_stride
        end

        def render(memory:, cursor: :auto, debug_lines: [])
          lines = Array.new(height) { |row| render_row(memory, row) }
          cursor = cursor_from_bda(memory) if cursor == :auto

          if cursor
            row = cursor[:row].to_i
            col = cursor[:col].to_i
            if row.between?(0, height - 1) && col.between?(0, width - 1)
              current = lines[row]
              current[col] = '_'
            end
          end

          debug_lines = Array(debug_lines).map(&:to_s).reject(&:empty?)
          return lines.join("\n") if debug_lines.empty?

          ([lines.join("\n"), '-' * width, *debug_lines]).join("\n")
        end

        def cursor_from_bda(memory)
          if memory.respond_to?(:key?) &&
             !memory.key?(CURSOR_BDA) &&
             !memory.key?(CURSOR_BDA + 1)
            return nil
          end

          low = read_byte(memory, CURSOR_BDA)
          high = read_byte(memory, CURSOR_BDA + 1)
          { row: high, col: low }
        end

        private

        def render_row(memory, row)
          chars = Array.new(width) do |col|
            char_addr = text_base + (row * row_stride) + (col * 2)
            sanitize_char(read_byte(memory, char_addr))
          end
          chars.join
        end

        def sanitize_char(byte)
          return ' ' if byte.nil? || byte.zero?
          return byte.chr if byte.between?(32, 126)

          '.'
        end

        def read_byte(memory, addr)
          return 0 unless memory

          if memory.respond_to?(:fetch)
            memory.fetch(addr, 0).to_i & 0xFF
          elsif memory.respond_to?(:[])
            (memory[addr] || 0).to_i & 0xFF
          else
            0
          end
        end
      end
    end
  end
end
