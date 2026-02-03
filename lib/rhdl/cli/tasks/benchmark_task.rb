# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for benchmarking
      class BenchmarkTask < Task
        def run
          case options[:type]
          when :gates
            benchmark_gates
          when :tests
            benchmark_tests
          when :timing
            benchmark_timing
          when :quick
            benchmark_quick
          when :ir, :apple2
            benchmark_apple2
          when :mos6502
            benchmark_mos6502
          when :gameboy
            benchmark_gameboy
          else
            benchmark_gates
          end
        end

        # Benchmark gate-level simulation
        def benchmark_gates
          require 'rhdl'

          lanes = (ENV['RHDL_BENCH_LANES'] || options[:lanes] || '64').to_i
          cycles = (ENV['RHDL_BENCH_CYCLES'] || options[:cycles] || '100000').to_i

          puts "Gate-level Simulation Benchmark"
          puts '=' * 50
          puts "Lanes: #{lanes}"
          puts "Cycles: #{cycles}"
          puts

          not_gate = RHDL::HDL::NotGate.new('inv')
          dff = RHDL::HDL::DFlipFlop.new('reg')

          RHDL::Sim::Component.connect(dff.outputs[:q], not_gate.inputs[:a])
          RHDL::Sim::Component.connect(not_gate.outputs[:y], dff.inputs[:d])

          sim = RHDL::Export.gate_level([not_gate, dff], backend: :interpreter, lanes: lanes, name: 'bench_toggle')

          sim.poke('reg.rst', 0)
          sim.poke('reg.en', (1 << lanes) - 1)

          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          cycles.times { sim.tick }
          finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          elapsed = finish - start
          rate = cycles / elapsed
          puts "Result: #{cycles} cycles in #{format('%.3f', elapsed)}s (#{format('%.2f', rate)} cycles/s)"
        end

        # Benchmark tests (profile RSpec)
        def benchmark_tests
          count = options[:count] || 20
          pattern = options[:pattern] || 'spec/'

          puts "Running RSpec with profiling (showing #{count} slowest tests)..."
          puts '=' * 60

          system("#{rspec_cmd} --profile #{count} --format progress #{pattern}")
        end

        # Detailed per-file timing analysis
        def benchmark_timing
          require 'benchmark'

          puts_header("RHDL Test Suite Timing Analysis")

          spec_files = Dir.glob('spec/**/*_spec.rb').sort
          groups = spec_files.group_by { |f| File.dirname(f).sub('spec/', '') }

          results = []

          groups.each do |group, files|
            group_time = 0.0
            file_times = []

            files.each do |file|
              print "."
              $stdout.flush

              start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              output = `#{rspec_cmd} #{file} --format progress 2>&1`
              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

              status = output.include?('0 failures') ? :pass : :fail

              file_times << {
                file: file,
                time: elapsed,
                status: status
              }
              group_time += elapsed
            end

            results << {
              group: group,
              total_time: group_time,
              files: file_times.sort_by { |f| -f[:time] }
            }
          end

          puts
          puts

          results.sort_by! { |r| -r[:total_time] }

          puts "Test Groups by Total Time"
          puts_separator
          results.each do |r|
            puts "#{r[:group].ljust(40)} #{format('%.2f', r[:total_time])}s (#{r[:files].length} files)"
          end

          puts
          puts "Top 15 Slowest Test Files"
          puts_separator

          all_files = results.flat_map { |r| r[:files] }.sort_by { |f| -f[:time] }
          all_files.first(15).each_with_index do |f, i|
            status_icon = f[:status] == :pass ? '' : ' [FAIL]'
            puts "#{(i + 1).to_s.rjust(2)}. #{format('%.2f', f[:time])}s  #{f[:file]}#{status_icon}"
          end

          total_time = results.sum { |r| r[:total_time] }
          puts
          puts '=' * 60
          puts "Total test time: #{format('%.2f', total_time)}s"
          puts "Total test files: #{all_files.length}"
        end

        # Quick benchmark by category
        def benchmark_quick
          require 'benchmark'

          puts_header("RHDL Test Suite Quick Benchmark")

          categories = {
            'HDL Components' => 'spec/rhdl/hdl/',
            '6502 CPU' => 'spec/examples/mos6502/',
            'Core Framework' => 'spec/rhdl/',
            'All Tests' => 'spec/'
          }

          results = []

          categories.each do |name, path|
            next unless Dir.exist?(path)

            files = Dir.glob("#{path}**/*_spec.rb")
            next if files.empty?

            print "Running #{name}..."
            $stdout.flush

            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            output = `#{rspec_cmd} #{path} --format progress 2>&1`
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

            match = output.match(/(\d+) examples?, (\d+) failures?/)
            examples = match ? match[1].to_i : 0
            failures = match ? match[2].to_i : 0

            results << {
              name: name,
              time: elapsed,
              examples: examples,
              failures: failures,
              files: files.length
            }

            puts " done (#{format('%.2f', elapsed)}s)"
          end

          puts
          puts "Results Summary"
          puts_separator
          puts "#{'Category'.ljust(20)} #{'Time'.rjust(10)} #{'Tests'.rjust(8)} #{'Files'.rjust(8)} #{'Rate'.rjust(12)}"
          puts_separator

          results.each do |r|
            rate = r[:examples] > 0 ? format('%.1f', r[:examples] / r[:time]) : 'N/A'
            puts "#{r[:name].ljust(20)} #{format('%8.2f', r[:time])}s #{r[:examples].to_s.rjust(8)} #{r[:files].to_s.rjust(8)} #{rate.rjust(8)} t/s"
          end
        end

        # Benchmark MOS6502 CPU IR with memory bridging (like karateka tests)
        def benchmark_mos6502
          require 'rhdl/codegen'

          # Paths to ROM and memory dump
          rom_path = File.expand_path('../../../../examples/mos6502/software/roms/appleiigo.rom', __dir__)
          karateka_path = File.expand_path('../../../../examples/mos6502/software/disks/karateka_mem.bin', __dir__)

          unless File.exist?(rom_path)
            puts "Error: AppleIIgo ROM not found at #{rom_path}"
            return
          end

          unless File.exist?(karateka_path)
            puts "Error: Karateka memory dump not found at #{karateka_path}"
            return
          end

          cycles = options[:cycles] || 100_000

          puts_header("MOS6502 CPU IR Benchmark - Karateka Game Code")
          puts "Cycles per run: #{cycles}"
          puts "ROM: #{rom_path}"
          puts "Memory dump: #{karateka_path}"
          puts

          # Generate IR once for all runners
          print "Generating RHDL::Examples::MOS6502::CPU IR... "
          $stdout.flush

          require_relative '../../../../examples/mos6502/hdl/cpu'
          require_relative '../../../../examples/mos6502/utilities/apple2/bus'

          ir_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ir = RHDL::Examples::MOS6502::CPU.to_flat_ir
          ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
          ir_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ir_start
          puts "done (#{format('%.3f', ir_elapsed)}s)"

          # Load ROM and memory data
          rom_data = File.binread(rom_path).bytes
          karateka_mem = File.binread(karateka_path).bytes

          # Define runners to benchmark
          runners = [
            { name: 'Interpreter', backend: :interpreter, available_const: :IR_INTERPRETER_AVAILABLE },
            { name: 'JIT', backend: :jit, available_const: :IR_JIT_AVAILABLE },
            { name: 'Compiler', backend: :compiler, available_const: :IR_COMPILER_AVAILABLE },
            { name: 'Verilator', backend: :verilator }
          ]

          results = []

          runners.each do |runner|
            # Skip Interpreter for large cycle counts (too slow)
            if runner[:backend] == :interpreter && cycles > 100_000
              puts "\n#{runner[:name]}: SKIPPED (cycles > 100K, too slow)"
              results << { name: runner[:name], status: :skipped }
              next
            end

            # Check availability
            if runner[:available_const]
              available = RHDL::Codegen::IR.const_get(runner[:available_const]) rescue false
            elsif runner[:backend] == :verilator
              available = verilator_available?
            else
              available = false
            end

            unless available
              puts "\n#{runner[:name]}: SKIPPED (not available)"
              results << { name: runner[:name], status: :skipped }
              next
            end

            print "\n#{runner[:name]}: "
            $stdout.flush

            begin
              # Create simulator and bus
              print "initializing... "
              $stdout.flush
              init_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              is_verilator = runner[:backend] == :verilator
              bus = nil
              sim = nil

              if is_verilator
                require_relative '../../../../examples/mos6502/utilities/runners/verilator_runner'
                sim = RHDL::Examples::MOS6502::VerilatorRunner.new
              else
                bus = RHDL::Examples::MOS6502::Apple2Bus.new("bench_bus")

                sim = case runner[:backend]
                when :interpreter
                  RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
                when :jit
                  RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
                when :compiler
                  RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
                end
              end

              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              # Load ROM and RAM
              print "loading... "
              $stdout.flush

              if is_verilator
                # Verilator: load memory and set reset vector
                sim.load_memory(rom_data, 0xD000)
                sim.load_memory(karateka_mem, 0x0000)
                sim.set_reset_vector(0xB82A)
              else
                # Check if Rust MOS6502 mode is available
                use_rust_memory = sim.respond_to?(:mos6502_mode?) && sim.mos6502_mode?

                # Always load into Ruby bus (needed for reset sequence)
                bus.load_rom(rom_data, base_addr: 0xD000)
                bus.load_ram(karateka_mem, base_addr: 0x0000)
                memory = bus.instance_variable_get(:@memory)
                memory[0xFFFC] = 0x2A  # low byte of $B82A
                memory[0xFFFD] = 0xB8  # high byte of $B82A

                if use_rust_memory
                  # Also load into Rust memory for batched execution
                  sim.mos6502_load_memory(rom_data, 0xD000, true)   # ROM
                  sim.mos6502_load_memory(karateka_mem, 0x0000, false)  # RAM
                  sim.mos6502_set_reset_vector(0xB82A)
                end
              end

              # Reset CPU
              if is_verilator
                sim.reset
              else
                sim.poke('rst', 1)
                sim.poke('rdy', 1)
                sim.poke('irq', 1)
                sim.poke('nmi', 1)
                sim.poke('data_in', 0)
                sim.poke('ext_pc_load_en', 0)
                sim.poke('ext_a_load_en', 0)
                sim.poke('ext_x_load_en', 0)
                sim.poke('ext_y_load_en', 0)
                sim.poke('ext_sp_load_en', 0)

                # Clock tick with memory bridging (Ruby fallback)
                clock_tick = lambda do
                  addr = sim.peek('addr')
                  rw = sim.peek('rw')
                  if rw == 1
                    data = bus.read(addr)
                    sim.poke('data_in', data)
                  else
                    data = sim.peek('data_out')
                    bus.write(addr, data)
                  end
                  sim.poke('clk', 0)
                  sim.tick
                  sim.poke('clk', 1)
                  sim.tick
                end

                # Run reset sequence
                clock_tick.call
                sim.poke('rst', 0)
                6.times { clock_tick.call }
              end

              # Benchmark
              print "running #{cycles} cycles... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              if is_verilator
                sim.run_cycles(cycles)
              elsif use_rust_memory
                # Use batched Rust execution - no FFI per cycle!
                sim.mos6502_run_cycles(cycles)
              else
                # Ruby memory bridging (fallback)
                cycles.times { clock_tick.call }
              end
              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              cycles_per_sec = cycles / run_elapsed
              pc = is_verilator ? sim.pc : sim.peek('reg_pc')

              puts "done"
              puts "  Init time: #{format('%.3f', init_elapsed)}s"
              puts "  Run time:  #{format('%.3f', run_elapsed)}s"
              puts "  Rate:      #{format('%.0f', cycles_per_sec)} cycles/s (#{format('%.2f', cycles_per_sec / 1_000_000)}M/s)"
              puts "  Final PC:  0x#{pc.to_s(16).upcase}"

              results << {
                name: runner[:name],
                status: :success,
                init_time: init_elapsed,
                run_time: run_elapsed,
                cycles_per_sec: cycles_per_sec,
                final_pc: pc
              }
            rescue => e
              puts "FAILED"
              puts "  Error: #{e.message}"
              puts "  #{e.backtrace.first(3).join("\n  ")}" if options[:verbose]
              results << { name: runner[:name], status: :failed, error: e.message }
            end
          end

          print_benchmark_summary(results, cycles)
        end

        # Benchmark Apple2 full system IR (legacy bench:ir)
        def benchmark_apple2
          require 'rhdl/codegen'

          # Paths to ROM and memory dump
          rom_path = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __dir__)
          karateka_path = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __dir__)

          unless File.exist?(rom_path)
            puts "Error: AppleIIgo ROM not found at #{rom_path}"
            puts "Please ensure the ROM file exists."
            return
          end

          unless File.exist?(karateka_path)
            puts "Error: Karateka memory dump not found at #{karateka_path}"
            puts "Please ensure the memory dump file exists."
            return
          end

          # Load ROM and memory data
          rom_data = File.binread(rom_path).bytes
          karateka_mem = File.binread(karateka_path).bytes

          # Modify ROM reset vector to point to game entry ($B82A)
          karateka_rom = rom_data.dup
          karateka_rom[0x2FFC] = 0x2A  # low byte of $B82A
          karateka_rom[0x2FFD] = 0xB8  # high byte of $B82A

          cycles = options[:cycles] || 100_000

          puts_header("Apple2 Full System IR Benchmark - Karateka Game Code")
          puts "Cycles per run: #{cycles}"
          puts "ROM: #{rom_path}"
          puts "Memory dump: #{karateka_path}"
          puts

          # Generate IR once for all runners
          print "Generating Apple2 IR... "
          $stdout.flush

          require_relative '../../../../examples/apple2/hdl'
          ir_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ir = RHDL::Apple2::Apple2.to_flat_ir
          ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
          ir_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ir_start
          puts "done (#{format('%.3f', ir_elapsed)}s)"

          # Define runners to benchmark
          runners = [
            { name: 'Interpreter', backend: :interpreter, available_const: :IR_INTERPRETER_AVAILABLE },
            { name: 'JIT', backend: :jit, available_const: :IR_JIT_AVAILABLE },
            { name: 'Compiler', backend: :compiler, available_const: :IR_COMPILER_AVAILABLE },
            { name: 'Verilator', backend: :verilator }
          ]

          results = []

          runners.each do |runner|
            # Skip Interpreter for large cycle counts (too slow)
            if runner[:backend] == :interpreter && cycles > 100_000
              puts "\n#{runner[:name]}: SKIPPED (cycles > 100K, too slow)"
              results << { name: runner[:name], status: :skipped }
              next
            end

            # Check availability
            if runner[:available_const]
              available = RHDL::Codegen::IR.const_get(runner[:available_const]) rescue false
            elsif runner[:backend] == :verilator
              available = verilator_available?
            else
              available = false
            end

            unless available
              puts "\n#{runner[:name]}: SKIPPED (not available)"
              results << { name: runner[:name], status: :skipped }
              next
            end

            print "\n#{runner[:name]}: "
            $stdout.flush

            begin
              # Create simulator
              print "initializing... "
              $stdout.flush
              init_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              is_verilator = runner[:backend] == :verilator
              sim = case runner[:backend]
              when :interpreter
                RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
              when :jit
                RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
              when :compiler
                RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
              when :verilator
                require_relative '../../../../examples/apple2/utilities/runners/verilator_runner'
                RHDL::Apple2::VerilatorRunner.new(sub_cycles: 14)
              end

              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              # Load ROM and RAM
              print "loading... "
              $stdout.flush
              if is_verilator
                sim.load_rom(karateka_rom, base_addr: 0xD000)
                sim.load_ram(karateka_mem.first(48 * 1024), base_addr: 0)
              else
                sim.apple2_load_rom(karateka_rom)
                sim.apple2_load_ram(karateka_mem.first(48 * 1024), 0)
              end

              # Reset
              if is_verilator
                sim.reset
              else
                sim.poke('reset', 1)
                sim.tick
                sim.poke('reset', 0)
              end

              # Warmup - run a few cycles to get past reset
              if is_verilator
                sim.run_steps(3)
              else
                3.times { sim.apple2_run_cpu_cycles(1, 0, false) }
              end

              # Benchmark
              print "running #{cycles} cycles... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              if is_verilator
                sim.run_steps(cycles)
              else
                sim.apple2_run_cpu_cycles(cycles, 0, false)
              end
              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              cycles_per_sec = cycles / run_elapsed
              pc = is_verilator ? sim.pc : sim.peek('cpu__pc_reg')

              puts "done"
              puts "  Init time: #{format('%.3f', init_elapsed)}s"
              puts "  Run time:  #{format('%.3f', run_elapsed)}s"
              puts "  Rate:      #{format('%.0f', cycles_per_sec)} cycles/s (#{format('%.2f', cycles_per_sec / 1_000_000)}M/s)"
              puts "  Final PC:  0x#{pc.to_s(16).upcase}"

              results << {
                name: runner[:name],
                status: :success,
                init_time: init_elapsed,
                run_time: run_elapsed,
                cycles_per_sec: cycles_per_sec,
                final_pc: pc
              }
            rescue => e
              puts "FAILED"
              puts "  Error: #{e.message}"
              results << { name: runner[:name], status: :failed, error: e.message }
            end
          end

          print_benchmark_summary(results, cycles)
        end

        # Benchmark GameBoy with Prince of Persia ROM
        def benchmark_gameboy
          rom_path = File.expand_path('../../../../examples/gameboy/software/roms/pop.gb', __dir__)

          unless File.exist?(rom_path)
            puts "Error: Prince of Persia ROM not found at #{rom_path}"
            puts "Please ensure the ROM file exists."
            return
          end

          frames = options[:frames] || 1000
          cycles_per_frame = 70224  # 154 scanlines * 456 dots

          puts_header("GameBoy Benchmark - Prince of Persia")
          puts "Frames: #{frames}"
          puts "Cycles per frame: #{cycles_per_frame}"
          puts "Total cycles: #{frames * cycles_per_frame}"
          puts "ROM: #{rom_path}"
          puts

          rom_data = File.binread(rom_path)

          # Define runners to benchmark
          runners = [
            { name: 'IR Compiler', backend: :compile },
            { name: 'Verilator', backend: :verilator }
          ]

          results = []

          runners.each do |runner_config|
            is_verilator = runner_config[:backend] == :verilator

            # Check availability
            if is_verilator
              unless verilator_available?
                puts "\n#{runner_config[:name]}: SKIPPED (not available)"
                results << { name: runner_config[:name], status: :skipped }
                next
              end
            else
              begin
                require_relative '../../../../examples/gameboy/utilities/runners/ir_runner'
                unless RHDL::Codegen::IR::COMPILER_AVAILABLE
                  puts "\n#{runner_config[:name]}: SKIPPED (not available)"
                  results << { name: runner_config[:name], status: :skipped }
                  next
                end
              rescue LoadError => e
                puts "\n#{runner_config[:name]}: SKIPPED (#{e.message})"
                results << { name: runner_config[:name], status: :skipped }
                next
              end
            end

            print "\n#{runner_config[:name]}: "
            $stdout.flush

            begin
              # Initialize runner
              print "initializing... "
              $stdout.flush
              init_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              if is_verilator
                require_relative '../../../../examples/gameboy/utilities/runners/verilator_runner'
                runner = RHDL::GameBoy::VerilatorRunner.new
              else
                runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
              end

              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              # Load ROM
              print "loading... "
              $stdout.flush
              runner.load_rom(rom_data)
              runner.reset

              # Run benchmark
              print "running #{frames} frames... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              if is_verilator
                # Verilator: run until we reach target frames
                while runner.frame_count < frames
                  runner.run_steps(cycles_per_frame)
                end
              else
                # IR: run total cycles
                target_cycles = frames * cycles_per_frame
                runner.run_steps(target_cycles)
              end

              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              total_cycles = runner.cycle_count
              actual_frames = total_cycles / cycles_per_frame
              cycles_per_sec = total_cycles / run_elapsed
              speed_mhz = cycles_per_sec / 1_000_000.0
              pct_realtime = speed_mhz / 4.19 * 100

              puts "done"
              puts "  Init time:  #{format('%.3f', init_elapsed)}s"
              puts "  Run time:   #{format('%.3f', run_elapsed)}s"
              puts "  Frames:     #{actual_frames}"
              puts "  Cycles:     #{total_cycles}"
              puts "  Rate:       #{format('%.0f', cycles_per_sec)} cycles/s (#{format('%.2f', speed_mhz)} MHz)"
              puts "  Speed:      #{format('%.1f', pct_realtime)}% of real GameBoy (4.19 MHz)"

              results << {
                name: runner_config[:name],
                status: :success,
                init_time: init_elapsed,
                run_time: run_elapsed,
                cycles_per_sec: cycles_per_sec,
                frames: actual_frames,
                speed_mhz: speed_mhz
              }
            rescue => e
              puts "FAILED"
              puts "  Error: #{e.message}"
              puts "  #{e.backtrace.first(3).join("\n  ")}" if options[:verbose]
              results << { name: runner_config[:name], status: :failed, error: e.message }
            end
          end

          # Summary
          puts
          puts_header("Summary")
          puts "#{'Runner'.ljust(15)} #{'Status'.ljust(10)} #{'Init'.rjust(10)} #{'Run'.rjust(10)} #{'Frames'.rjust(10)} #{'Speed'.rjust(15)}"
          puts_separator

          results.each do |r|
            if r[:status] == :success
              speed_str = "#{format('%.2f', r[:speed_mhz])} MHz"
              puts "#{r[:name].ljust(15)} #{'OK'.ljust(10)} #{format('%8.3f', r[:init_time])}s #{format('%8.3f', r[:run_time])}s #{r[:frames].to_s.rjust(10)} #{speed_str.rjust(15)}"
            elsif r[:status] == :skipped
              puts "#{r[:name].ljust(15)} #{'SKIP'.ljust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)} #{'-'.rjust(15)}"
            else
              puts "#{r[:name].ljust(15)} #{'FAIL'.ljust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)} #{'-'.rjust(15)}"
            end
          end

          # Performance comparison
          successful = results.select { |r| r[:status] == :success }
          if successful.length >= 2
            puts
            puts "Performance Ratios:"
            base = successful.first
            successful[1..].each do |r|
              ratio = r[:cycles_per_sec] / base[:cycles_per_sec]
              puts "  #{r[:name]} vs #{base[:name]}: #{format('%.1f', ratio)}x"
            end
          end
        end

        private

        def print_benchmark_summary(results, cycles)
          puts
          puts_header("Summary")
          puts "#{'Runner'.ljust(15)} #{'Status'.ljust(10)} #{'Init'.rjust(10)} #{'Run'.rjust(10)} #{'Rate'.rjust(15)}"
          puts_separator

          results.each do |r|
            if r[:status] == :success
              rate_str = "#{format('%.2f', r[:cycles_per_sec] / 1_000_000)}M/s"
              puts "#{r[:name].ljust(15)} #{'OK'.ljust(10)} #{format('%8.3f', r[:init_time])}s #{format('%8.3f', r[:run_time])}s #{rate_str.rjust(15)}"
            elsif r[:status] == :skipped
              puts "#{r[:name].ljust(15)} #{'SKIP'.ljust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)} #{'-'.rjust(15)}"
            else
              puts "#{r[:name].ljust(15)} #{'FAIL'.ljust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)} #{'-'.rjust(15)}"
            end
          end

          # Performance comparison
          successful = results.select { |r| r[:status] == :success }
          if successful.length >= 2
            puts
            puts "Performance Ratios:"
            base = successful.first
            successful[1..].each do |r|
              ratio = r[:cycles_per_sec] / base[:cycles_per_sec]
              puts "  #{r[:name]} vs #{base[:name]}: #{format('%.1f', ratio)}x"
            end
          end
        end

        def rspec_cmd
          binstub = File.join(Config.project_root, 'bin/rspec')
          File.executable?(binstub) ? binstub : 'rspec'
        end

        def verilator_available?
          ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
            File.executable?(File.join(path, 'verilator'))
          end
        end
      end
    end
  end
end
