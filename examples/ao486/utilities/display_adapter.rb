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
        DEFAULT_PAGE_STRIDE = DEFAULT_ROW_STRIDE * DEFAULT_HEIGHT
        BUFFER_SIZE = DEFAULT_PAGE_STRIDE
        CURSOR_BDA = 0x450
        VIDEO_PAGE_BDA = 0x462

        attr_reader :width, :height, :text_base, :row_stride, :page_stride

        def initialize(
          width: DEFAULT_WIDTH,
          height: DEFAULT_HEIGHT,
          text_base: TEXT_BASE,
          row_stride: DEFAULT_ROW_STRIDE,
          page_stride: DEFAULT_PAGE_STRIDE
        )
          @width = width
          @height = height
          @text_base = text_base
          @row_stride = row_stride
          @page_stride = page_stride
        end

        def render(memory:, cursor: :auto, debug_lines: [], page: :auto)
          page = active_page(memory) if page == :auto
          lines = Array.new(height) { |row| render_row(memory, row, page) }
          cursor = cursor_from_bda(memory, page: page) if cursor == :auto

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

          panel_width = [width, debug_lines.map(&:length).max.to_i].max
          panel_lines = debug_lines.map { |line| line.ljust(panel_width)[0, panel_width] }
          panel = []
          panel << "+" << ("-" * panel_width) << "+"
          panel = ["+#{'-' * panel_width}+"]
          panel.concat(panel_lines.map { |line| "|#{line}|" })
          panel << "+#{'-' * panel_width}+"

          ([lines.join("\n"), *panel]).join("\n")
        end

        def cursor_from_bda(memory, page: :auto)
          page = active_page(memory) if page == :auto
          base = CURSOR_BDA + (page.to_i * 2)

          if memory.respond_to?(:key?) &&
             !memory.key?(base) &&
             !memory.key?(base + 1)
            return nil
          end

          low = read_byte(memory, base)
          high = read_byte(memory, base + 1)
          { row: high, col: low }
        end

        private

        def render_row(memory, row, page)
          chars = Array.new(width) do |col|
            char_addr = page_base(page) + (row * row_stride) + (col * 2)
            sanitize_char(read_byte(memory, char_addr))
          end
          chars.join
        end

        def page_base(page)
          text_base + (page.to_i * page_stride)
        end

        def active_page(memory)
          read_byte(memory, VIDEO_PAGE_BDA)
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
