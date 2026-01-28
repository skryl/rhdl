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
          when :verilator
            benchmark_verilator
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
          print "Generating MOS6502::CPU IR... "
          $stdout.flush

          require_relative '../../../../examples/mos6502/hdl/cpu'
          require_relative '../../../../examples/mos6502/utilities/apple2_bus'

          ir_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ir = MOS6502::CPU.to_flat_ir
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
            { name: 'Compiler', backend: :compiler, available_const: :IR_COMPILER_AVAILABLE }
          ]

          results = []

          runners.each do |runner|
            available = RHDL::Codegen::IR.const_get(runner[:available_const]) rescue false
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

              bus = MOS6502::Apple2Bus.new("bench_bus")

              sim = case runner[:backend]
              when :interpreter
                RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
              when :jit
                RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
              when :compiler
                RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
              end

              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              # Check if Rust MOS6502 mode is available
              use_rust_memory = sim.respond_to?(:mos6502_mode?) && sim.mos6502_mode?

              # Load ROM and RAM
              print "loading... "
              $stdout.flush

              # Always load into Ruby bus (needed for reset sequence)
              bus.load_rom(rom_data, base_addr: 0xD000)
              bus.load_ram(karateka_mem, base_addr: 0x0000)
              memory = bus.instance_variable_get(:@memory)
              memory[0xFFFC] = 0x2A  # low byte of $B82A
              memory[0xFFFD] = 0xB8  # high byte of $B82A

              if use_rust_memory
                # Also load into Rust memory for batched execution
                sim.load_mos6502_memory(rom_data, 0xD000, true)   # ROM
                sim.load_mos6502_memory(karateka_mem, 0x0000, false)  # RAM
                sim.set_mos6502_reset_vector(0xB82A)
              end

              # Reset CPU
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

              # Benchmark
              print "running #{cycles} cycles... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              if use_rust_memory
                # Use batched Rust execution - no FFI per cycle!
                sim.run_mos6502_cycles(cycles)
              else
                # Ruby memory bridging (fallback)
                cycles.times { clock_tick.call }
              end
              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              cycles_per_sec = cycles / run_elapsed
              pc = sim.peek('reg_pc')

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
            { name: 'Compiler', backend: :compiler, available_const: :IR_COMPILER_AVAILABLE }
          ]

          results = []

          runners.each do |runner|
            available = RHDL::Codegen::IR.const_get(runner[:available_const]) rescue false
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

              sim = case runner[:backend]
              when :interpreter
                RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
              when :jit
                RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
              when :compiler
                RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
              end

              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              # Load ROM and RAM
              print "loading... "
              $stdout.flush
              sim.load_rom(karateka_rom)
              sim.load_ram(karateka_mem.first(48 * 1024), 0)

              # Reset
              sim.poke('reset', 1)
              sim.tick
              sim.poke('reset', 0)

              # Warmup - run a few cycles to get past reset
              3.times { sim.run_cpu_cycles(1, 0, false) }

              # Benchmark
              print "running #{cycles} cycles... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              sim.run_cpu_cycles(cycles, 0, false)
              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              cycles_per_sec = cycles / run_elapsed
              pc = sim.peek('cpu__pc_reg')

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

        # Benchmark Verilator simulation
        def benchmark_verilator
          # Check if Verilator is available
          verilator_path = ENV['PATH'].split(File::PATH_SEPARATOR).find do |path|
            File.executable?(File.join(path, 'verilator'))
          end

          unless verilator_path
            puts "Error: Verilator not found in PATH"
            puts "Install Verilator:"
            puts "  Ubuntu/Debian: sudo apt-get install verilator"
            puts "  macOS: brew install verilator"
            return
          end

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

          cycles = options[:cycles] || 100_000

          puts_header("Verilator Simulation Benchmark - Apple II")

          # Check Verilator version
          version = `verilator --version 2>&1`.lines.first&.strip
          puts "Verilator: #{version}"
          puts "Cycles: #{cycles}"
          puts "ROM: #{rom_path}"
          puts "Memory dump: #{karateka_path}"
          puts

          begin
            # Load RHDL and the Verilator runner
            require 'rhdl'
            $LOAD_PATH.unshift(File.expand_path('../../../../examples/apple2/utilities', __dir__))
            require 'apple2_verilator'

            # Create and initialize runner (includes Verilator build)
            print "Building Verilator simulation... "
            $stdout.flush
            init_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            runner = RHDL::Apple2::VerilatorRunner.new(sub_cycles: 14)
            init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start
            puts "done (#{format('%.2f', init_elapsed)}s)"

            # Load ROM and memory
            print "Loading ROM and memory... "
            $stdout.flush
            rom_data = File.binread(rom_path).bytes
            karateka_mem = File.binread(karateka_path).bytes

            runner.load_rom(rom_data, base_addr: 0xD000)
            runner.load_ram(karateka_mem, base_addr: 0x0000)

            # Set reset vector to game entry ($B82A)
            runner.write_memory(0xFFFC, 0x2A)  # low byte
            runner.write_memory(0xFFFD, 0xB8)  # high byte
            puts "done"

            # Reset
            print "Resetting CPU... "
            $stdout.flush
            runner.reset
            puts "done"

            # Run benchmark
            print "Running #{cycles} cycles... "
            $stdout.flush
            run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            runner.run_steps(cycles)
            run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

            cycles_per_sec = cycles / run_elapsed
            puts "done"

            puts
            puts "Results:"
            puts "  Build time: #{format('%.3f', init_elapsed)}s"
            puts "  Run time:   #{format('%.3f', run_elapsed)}s"
            puts "  Rate:       #{format('%.0f', cycles_per_sec)} cycles/s (#{format('%.2f', cycles_per_sec / 1_000_000)}M/s)"
            puts "  PC:         0x#{runner.pc.to_s(16).upcase}"

          rescue => e
            puts "FAILED"
            puts "  Error: #{e.message}"
            puts "  #{e.backtrace.first(5).join("\n  ")}" if options[:verbose]
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
      end
    end
  end
end
