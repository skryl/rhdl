module DisplayHelper
  DISPLAY_BASE = 0x800
  DISPLAY_ROWS = 28
  DISPLAY_COLS = 80

  # Initialize display memory with dots
  def clear_display(memory, char = '.')
    (0...DISPLAY_ROWS).each do |row|
      (0...DISPLAY_COLS).each do |col|
        memory.write(DISPLAY_BASE + row * DISPLAY_COLS + col, char.ord)
      end
    end
  end

  # Reads a 28×80 "terminal" from memory starting at +start_addr+.
  # Returns an array of strings (28 rows, each 80 columns).
  def read_display(memory, base_addr = DISPLAY_BASE, rows = DISPLAY_ROWS, cols = DISPLAY_COLS)
    display = []
    (0...rows).each do |row|
      line = ""
      (0...cols).each do |col|
        addr = base_addr + row * cols + col
        char = memory.read(addr)
        if char != '.'.ord && char != '#'.ord && char != 'X'.ord
          puts "Invalid character at #{addr.to_s(16)}: #{char}"
        end
        line << (char == '.'.ord ? '.' : (char == 'X'.ord ? 'X' : (char == '#'.ord ? '#' : '?')))
      end
      display << line
    end
    display
  end

  # Verifies that the display matches the expected pattern
  def verify_display(memory, expected_display, base_addr = DISPLAY_BASE, rows = DISPLAY_ROWS, cols = DISPLAY_COLS)
    display = read_display(memory, base_addr, rows, cols)
    expected_display.each_with_index do |expected_line, index|
      expect(display[index]).to eq(expected_line),
        "Mismatch on line #{index}:\nExpected: #{expected_line}\nGot:      #{display[index]}"
    end
  end

  # Reads and prints the 28×80 "terminal" from memory.
  def print_display(memory, base_addr = DISPLAY_BASE, rows = DISPLAY_ROWS, cols = DISPLAY_COLS)
    puts "\nDisplay contents (base: 0x#{base_addr.to_s(16)}):"
    read_display(memory, base_addr, rows, cols).each { |line| puts line }
  end
end 