# frozen_string_literal: true

require "io/console"

require_relative "../display_adapter"
require_relative "../runners/headless_runner"

module RHDL
  module Examples
    module AO486
      module Tasks
        # Interactive/headless AO486 runner surface.
        class RunTask
          ESC = "\e"
          CLEAR_SCREEN = "#{ESC}[2J"
          MOVE_HOME = "#{ESC}[H"
          HIDE_CURSOR = "#{ESC}[?25l"
          SHOW_CURSOR = "#{ESC}[?25h"
          FRAME_INTERVAL_SECONDS = 0.033
          MAX_WORK_SLICE_SECONDS = 0.020
          MAX_BUDGET_FRAMES = 8
          DEFAULT_SPEED = 256
          DEFAULT_HEADLESS_CYCLES = 256
          DEFAULT_PROGRAM_BASE_ADDRESS = 0x000F_FFF0
          DEFAULT_DATA_CHECK_ADDRESSES = [0x0000_0200].freeze
          DEFAULT_BIOS_SYSTEM_RELATIVE_PATH = File.join("examples", "ao486", "software", "bin", "boot0.rom")
          DEFAULT_BIOS_VIDEO_RELATIVE_PATH = File.join("examples", "ao486", "software", "bin", "boot1.rom")
          DEFAULT_DOS_IMAGE_RELATIVE_PATH = File.join("examples", "ao486", "software", "images", "dos4.img")
          FALLBACK_DOS_IMAGE_RELATIVE_PATH = File.join("examples", "ao486", "software", "images", "fdboot.img")
          SUPPORTED_MODES = %i[ir verilator arcilator].freeze
          SUPPORTED_IR_BACKENDS = %i[compiler interpreter jit].freeze

          attr_reader :runner, :options

          def initialize(options = {}, runner_class: HeadlessRunner, out: $stdout)
            @options = options
            @out = out
            @mode = normalize_mode(options[:mode] || :ir)
            @sim_backend = normalize_sim(options[:sim] || default_sim_backend(@mode))
            @debug = !!options[:debug]
            @headless = !!options[:headless]
            @io_mode = (options[:io] || :vga).to_sym
            @cycles_per_frame = [integer_option(options[:speed], default_speed(@mode, @sim_backend)), 1].max
            @headless_cycles = integer_option(options[:cycles], nil)
            @program_base_address = integer_option(options[:address], DEFAULT_PROGRAM_BASE_ADDRESS)
            @data_check_addresses = normalize_data_check_addresses(options[:data_check_addresses])
            @bios = !!options[:bios]
            @bios_system = options[:bios_system]
            @bios_video = options[:bios_video]
            @boot_addr = integer_option(options[:boot_addr], nil)
            @disk = options[:disk]
            @trace = nil
            @trace_cursor = 0
            @live_state = {}
            @cycle_budget = 0
            @running = false
            @stty_state = nil
            @keyboard_mode = :terminal

            @runner = runner_class.new(**headless_runner_options)
            @display_adapter = RHDL::Examples::AO486::DisplayAdapter.new(
              io_mode: @io_mode,
              debug: @debug
            )
          end

          def software_path(path = nil)
            base = File.expand_path("../../software", __dir__)
            return base if path.nil? || path.empty?

            File.expand_path(path, base)
          end

          def load_program(path, base_addr: @program_base_address)
            @program_binary = File.expand_path(path.to_s)
            @program_base_address = Integer(base_addr)
          end

          def run
            validate_run_inputs!
            trap("INT") { @running = false }
            trap("TERM") { @running = false }

            @running = true
            @headless ? run_headless : run_interactive
          ensure
            cleanup_terminal
          end

          private

          def run_headless
            cycles = @headless_cycles || DEFAULT_HEADLESS_CYCLES
            trace = execute_trace(cycles: cycles)
            render_headless_summary(trace: trace, cycles: cycles)
            trace
          end

          def run_interactive
            return run_interactive_live if live_mode?

            run_interactive_trace
          end

          def run_interactive_trace
            @trace = execute_trace(cycles: @headless_cycles || @cycles_per_frame)
            @trace_cursor = 0

            @out.puts startup_banner
            @out.puts "Press Ctrl+C to exit."
            @out.puts "Debug mode enabled (+/- adjust speed)." if @debug
            @out.puts "ESC toggles command mode when debug is enabled." if @debug

            setup_terminal_input_mode
            if tty_out?
              @out.print CLEAR_SCREEN
              @out.print HIDE_CURSOR
            end

            loop do
              break unless @running
              break if replay_length <= 0

              frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              handle_keyboard_input
              @trace_cursor = [@trace_cursor + @cycles_per_frame, replay_length].min
              render_interactive_frame
              break if @trace_cursor >= replay_length

              frame_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
              sleep_time = FRAME_INTERVAL_SECONDS - frame_elapsed
              sleep(sleep_time) if sleep_time > 0
            end

            @trace
          end

          def run_interactive_live
            prepare_live_session!
            @live_state = runner.state
            @cycle_budget = 0

            @out.puts startup_banner
            @out.puts "Press Ctrl+C to exit."
            @out.puts "Debug mode enabled (+/- adjust speed)." if @debug
            @out.puts "ESC toggles command mode when debug is enabled." if @debug

            setup_terminal_input_mode
            if tty_out?
              @out.print CLEAR_SCREEN
              @out.print HIDE_CURSOR
            end

            while @running
              frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              handle_keyboard_input
              run_live_budgeted(frame_start: frame_start)
              @live_state = runner.state
              render_interactive_frame

              frame_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
              sleep_time = FRAME_INTERVAL_SECONDS - frame_elapsed
              sleep(sleep_time) if sleep_time > 0
            end

            @live_state
          end

          def live_mode?
            runner.respond_to?(:supports_live_cycles?) && runner.supports_live_cycles?
          end

          def prepare_live_session!
            if @bios && (@program_binary.nil? || @program_binary.empty?)
              unless runner.respond_to?(:load_dos_boot)
                raise NotImplementedError, "#{runner.class} does not support live BIOS boot sessions"
              end

              runner.load_dos_boot(
                bios_system: resolved_bios_system_path,
                bios_video: resolved_bios_video_path,
                dos_image: resolved_dos_image_path
              )
              return
            end

            runner.load_program(
              program_binary: @program_binary,
              program_base_address: @program_base_address,
              data_check_addresses: @data_check_addresses
            )
          end

          def run_live_budgeted(frame_start:)
            max_budget = [@cycles_per_frame * MAX_BUDGET_FRAMES, @cycles_per_frame].max
            @cycle_budget = [@cycle_budget + @cycles_per_frame, max_budget].min
            return if @cycle_budget <= 0

            while @running && @cycle_budget > 0
              step_cycles = [@cycle_budget, @cycles_per_frame].min
              runner.run_cycles(step_cycles)
              @cycle_budget -= step_cycles
              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
              break if elapsed >= MAX_WORK_SLICE_SECONDS
            end
          end

          def execute_program(cycles:)
            runner.run_program(
              program_binary: @program_binary,
              cycles: Integer(cycles),
              program_base_address: @program_base_address,
              data_check_addresses: @data_check_addresses
            )
          end

          def execute_trace(cycles:)
            return execute_program(cycles: cycles) unless @bios && (@program_binary.nil? || @program_binary.empty?)

            runner.run_dos_boot(
              bios_system: resolved_bios_system_path,
              bios_video: resolved_bios_video_path,
              dos_image: resolved_dos_image_path,
              cycles: Integer(cycles)
            )
          end

          def render_headless_summary(trace:, cycles:)
            pc_sequence = Array(trace.fetch("pc_sequence", []))
            instruction_sequence = Array(trace.fetch("instruction_sequence", []))
            writes = Array(trace.fetch("memory_writes", []))
            final_pc = pc_sequence.last || 0
            final_inst = instruction_sequence.last || 0

            @out.puts format(
              "AO486 Headless  mode=%s sim=%s io=%s cycles=%d pc=0x%08x inst=0x%08x writes=%d",
              @mode,
              @sim_backend,
              @io_mode,
              Integer(cycles),
              Integer(final_pc) & 0xFFFF_FFFF,
              Integer(final_inst) & 0xFFFF_FFFF,
              writes.length
            )

            return if @io_mode != :vga

            render_memory_window(trace: trace, limit: 8)
          end

          def render_interactive_frame
            frame = live_mode? ? interactive_live_frame_text : interactive_trace_frame_text
            if tty_out?
              @out.print MOVE_HOME
              @out.print frame
            else
              @out.puts frame
            end
            @out.flush if @out.respond_to?(:flush)
          end

          def interactive_trace_frame_text
            @display_adapter.render_trace_frame(
              mode: @mode,
              sim_backend: @sim_backend,
              speed: @cycles_per_frame,
              trace: @trace,
              trace_cursor: @trace_cursor,
              replay_length: replay_length,
              program_base_address: @program_base_address,
              boot_addr: @boot_addr,
              bios: @bios,
              bios_system: @bios_system,
              bios_video: @bios_video,
              disk: @disk,
              root_path: root_path
            )
          end

          def interactive_live_frame_text
            @display_adapter.render_live_frame(
              mode: @mode,
              sim_backend: @sim_backend,
              speed: @cycles_per_frame,
              state: @live_state,
              program_base_address: @program_base_address,
              boot_addr: @boot_addr,
              bios: @bios,
              bios_system: @bios_system,
              bios_video: @bios_video,
              disk: @disk,
              root_path: root_path
            )
          end

          def render_memory_window(trace:, limit:)
            rows = @display_adapter.memory_lines(memory: trace.fetch("memory_contents", {}), limit: limit)
            return if rows.empty?

            @out.puts "VGA memory window:"
            rows.each do |line|
              @out.puts "  #{line}"
            end
          end

          def replay_length
            Array(@trace.fetch("pc_sequence", [])).length
          end

          def handle_keyboard_input
            return unless $stdin.tty?
            return unless IO.select([$stdin], nil, nil, 0)

            data = $stdin.read_nonblock(256, exception: false)
            return if data.nil? || data == :wait_readable || data.empty?

            process_keyboard_bytes(data.bytes)
          rescue IO::WaitReadable, Errno::EAGAIN, EOFError
            nil
          end

          def process_keyboard_bytes(bytes)
            raw = Array(bytes).map { |entry| Integer(entry) & 0xFF }
            idx = 0

            while idx < raw.length
              value = raw[idx]

              if value == 3 # Ctrl+C
                @running = false
                break
              end

              if value == 27 && @debug
                # Keep escape sequences (for arrows/etc.) available to target terminal IO.
                if idx + 1 < raw.length && raw[idx + 1] == 91
                  seq = [raw[idx], raw[idx + 1], raw[idx + 2]].compact
                  forward_keyboard_bytes(seq)
                  idx += seq.length
                  next
                end

                @keyboard_mode = (@keyboard_mode == :terminal ? :command : :terminal)
                idx += 1
                next
              end

              if @debug && @keyboard_mode == :command
                handle_command_key(value)
              else
                forward_keyboard_bytes([value])
              end

              idx += 1
            end
          end

          def handle_command_key(value)
            case value
            when 43, 61 # +, =
              @cycles_per_frame += [@cycles_per_frame / 10, 1].max
            when 45, 95 # -, _
              @cycles_per_frame = [@cycles_per_frame - [@cycles_per_frame / 10, 1].max, 1].max
            when 81, 113 # Q/q
              @running = false
            end
          end

          def forward_keyboard_bytes(bytes)
            return unless runner.respond_to?(:send_keyboard_bytes)

            mapped = normalize_keyboard_bytes(bytes)
            runner.send_keyboard_bytes(mapped) unless mapped.empty?
          end

          def normalize_keyboard_bytes(bytes)
            Array(bytes).map do |value|
              byte = Integer(value) & 0xFF
              case byte
              when 10, 13 then 13
              when 127 then 8
              else byte
              end
            end
          rescue ArgumentError, TypeError
            []
          end

          def validate_run_inputs!
            return if @program_binary && !@program_binary.empty?

            return validate_bios_inputs! if @bios

            raise ArgumentError, "program binary is required"
          end

          def validate_bios_inputs!
            ensure_existing_file!(resolved_bios_system_path, "BIOS system ROM")
            ensure_existing_file!(resolved_bios_video_path, "BIOS video ROM")
            ensure_existing_file!(resolved_dos_image_path, "DOS disk image")
          end

          def ensure_existing_file!(path, label)
            raise ArgumentError, "#{label} not found: #{path}" unless File.file?(path)
          end

          def resolved_bios_system_path
            value = @bios_system.to_s.strip
            return File.expand_path(value, root_path) unless value.empty?

            File.expand_path(DEFAULT_BIOS_SYSTEM_RELATIVE_PATH, root_path)
          end

          def resolved_bios_video_path
            value = @bios_video.to_s.strip
            return File.expand_path(value, root_path) unless value.empty?

            File.expand_path(DEFAULT_BIOS_VIDEO_RELATIVE_PATH, root_path)
          end

          def resolved_dos_image_path
            value = @disk.to_s.strip
            return File.expand_path(value, root_path) unless value.empty?

            primary = File.expand_path(DEFAULT_DOS_IMAGE_RELATIVE_PATH, root_path)
            return primary if File.file?(primary)

            File.expand_path(FALLBACK_DOS_IMAGE_RELATIVE_PATH, root_path)
          end

          def root_path
            File.expand_path(options[:cwd] || Dir.pwd)
          end

          def headless_runner_options
            root = File.expand_path(options[:cwd] || Dir.pwd)
            out_dir = File.expand_path(options[:out_dir] || File.join(root, "examples", "ao486", "hdl"), root)
            vendor_root = File.expand_path(options[:vendor_root] || File.join(out_dir, "vendor", "source_hdl"), root)
            runner_options = {
              mode: @mode,
              out_dir: out_dir,
              vendor_root: vendor_root,
              cwd: root
            }
            if @mode == :ir
              runner_options[:backend] = @sim_backend
              runner_options[:allow_fallback] = false
            end
            if @mode == :verilator
              runner_options[:source_mode] = (options[:source_mode] || :generated).to_sym
            end
            runner_options
          end

          def startup_banner
            "AO486 Interactive Runner"
          end

          def normalize_mode(value)
            mode = value.to_sym
            return mode if SUPPORTED_MODES.include?(mode)

            raise ArgumentError, "Unsupported mode #{value.inspect}. Use ir, verilator, or arcilator."
          end

          def normalize_sim(value)
            backend = case value.to_sym
                      when :compile then :compiler
                      when :interpret then :interpreter
                      else value.to_sym
                      end
            return backend if SUPPORTED_IR_BACKENDS.include?(backend)
            return :compiler if @mode != :ir

            raise ArgumentError, "Unsupported IR backend #{value.inspect}. Use interpret, jit, or compile."
          end

          def normalize_data_check_addresses(value)
            values = Array(value).compact.map { |entry| Integer(entry) }
            values.empty? ? DEFAULT_DATA_CHECK_ADDRESSES : values
          end

          def default_sim_backend(mode)
            if mode == :ir
              return :compiler if RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
              return :interpreter if RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
              return :jit if RHDL::Codegen::IR::IR_JIT_AVAILABLE
              return :compiler
            end

            :compiler
          end

          def default_speed(mode, sim_backend)
            case mode
            when :ir
              sim_backend == :compiler ? 100_000 : 10_000
            when :verilator, :arcilator
              100_000
            else
              DEFAULT_SPEED
            end
          end

          def integer_option(value, fallback)
            return fallback if value.nil?

            Integer(value)
          rescue ArgumentError, TypeError
            fallback
          end

          def setup_terminal_input_mode
            return unless $stdin.tty?

            state = `stty -g`.strip
            return if state.empty?

            @stty_state = state
            system("stty -echo -icanon min 0 time 0")
          end

          def cleanup_terminal
            restore_terminal_input_mode
            return unless tty_out?

            @out.print SHOW_CURSOR
            @out.print "\n"
            @out.flush if @out.respond_to?(:flush)
          end

          def restore_terminal_input_mode
            return if @stty_state.nil? || @stty_state.empty?

            system("stty #{@stty_state}")
            @stty_state = nil
          end

          def tty_out?
            @out.respond_to?(:tty?) && @out.tty?
          end
        end
      end
    end
  end
end
