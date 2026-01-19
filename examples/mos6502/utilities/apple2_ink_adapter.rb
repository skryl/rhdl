# Apple II Ink TUI Adapter
# Manages communication between Ruby Apple II emulator and Node.js Ink TUI

require 'open3'
require 'json'

module Apple2Harness
  class InkAdapter
    attr_reader :runner, :mode

    def initialize(runner, mode: :isa)
      @runner = runner
      @mode = mode
      @running = false
      @auto_run = false
      @cycles_per_frame = 10_000
      @tui_process = nil
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thread = nil
      @breakpoints = Set.new
      @screen_update_counter = 0
    end

    def running?
      @running
    end

    # Start the TUI
    def run
      @running = true
      start_ink_process

      # Main event loop
      loop do
        break unless @running
        break unless @wait_thread&.alive?

        # Check for input from TUI (non-blocking)
        handle_tui_input

        # Run simulation if auto-running
        if @auto_run && !@runner.halted?
          @runner.run_steps(@cycles_per_frame)

          # Check for breakpoints
          if @breakpoints.include?(@runner.cpu_state[:pc])
            @auto_run = false
            send_event(type: 'breakpoint_hit', address: @runner.cpu_state[:pc])
          end

          # Send screen updates periodically
          @screen_update_counter += 1
          if @screen_update_counter >= 5 || @runner.screen_dirty?
            send_screen_update
            @runner.clear_screen_dirty
            @screen_update_counter = 0
          end

          send_state
        end

        # Check if CPU halted
        if @runner.halted? && @auto_run
          @auto_run = false
          send_event(type: 'halted', pc: @runner.cpu_state[:pc])
          send_state
        end

        sleep(0.016) # ~60fps
      end

      cleanup
    end

    def stop
      @running = false
      send_event(type: 'quit')
    end

    private

    def start_ink_process
      tui_dir = File.expand_path('../../../../tui-ink', __FILE__)

      # Ensure dependencies are installed (seamless like uv)
      node_modules = File.join(tui_dir, 'node_modules')
      unless Dir.exist?(node_modules)
        STDERR.puts "Installing TUI dependencies..."
        system('npm', 'install', '--silent', chdir: tui_dir)
      end

      # Start the Node.js process using npx tsx (no build step needed)
      @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(
        'npx', 'tsx', 'src/apple2/index.tsx',
        chdir: tui_dir
      )

      # Send ready event
      send_event(type: 'ready', mode: @mode.to_s)
      send_log("Apple ][ emulator ready", level: :info)
      send_state
    end

    def handle_tui_input
      return unless @stdout

      begin
        while IO.select([@stdout], nil, nil, 0)
          line = @stdout.gets
          break unless line
          process_command(line.strip)
        end
      rescue IOError, Errno::EPIPE
        @running = false
      end
    end

    def process_command(line)
      cmd = JSON.parse(line, symbolize_names: true) rescue nil
      return unless cmd

      case cmd[:type]
      when 'init'
        send_event(type: 'ready', mode: @mode.to_s)
        send_state

      when 'get_state'
        send_state

      when 'step'
        if @mode == :isa
          @runner.cpu.step
        else
          # HDL mode: step one instruction (multiple cycles)
          @runner.run_steps(1)
        end
        send_state
        send_screen_update if @runner.screen_dirty?

      when 'step_cycle'
        @runner.run_steps(1)
        send_state

      when 'run'
        @auto_run = true
        send_log("Running...", level: :info)

      when 'stop'
        @auto_run = false
        send_log("Stopped", level: :info)
        send_state

      when 'reset'
        @runner.reset
        @auto_run = false
        send_log("CPU Reset", level: :info)
        send_state
        send_screen_update

      when 'set_speed'
        @cycles_per_frame = cmd[:cycles] || 10_000
        send_log("Speed: #{@cycles_per_frame} cycles/frame", level: :info)

      when 'key_press'
        @runner.inject_key(cmd[:ascii])

      when 'read_memory'
        send_memory(cmd[:address], cmd[:length] || 128)

      when 'write_memory'
        @runner.bus.write(cmd[:address], cmd[:value])
        send_log("Wrote $#{cmd[:value].to_s(16).upcase.rjust(2,'0')} to $#{cmd[:address].to_s(16).upcase.rjust(4,'0')}", level: :info)

      when 'set_breakpoint'
        @breakpoints.add(cmd[:address])
        send_log("Breakpoint set at $#{cmd[:address].to_s(16).upcase.rjust(4,'0')}", level: :info)

      when 'clear_breakpoint'
        @breakpoints.delete(cmd[:address])
        send_log("Breakpoint cleared at $#{cmd[:address].to_s(16).upcase.rjust(4,'0')}", level: :info)

      when 'disassemble'
        send_disassembly(cmd[:address], cmd[:count] || 10)

      when 'quit'
        @running = false
      end
    end

    def send_state
      cpu = @runner.cpu_state
      screen = build_screen_data

      state = {
        cpu: {
          pc: cpu[:pc],
          a: cpu[:a],
          x: cpu[:x],
          y: cpu[:y],
          sp: cpu[:sp],
          p: cpu[:p],
          cycles: cpu[:cycles],
          halted: cpu[:halted] || false
        },
        screen: screen,
        running: @auto_run,
        speed: @cycles_per_frame,
        mode: @mode.to_s
      }

      send_event(type: 'state', state: state)
    end

    def send_screen_update
      screen = build_screen_data
      send_event(type: 'screen_update', screen: screen)
    end

    def build_screen_data
      rows = @runner.read_screen_array
      {
        rows: rows,
        dirty: @runner.screen_dirty?
      }
    end

    def send_memory(address, length)
      bytes = []
      length.times do |i|
        bytes << @runner.bus.read(address + i)
      end

      send_event(type: 'memory', dump: {
        address: address,
        bytes: bytes
      })
    end

    def send_disassembly(address, count)
      instructions = []
      addr = address

      count.times do
        bytes, mnemonic, operand = disassemble_instruction(addr)
        instructions << {
          address: addr,
          bytes: bytes,
          mnemonic: mnemonic,
          operand: operand,
          cycles: 0
        }
        addr += bytes.length
      end

      send_event(type: 'disassembly', instructions: instructions)
    end

    def disassemble_instruction(addr)
      opcode = @runner.bus.read(addr)
      info = OPCODES[opcode] || { mnemonic: '???', mode: :implied, bytes: 1 }

      bytes = [opcode]
      operand = ''

      case info[:mode]
      when :implied, :accumulator
        # No operand

      when :immediate
        val = @runner.bus.read(addr + 1)
        bytes << val
        operand = "#$#{val.to_s(16).upcase.rjust(2, '0')}"

      when :zero_page
        val = @runner.bus.read(addr + 1)
        bytes << val
        operand = "$#{val.to_s(16).upcase.rjust(2, '0')}"

      when :zero_page_x
        val = @runner.bus.read(addr + 1)
        bytes << val
        operand = "$#{val.to_s(16).upcase.rjust(2, '0')},X"

      when :zero_page_y
        val = @runner.bus.read(addr + 1)
        bytes << val
        operand = "$#{val.to_s(16).upcase.rjust(2, '0')},Y"

      when :absolute
        lo = @runner.bus.read(addr + 1)
        hi = @runner.bus.read(addr + 2)
        bytes << lo << hi
        operand = "$#{((hi << 8) | lo).to_s(16).upcase.rjust(4, '0')}"

      when :absolute_x
        lo = @runner.bus.read(addr + 1)
        hi = @runner.bus.read(addr + 2)
        bytes << lo << hi
        operand = "$#{((hi << 8) | lo).to_s(16).upcase.rjust(4, '0')},X"

      when :absolute_y
        lo = @runner.bus.read(addr + 1)
        hi = @runner.bus.read(addr + 2)
        bytes << lo << hi
        operand = "$#{((hi << 8) | lo).to_s(16).upcase.rjust(4, '0')},Y"

      when :indirect
        lo = @runner.bus.read(addr + 1)
        hi = @runner.bus.read(addr + 2)
        bytes << lo << hi
        operand = "($#{((hi << 8) | lo).to_s(16).upcase.rjust(4, '0')})"

      when :indirect_x
        val = @runner.bus.read(addr + 1)
        bytes << val
        operand = "($#{val.to_s(16).upcase.rjust(2, '0')},X)"

      when :indirect_y
        val = @runner.bus.read(addr + 1)
        bytes << val
        operand = "($#{val.to_s(16).upcase.rjust(2, '0')}),Y"

      when :relative
        val = @runner.bus.read(addr + 1)
        bytes << val
        offset = val < 128 ? val : val - 256
        target = addr + 2 + offset
        operand = "$#{target.to_s(16).upcase.rjust(4, '0')}"
      end

      [bytes, info[:mnemonic], operand]
    end

    def send_log(message, level: :info)
      send_event(type: 'log', message: message, level: level.to_s)
    end

    def send_event(event)
      return unless @stdin
      @stdin.puts(JSON.generate(event))
      @stdin.flush
    rescue Errno::EPIPE, IOError
      # TUI process died
    end

    def cleanup
      @stdin&.close
      @stdout&.close
      @stderr&.close
      @wait_thread&.value rescue nil
    end

    # 6502 opcode table for disassembly
    OPCODES = {
      0x00 => { mnemonic: 'BRK', mode: :implied },
      0x01 => { mnemonic: 'ORA', mode: :indirect_x },
      0x05 => { mnemonic: 'ORA', mode: :zero_page },
      0x06 => { mnemonic: 'ASL', mode: :zero_page },
      0x08 => { mnemonic: 'PHP', mode: :implied },
      0x09 => { mnemonic: 'ORA', mode: :immediate },
      0x0A => { mnemonic: 'ASL', mode: :accumulator },
      0x0D => { mnemonic: 'ORA', mode: :absolute },
      0x0E => { mnemonic: 'ASL', mode: :absolute },
      0x10 => { mnemonic: 'BPL', mode: :relative },
      0x11 => { mnemonic: 'ORA', mode: :indirect_y },
      0x15 => { mnemonic: 'ORA', mode: :zero_page_x },
      0x16 => { mnemonic: 'ASL', mode: :zero_page_x },
      0x18 => { mnemonic: 'CLC', mode: :implied },
      0x19 => { mnemonic: 'ORA', mode: :absolute_y },
      0x1D => { mnemonic: 'ORA', mode: :absolute_x },
      0x1E => { mnemonic: 'ASL', mode: :absolute_x },
      0x20 => { mnemonic: 'JSR', mode: :absolute },
      0x21 => { mnemonic: 'AND', mode: :indirect_x },
      0x24 => { mnemonic: 'BIT', mode: :zero_page },
      0x25 => { mnemonic: 'AND', mode: :zero_page },
      0x26 => { mnemonic: 'ROL', mode: :zero_page },
      0x28 => { mnemonic: 'PLP', mode: :implied },
      0x29 => { mnemonic: 'AND', mode: :immediate },
      0x2A => { mnemonic: 'ROL', mode: :accumulator },
      0x2C => { mnemonic: 'BIT', mode: :absolute },
      0x2D => { mnemonic: 'AND', mode: :absolute },
      0x2E => { mnemonic: 'ROL', mode: :absolute },
      0x30 => { mnemonic: 'BMI', mode: :relative },
      0x31 => { mnemonic: 'AND', mode: :indirect_y },
      0x35 => { mnemonic: 'AND', mode: :zero_page_x },
      0x36 => { mnemonic: 'ROL', mode: :zero_page_x },
      0x38 => { mnemonic: 'SEC', mode: :implied },
      0x39 => { mnemonic: 'AND', mode: :absolute_y },
      0x3D => { mnemonic: 'AND', mode: :absolute_x },
      0x3E => { mnemonic: 'ROL', mode: :absolute_x },
      0x40 => { mnemonic: 'RTI', mode: :implied },
      0x41 => { mnemonic: 'EOR', mode: :indirect_x },
      0x45 => { mnemonic: 'EOR', mode: :zero_page },
      0x46 => { mnemonic: 'LSR', mode: :zero_page },
      0x48 => { mnemonic: 'PHA', mode: :implied },
      0x49 => { mnemonic: 'EOR', mode: :immediate },
      0x4A => { mnemonic: 'LSR', mode: :accumulator },
      0x4C => { mnemonic: 'JMP', mode: :absolute },
      0x4D => { mnemonic: 'EOR', mode: :absolute },
      0x4E => { mnemonic: 'LSR', mode: :absolute },
      0x50 => { mnemonic: 'BVC', mode: :relative },
      0x51 => { mnemonic: 'EOR', mode: :indirect_y },
      0x55 => { mnemonic: 'EOR', mode: :zero_page_x },
      0x56 => { mnemonic: 'LSR', mode: :zero_page_x },
      0x58 => { mnemonic: 'CLI', mode: :implied },
      0x59 => { mnemonic: 'EOR', mode: :absolute_y },
      0x5D => { mnemonic: 'EOR', mode: :absolute_x },
      0x5E => { mnemonic: 'LSR', mode: :absolute_x },
      0x60 => { mnemonic: 'RTS', mode: :implied },
      0x61 => { mnemonic: 'ADC', mode: :indirect_x },
      0x65 => { mnemonic: 'ADC', mode: :zero_page },
      0x66 => { mnemonic: 'ROR', mode: :zero_page },
      0x68 => { mnemonic: 'PLA', mode: :implied },
      0x69 => { mnemonic: 'ADC', mode: :immediate },
      0x6A => { mnemonic: 'ROR', mode: :accumulator },
      0x6C => { mnemonic: 'JMP', mode: :indirect },
      0x6D => { mnemonic: 'ADC', mode: :absolute },
      0x6E => { mnemonic: 'ROR', mode: :absolute },
      0x70 => { mnemonic: 'BVS', mode: :relative },
      0x71 => { mnemonic: 'ADC', mode: :indirect_y },
      0x75 => { mnemonic: 'ADC', mode: :zero_page_x },
      0x76 => { mnemonic: 'ROR', mode: :zero_page_x },
      0x78 => { mnemonic: 'SEI', mode: :implied },
      0x79 => { mnemonic: 'ADC', mode: :absolute_y },
      0x7D => { mnemonic: 'ADC', mode: :absolute_x },
      0x7E => { mnemonic: 'ROR', mode: :absolute_x },
      0x81 => { mnemonic: 'STA', mode: :indirect_x },
      0x84 => { mnemonic: 'STY', mode: :zero_page },
      0x85 => { mnemonic: 'STA', mode: :zero_page },
      0x86 => { mnemonic: 'STX', mode: :zero_page },
      0x88 => { mnemonic: 'DEY', mode: :implied },
      0x8A => { mnemonic: 'TXA', mode: :implied },
      0x8C => { mnemonic: 'STY', mode: :absolute },
      0x8D => { mnemonic: 'STA', mode: :absolute },
      0x8E => { mnemonic: 'STX', mode: :absolute },
      0x90 => { mnemonic: 'BCC', mode: :relative },
      0x91 => { mnemonic: 'STA', mode: :indirect_y },
      0x94 => { mnemonic: 'STY', mode: :zero_page_x },
      0x95 => { mnemonic: 'STA', mode: :zero_page_x },
      0x96 => { mnemonic: 'STX', mode: :zero_page_y },
      0x98 => { mnemonic: 'TYA', mode: :implied },
      0x99 => { mnemonic: 'STA', mode: :absolute_y },
      0x9A => { mnemonic: 'TXS', mode: :implied },
      0x9D => { mnemonic: 'STA', mode: :absolute_x },
      0xA0 => { mnemonic: 'LDY', mode: :immediate },
      0xA1 => { mnemonic: 'LDA', mode: :indirect_x },
      0xA2 => { mnemonic: 'LDX', mode: :immediate },
      0xA4 => { mnemonic: 'LDY', mode: :zero_page },
      0xA5 => { mnemonic: 'LDA', mode: :zero_page },
      0xA6 => { mnemonic: 'LDX', mode: :zero_page },
      0xA8 => { mnemonic: 'TAY', mode: :implied },
      0xA9 => { mnemonic: 'LDA', mode: :immediate },
      0xAA => { mnemonic: 'TAX', mode: :implied },
      0xAC => { mnemonic: 'LDY', mode: :absolute },
      0xAD => { mnemonic: 'LDA', mode: :absolute },
      0xAE => { mnemonic: 'LDX', mode: :absolute },
      0xB0 => { mnemonic: 'BCS', mode: :relative },
      0xB1 => { mnemonic: 'LDA', mode: :indirect_y },
      0xB4 => { mnemonic: 'LDY', mode: :zero_page_x },
      0xB5 => { mnemonic: 'LDA', mode: :zero_page_x },
      0xB6 => { mnemonic: 'LDX', mode: :zero_page_y },
      0xB8 => { mnemonic: 'CLV', mode: :implied },
      0xB9 => { mnemonic: 'LDA', mode: :absolute_y },
      0xBA => { mnemonic: 'TSX', mode: :implied },
      0xBC => { mnemonic: 'LDY', mode: :absolute_x },
      0xBD => { mnemonic: 'LDA', mode: :absolute_x },
      0xBE => { mnemonic: 'LDX', mode: :absolute_y },
      0xC0 => { mnemonic: 'CPY', mode: :immediate },
      0xC1 => { mnemonic: 'CMP', mode: :indirect_x },
      0xC4 => { mnemonic: 'CPY', mode: :zero_page },
      0xC5 => { mnemonic: 'CMP', mode: :zero_page },
      0xC6 => { mnemonic: 'DEC', mode: :zero_page },
      0xC8 => { mnemonic: 'INY', mode: :implied },
      0xC9 => { mnemonic: 'CMP', mode: :immediate },
      0xCA => { mnemonic: 'DEX', mode: :implied },
      0xCC => { mnemonic: 'CPY', mode: :absolute },
      0xCD => { mnemonic: 'CMP', mode: :absolute },
      0xCE => { mnemonic: 'DEC', mode: :absolute },
      0xD0 => { mnemonic: 'BNE', mode: :relative },
      0xD1 => { mnemonic: 'CMP', mode: :indirect_y },
      0xD5 => { mnemonic: 'CMP', mode: :zero_page_x },
      0xD6 => { mnemonic: 'DEC', mode: :zero_page_x },
      0xD8 => { mnemonic: 'CLD', mode: :implied },
      0xD9 => { mnemonic: 'CMP', mode: :absolute_y },
      0xDD => { mnemonic: 'CMP', mode: :absolute_x },
      0xDE => { mnemonic: 'DEC', mode: :absolute_x },
      0xE0 => { mnemonic: 'CPX', mode: :immediate },
      0xE1 => { mnemonic: 'SBC', mode: :indirect_x },
      0xE4 => { mnemonic: 'CPX', mode: :zero_page },
      0xE5 => { mnemonic: 'SBC', mode: :zero_page },
      0xE6 => { mnemonic: 'INC', mode: :zero_page },
      0xE8 => { mnemonic: 'INX', mode: :implied },
      0xE9 => { mnemonic: 'SBC', mode: :immediate },
      0xEA => { mnemonic: 'NOP', mode: :implied },
      0xEC => { mnemonic: 'CPX', mode: :absolute },
      0xED => { mnemonic: 'SBC', mode: :absolute },
      0xEE => { mnemonic: 'INC', mode: :absolute },
      0xF0 => { mnemonic: 'BEQ', mode: :relative },
      0xF1 => { mnemonic: 'SBC', mode: :indirect_y },
      0xF5 => { mnemonic: 'SBC', mode: :zero_page_x },
      0xF6 => { mnemonic: 'INC', mode: :zero_page_x },
      0xF8 => { mnemonic: 'SED', mode: :implied },
      0xF9 => { mnemonic: 'SBC', mode: :absolute_y },
      0xFD => { mnemonic: 'SBC', mode: :absolute_x },
      0xFE => { mnemonic: 'INC', mode: :absolute_x },
    }.freeze
  end
end
