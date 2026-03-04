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
          when :cpu8bit
            benchmark_cpu8bit
          when :gameboy
            benchmark_gameboy
          when :riscv
            benchmark_riscv
          when :web_apple2
            benchmark_web_apple2
          when :web_riscv
            benchmark_web_riscv
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

          sim = RHDL::Sim.gate_level([not_gate, dff], backend: :interpreter, lanes: lanes, name: 'bench_toggle')

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

        # Benchmark 8-bit CPU FastHarness native backends.
        def benchmark_cpu8bit
          require 'rhdl/codegen'
          require_relative '../../../../examples/8bit/hdl/cpu/harness'

          cycles = options[:cycles] || 5_000_000
          batch_size = options[:batch_size] || 4096
          runner_filter = (ENV['RHDL_BENCH_BACKENDS'] || '')
            .split(',')
            .map { |name| name.strip.downcase.to_sym }
            .map { |name| name == :gpu ? :arcilator_gpu : name }
            .reject(&:empty?)

          puts_header("8-bit CPU FastHarness Benchmark")
          puts "Cycles per run: #{cycles}"
          puts "Batch size: #{batch_size}"
          puts

          # JMP_LONG 0x0000 (infinite loop)
          loop_program = [0xF9, 0x00, 0x00].freeze

          runners = [
            {
              name: 'Compiler',
              sim: :compile,
              filter_key: :compiler,
              available: RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
            },
            {
              name: 'ArcilatorGPU',
              sim: :arcilator_gpu,
              filter_key: :arcilator_gpu,
              available: RHDL::HDL::CPU::FastHarness.arcilator_gpu_status[:ready]
            }
          ]
          runners.select! { |runner| runner_filter.include?(runner[:filter_key]) } unless runner_filter.empty?

          results = []

          runners.each do |runner|
            unless runner[:available]
              puts "\n#{runner[:name]}: SKIPPED (not available)"
              results << { name: runner[:name], status: :skipped }
              next
            end

            print "\n#{runner[:name]}: "
            $stdout.flush

            begin
              print 'initializing... '
              $stdout.flush
              init_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              sim = RHDL::HDL::CPU::FastHarness.new(nil, sim: runner[:sim])
              sim.memory.load(loop_program, 0)
              sim.pc = 0
              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              print "running #{cycles} cycles... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              cycles_run = sim.run_cycles(cycles, batch_size: batch_size)
              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              cycles_per_sec = cycles_run / run_elapsed
              final_pc = sim.pc

              puts 'done'
              puts "  Init time:  #{format('%.3f', init_elapsed)}s"
              puts "  Run time:   #{format('%.3f', run_elapsed)}s"
              puts "  Cycles run: #{cycles_run}"
              puts "  Final PC:   0x#{final_pc.to_s(16).upcase}"

              results << {
                name: runner[:name],
                status: :success,
                init_time: init_elapsed,
                run_time: run_elapsed,
                cycles_per_sec: cycles_per_sec,
                final_pc: final_pc
              }
            rescue => e
              puts 'FAILED'
              puts "  Error: #{e.message}"
              puts "  #{e.backtrace.first(3).join("\n  ")}" if options[:verbose]
              results << { name: runner[:name], status: :failed, error: e.message }
            end
          end

          print_benchmark_summary(results, cycles)
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
          runner_filter = (ENV['RHDL_BENCH_BACKENDS'] || '')
            .split(',')
            .map { |name| name.strip.downcase.to_sym }
            .reject(&:empty?)

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
          ir = RHDL::Examples::MOS6502::CPU.to_flat_circt_nodes
          ir_json_by_backend = {
            interpreter: RHDL::Sim::Native::IR.sim_json(ir, backend: :interpreter),
            jit: RHDL::Sim::Native::IR.sim_json(ir, backend: :jit),
            compiler: RHDL::Sim::Native::IR.sim_json(ir, backend: :compiler)
          }
          ir_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ir_start
          puts "done (#{format('%.3f', ir_elapsed)}s)"

          # Load ROM and memory data
          rom_data = File.binread(rom_path).bytes
          karateka_mem = File.binread(karateka_path).bytes

          # Define runners to benchmark
          runners = [
            { name: 'Interpreter', backend: :interpreter, available_const: :INTERPRETER_AVAILABLE },
            { name: 'JIT', backend: :jit, available_const: :JIT_AVAILABLE },
            { name: 'Compiler', backend: :compiler, available_const: :COMPILER_AVAILABLE },
            { name: 'Verilator', backend: :verilator }
          ]

          results = []

          runners.each do |runner|
            if runner_filter.any? && !runner_filter.include?(runner[:backend])
              results << { name: runner[:name], status: :skipped }
              next
            end

            # Skip Interpreter for large cycle counts (too slow)
            if runner[:backend] == :interpreter && cycles > 100_000
              puts "\n#{runner[:name]}: SKIPPED (cycles > 100K, too slow)"
              results << { name: runner[:name], status: :skipped }
              next
            end

            # Check availability
            if runner[:available_const]
              available = RHDL::Sim::Native::IR.const_get(runner[:available_const]) rescue false
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
                sim = RHDL::Examples::MOS6502::VerilogRunner.new
              else
                bus = RHDL::Examples::MOS6502::Apple2Bus.new("bench_bus")

                sim = case runner[:backend]
                when :interpreter
                  RHDL::Sim::Native::IR::Simulator.new(ir_json_by_backend[:interpreter], backend: :interpreter)
                when :jit
                  RHDL::Sim::Native::IR::Simulator.new(ir_json_by_backend[:jit], backend: :jit)
                when :compiler
                  RHDL::Sim::Native::IR::Simulator.new(ir_json_by_backend[:compiler], backend: :compiler)
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
                use_rust_memory = sim.respond_to?(:runner_kind) && sim.runner_kind == :mos6502

                # Always load into Ruby bus (needed for reset sequence)
                bus.load_rom(rom_data, base_addr: 0xD000)
                bus.load_ram(karateka_mem, base_addr: 0x0000)
                memory = bus.instance_variable_get(:@memory)
                memory[0xFFFC] = 0x2A  # low byte of $B82A
                memory[0xFFFD] = 0xB8  # high byte of $B82A

                if use_rust_memory
                  # Also load into Rust memory for batched execution
                  sim.runner_load_memory(rom_data, 0xD000, true)   # ROM
                  sim.runner_load_memory(karateka_mem, 0x0000, false)  # RAM
                  sim.runner_set_reset_vector(0xB82A)
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
                sim.runner_run_cycles(cycles)
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

        # Benchmark Apple2 full system IR (legacy bench:native[ir])
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
          compiler_sub_cycles = 14
          runner_filter = (ENV['RHDL_BENCH_BACKENDS'] || '')
            .split(',')
            .map { |name| name.strip.downcase.to_sym }
            .reject(&:empty?)

          puts_header("Apple2 Full System IR Benchmark - Karateka Game Code")
          puts "Cycles per run: #{cycles}"
          puts "Compiler sub-cycles: #{compiler_sub_cycles} (fixed)"
          puts "ROM: #{rom_path}"
          puts "Memory dump: #{karateka_path}"
          puts

          # Generate IR once for all runners
          print "Generating Apple2 IR... "
          $stdout.flush

          require_relative '../../../../examples/apple2/hdl'
          ir_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ir = RHDL::Examples::Apple2::Apple2.to_flat_circt_nodes
          ir_json_by_backend = {
            interpreter: RHDL::Sim::Native::IR.sim_json(ir, backend: :interpreter),
            jit: RHDL::Sim::Native::IR.sim_json(ir, backend: :jit),
            compiler: RHDL::Sim::Native::IR.sim_json(ir, backend: :compiler)
          }
          ir_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ir_start
          puts "done (#{format('%.3f', ir_elapsed)}s)"

          # Define runners to benchmark
          runners = [
            { name: 'Interpreter', backend: :interpreter, available_const: :INTERPRETER_AVAILABLE },
            { name: 'JIT', backend: :jit, available_const: :JIT_AVAILABLE },
            { name: 'Compiler', backend: :compiler, available_const: :COMPILER_AVAILABLE },
            { name: 'Verilator', backend: :verilator },
            { name: 'Arcilator', backend: :arcilator }
          ]
          runners.select! { |runner| runner_filter.include?(runner[:backend]) } unless runner_filter.empty?

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
              available = RHDL::Sim::Native::IR.const_get(runner[:available_const]) rescue false
            elsif runner[:backend] == :verilator
              available = verilator_available?
            elsif runner[:backend] == :arcilator
              available = arcilator_available?
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

            is_hdl_runner = runner[:backend] == :verilator || runner[:backend] == :arcilator

            begin
              # Create simulator
              print "initializing... "
              $stdout.flush
              init_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              sim = case runner[:backend]
              when :interpreter
                RHDL::Sim::Native::IR::Simulator.new(ir_json_by_backend[:interpreter], backend: :interpreter)
              when :jit
                RHDL::Sim::Native::IR::Simulator.new(ir_json_by_backend[:jit], backend: :jit)
              when :compiler
                RHDL::Sim::Native::IR::Simulator.new(ir_json_by_backend[:compiler], backend: :compiler, sub_cycles: compiler_sub_cycles)
              when :verilator
                require_relative '../../../../examples/apple2/utilities/runners/verilator_runner'
                RHDL::Examples::Apple2::VerilogRunner.new(sub_cycles: 14)
              when :arcilator
                require_relative '../../../../examples/apple2/utilities/runners/arcilator_runner'
                RHDL::Examples::Apple2::ArcilatorRunner.new(sub_cycles: 14)
              end

              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              # Load ROM and RAM
              print "loading... "
              $stdout.flush
              if is_hdl_runner
                sim.load_rom(karateka_rom, base_addr: 0xD000)
                sim.load_ram(karateka_mem.first(48 * 1024), base_addr: 0)
              else
                sim.runner_load_rom(karateka_rom)
                sim.runner_load_memory(karateka_mem.first(48 * 1024), 0, false)
              end

              # Reset
              if is_hdl_runner
                sim.reset
              else
                sim.poke('reset', 1)
                sim.tick
                sim.poke('reset', 0)
              end

              # Warmup - run a few cycles to get past reset
              if is_hdl_runner
                sim.run_steps(3)
              else
                sim.runner_run_cycles(3, 0, false)
              end

              # Benchmark
              print "running #{cycles} cycles... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              if is_hdl_runner
                sim.run_steps(cycles)
              else
                sim.runner_run_cycles(cycles, 0, false)
              end
              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              cycles_per_sec = cycles / run_elapsed
              pc = is_hdl_runner ? sim.pc : sim.peek('cpu__pc_reg')

              puts "done"
              puts "  Init time: #{format('%.3f', init_elapsed)}s"
              puts "  Run time:  #{format('%.3f', run_elapsed)}s"
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
                unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
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
                runner = RHDL::Examples::GameBoy::VerilogRunner.new
              else
                runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
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

        # Benchmark RISC-V single-cycle CPU running xv6 boot across IR/Verilator/Arcilator
        def benchmark_riscv
          kernel_path = File.expand_path('../../../../examples/riscv/software/bin/xv6_kernel.bin', __dir__)
          fs_path = File.expand_path('../../../../examples/riscv/software/bin/xv6_fs.img', __dir__)

          unless File.exist?(kernel_path)
            puts "Error: xv6 kernel not found at #{kernel_path}"
            return
          end

          unless File.exist?(fs_path)
            puts "Error: xv6_fs.img not found at #{fs_path}"
            return
          end

          cycles = options[:cycles] || 100_000
          runner_filter = (ENV['RHDL_BENCH_BACKENDS'] || '')
            .split(',')
            .map { |name| name.strip.downcase.to_sym }
            .reject(&:empty?)

          puts_header("RISC-V Single-Cycle CPU Benchmark - xv6 Boot")
          puts "Cycles per run: #{cycles}"
          puts "Kernel: #{kernel_path}"
          puts "Filesystem: #{fs_path}"
          puts

          require_relative '../../../../examples/riscv/utilities/runners/headless_runner'

          runners = [
            { name: 'IR Compiler', mode: :ir, sim: :compile, filter_key: :compiler },
            { name: 'Verilator', mode: :verilog, sim: nil, filter_key: :verilator },
            { name: 'CIRCT', mode: :circt, sim: nil, filter_key: :circt }
          ]
          runners.select! { |r| runner_filter.include?(r[:filter_key]) } unless runner_filter.empty?

          results = []

          runners.each do |runner_config|
            # Check availability
            available = case runner_config[:mode]
                        when :ir
                          begin
                            require 'rhdl/codegen'
                            RHDL::Sim::Native::IR::COMPILER_AVAILABLE
                          rescue LoadError, NameError
                            false
                          end
                        when :verilog
                          verilator_available?
                        when :circt
                          arcilator_available?
                        end

            unless available
              puts "\n#{runner_config[:name]}: SKIPPED (not available)"
              results << { name: runner_config[:name], status: :skipped }
              next
            end

            print "\n#{runner_config[:name]}: "
            $stdout.flush

            begin
              # Create HeadlessRunner
              print "initializing... "
              $stdout.flush
              init_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              runner_opts = { mode: runner_config[:mode], core: :single }
              runner_opts[:sim] = runner_config[:sim] if runner_config[:sim]
              runner = RHDL::Examples::RISCV::HeadlessRunner.new(**runner_opts)

              init_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - init_start

              # Load xv6
              print "loading xv6... "
              $stdout.flush
              runner.load_xv6(kernel: kernel_path, fs: fs_path)

              # Warmup - run 100 cycles past reset
              runner.run_steps(100)

              # Benchmark
              print "running #{cycles} cycles... "
              $stdout.flush
              run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              runner.run_steps(cycles)
              run_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start

              cycles_per_sec = cycles / run_elapsed
              state = runner.cpu_state
              pc = state[:pc]

              puts "done"
              puts "  Init time: #{format('%.3f', init_elapsed)}s"
              puts "  Run time:  #{format('%.3f', run_elapsed)}s"
              puts "  Final PC:  0x#{pc.to_s(16).upcase}"

              results << {
                name: runner_config[:name],
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
              results << { name: runner_config[:name], status: :failed, error: e.message }
            end
          end

          print_benchmark_summary(results, cycles)
        end

        # Benchmark Apple II web WASM backends (Rust AOT compiler + Arcilator + Verilator) via Node.js
        def benchmark_web_apple2
          rom_path = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __dir__)
          karateka_path = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __dir__)
          bench_script = File.expand_path('../../../../web/bench/apple2_wasm_bench.mjs', __dir__)

          unless File.exist?(rom_path) && File.exist?(karateka_path)
            puts "Error: ROM or Karateka memory dump not found"
            puts "  ROM: #{rom_path}"
            puts "  RAM: #{karateka_path}"
            return
          end

          unless command_available?('node')
            puts "Error: Node.js not found in PATH (required for WASM benchmarks)"
            return
          end

          cycles = options[:cycles] || 100_000
          runner_filter = (ENV['RHDL_BENCH_BACKENDS'] || '')
            .split(',')
            .map { |name| name.strip.downcase.to_sym }
            .reject(&:empty?)

          puts_header("Apple II Web WASM Benchmark - Karateka Game Code")
          puts "Cycles per run: #{cycles}"
          puts "ROM: #{rom_path}"
          puts "Memory dump: #{karateka_path}"
          puts

          # Build WASM artifacts
          wasm_backends = prepare_web_wasm_backends(runner_filter)

          if wasm_backends.empty?
            puts "No WASM backends available. Ensure CIRCT tools or Rust wasm32 target are installed."
            return
          end

          results = []

          wasm_backends.each do |backend|
            print "\n#{backend[:name]}: "
            $stdout.flush

            begin
              print "running #{cycles} cycles... "
              $stdout.flush

              cmd = ['node', bench_script, backend[:wasm_path], rom_path, karateka_path, cycles.to_s]
              cmd << backend[:ir_json_path] if backend[:ir_json_path]

              output = `#{cmd.shelljoin} 2>&1`
              unless $?.success?
                puts "FAILED"
                puts "  Error: #{output.lines.first(3).join('  ')}"
                results << { name: backend[:name], status: :failed, error: output.lines.first&.strip }
                next
              end

              data = JSON.parse(output.lines.last)

              puts "done"
              puts "  WASM size: #{format('%.1f', data['wasm_size'] / 1024.0)} KB"
              puts "  Init time: #{format('%.3f', data['init_ms'] / 1000.0)}s"
              puts "  Run time:  #{format('%.3f', data['run_ms'] / 1000.0)}s"
              puts "  Final PC:  0x#{data['final_pc'].to_s(16).upcase}"
              puts "  Signals:   #{data['signal_count']}"

              results << {
                name: backend[:name],
                status: :success,
                init_time: data['init_ms'] / 1000.0,
                run_time: data['run_ms'] / 1000.0,
                cycles_per_sec: data['cycles_per_sec'],
                final_pc: data['final_pc'],
                wasm_size: data['wasm_size']
              }
            rescue => e
              puts "FAILED"
              puts "  Error: #{e.message}"
              results << { name: backend[:name], status: :failed, error: e.message }
            end
          end

          print_benchmark_summary(results, cycles)
        end

        # Benchmark RISC-V web WASM backends (Rust AOT compiler + Arcilator + Verilator) via Node.js
        def benchmark_web_riscv
          kernel_path = File.expand_path('../../../../examples/riscv/software/bin/xv6_kernel.bin', __dir__)
          fs_path = File.expand_path('../../../../examples/riscv/software/bin/xv6_fs.img', __dir__)
          bench_script = File.expand_path('../../../../web/bench/riscv_wasm_bench.mjs', __dir__)

          unless File.exist?(kernel_path) && File.exist?(fs_path)
            puts "Error: xv6 kernel or xv6_fs.img not found"
            puts "  Kernel: #{kernel_path}"
            puts "  Filesystem: #{fs_path}"
            return
          end

          unless command_available?('node')
            puts "Error: Node.js not found in PATH (required for WASM benchmarks)"
            return
          end

          cycles = options[:cycles] || 100_000
          runner_filter = (ENV['RHDL_BENCH_BACKENDS'] || '')
            .split(',')
            .map { |name| name.strip.downcase.to_sym }
            .reject(&:empty?)

          puts_header("RISC-V Web WASM Benchmark - xv6")
          puts "Cycles per run: #{cycles}"
          puts "Kernel: #{kernel_path}"
          puts "Filesystem: #{fs_path}"
          puts

          wasm_backends = prepare_web_riscv_wasm_backends(runner_filter)
          if wasm_backends.empty?
            puts "No WASM backends available. Ensure CIRCT tools or Rust wasm32 target are installed."
            return
          end

          results = []

          wasm_backends.each do |backend|
            print "\n#{backend[:name]}: "
            $stdout.flush

            begin
              print "running #{cycles} cycles... "
              $stdout.flush

              cmd = ['node', bench_script, backend[:wasm_path], kernel_path, fs_path, cycles.to_s]
              cmd << backend[:ir_json_path] if backend[:ir_json_path]

              output = `#{cmd.shelljoin} 2>&1`
              unless $?.success?
                puts "FAILED"
                puts "  Error: #{output.lines.first(3).join('  ')}"
                results << { name: backend[:name], status: :failed, error: output.lines.first&.strip }
                next
              end

              data = JSON.parse(output.lines.last)

              puts "done"
              puts "  WASM size: #{format('%.1f', data['wasm_size'] / 1024.0)} KB"
              puts "  Init time: #{format('%.3f', data['init_ms'] / 1000.0)}s"
              puts "  Run time:  #{format('%.3f', data['run_ms'] / 1000.0)}s"
              puts "  Final PC:  0x#{data['final_pc'].to_s(16).upcase}"
              puts "  Signals:   #{data['signal_count'] || '-'}"

              results << {
                name: backend[:name],
                status: :success,
                init_time: data['init_ms'] / 1000.0,
                run_time: data['run_ms'] / 1000.0,
                cycles_per_sec: data['cycles_per_sec'],
                final_pc: data['final_pc'],
                wasm_size: data['wasm_size']
              }
            rescue => e
              puts "FAILED"
              puts "  Error: #{e.message}"
              results << { name: backend[:name], status: :failed, error: e.message }
            end
          end

          print_benchmark_summary(results, cycles)
        end

        private

        def print_benchmark_summary(results, cycles)
          puts
          puts_header("Summary")
          puts "#{'Runner'.ljust(15)} #{'Status'.ljust(10)} #{'Init'.rjust(10)} #{'Run'.rjust(10)}"
          puts_separator

          results.each do |r|
            if r[:status] == :success
              puts "#{r[:name].ljust(15)} #{'OK'.ljust(10)} #{format('%8.3f', r[:init_time])}s #{format('%8.3f', r[:run_time])}s"
            elsif r[:status] == :skipped
              puts "#{r[:name].ljust(15)} #{'SKIP'.ljust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)}"
            else
              puts "#{r[:name].ljust(15)} #{'FAIL'.ljust(10)} #{'-'.rjust(10)} #{'-'.rjust(10)}"
            end
          end

          # Performance comparison (ratio-centric; do not report absolute speed)
          successful = results.select { |r| r[:status] == :success }
          compiler = successful.find { |r| r[:name] == 'Compiler' }
          if successful.length >= 2
            puts
            puts "Performance Ratios:"
            base = compiler || successful.first
            successful.each do |r|
              next if r[:name] == base[:name]

              ratio = r[:cycles_per_sec] / base[:cycles_per_sec]
              puts "  #{r[:name]} vs #{base[:name]}: #{format('%.3f', ratio)}x"
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

        def arcilator_available?
          %w[firtool arcilator llc].all? do |cmd|
            ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
              File.executable?(File.join(path, cmd))
            end
          end
        end

        def command_available?(cmd)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
            File.executable?(File.join(dir, cmd))
          end
        end

        # Build/locate WASM backends for the web Apple II benchmark.
        # Returns an array of { name:, wasm_path:, ir_json_path: } hashes.
        def prepare_web_wasm_backends(runner_filter)
          require 'shellwords'

          project_root = File.expand_path('../../../..', __dir__)
          pkg_dir = File.join(project_root, 'web', 'assets', 'pkg')

          backends = []

          # 1) Rust AOT Compiler WASM
          if runner_filter.empty? || runner_filter.include?(:compiler)
            compiler_wasm = File.join(pkg_dir, 'ir_compiler.wasm')
            ir_json = File.join(project_root, 'web', 'assets', 'fixtures', 'apple2', 'ir', 'apple2.json')

            unless File.exist?(compiler_wasm) && File.exist?(ir_json)
              print "Building Rust AOT compiler WASM... "
              $stdout.flush
              begin
                build_compiler_wasm_for_bench(project_root, pkg_dir, ir_json)
                puts "done"
              rescue => e
                puts "FAILED (#{e.message})"
              end
            end

            if File.exist?(compiler_wasm) && File.exist?(ir_json)
              backends << { name: 'Compiler', wasm_path: compiler_wasm, ir_json_path: ir_json }
            else
              puts "Compiler WASM: SKIPPED (not available)"
            end
          end

          # 2) Arcilator WASM
          if runner_filter.empty? || runner_filter.include?(:arcilator)
            arc_wasm = File.join(pkg_dir, 'apple2_arcilator.wasm')

            unless File.exist?(arc_wasm)
              print "Building arcilator WASM... "
              $stdout.flush
              begin
                require_relative 'utilities/web_apple2_arcilator_build'
                WebApple2ArcilatorBuild.build(dest_dir: pkg_dir)
                puts "done"
              rescue => e
                puts "FAILED (#{e.message})"
              end
            end

            if File.exist?(arc_wasm)
              backends << { name: 'Arcilator', wasm_path: arc_wasm, ir_json_path: nil }
            else
              puts "Arcilator WASM: SKIPPED (not available)"
            end
          end

          # 3) Verilator WASM
          if runner_filter.empty? || runner_filter.include?(:verilator)
            ver_wasm = File.join(pkg_dir, 'apple2_verilator.wasm')

            unless File.exist?(ver_wasm)
              print "Building verilator WASM... "
              $stdout.flush
              begin
                require_relative 'utilities/web_apple2_verilator_build'
                WebApple2VerilatorBuild.build(dest_dir: pkg_dir)
                puts "done"
              rescue => e
                puts "FAILED (#{e.message})"
              end
            end

            if File.exist?(ver_wasm)
              backends << { name: 'Verilator', wasm_path: ver_wasm, ir_json_path: nil }
            else
              puts "Verilator WASM: SKIPPED (not available)"
            end
          end

          backends
        end

        # Build/locate WASM backends for the web RISC-V benchmark.
        # Returns an array of { name:, wasm_path:, ir_json_path: } hashes.
        def prepare_web_riscv_wasm_backends(runner_filter)
          require 'shellwords'

          project_root = File.expand_path('../../../..', __dir__)
          pkg_dir = File.join(project_root, 'web', 'assets', 'pkg')
          backends = []

          # 1) Rust AOT Compiler WASM (RISC-V IR)
          if runner_filter.empty? || runner_filter.include?(:compiler)
            compiler_wasm = File.join(pkg_dir, 'ir_compiler_riscv.wasm')
            ir_json = File.join(project_root, 'web', 'assets', 'fixtures', 'riscv', 'ir', 'riscv.json')

            unless File.exist?(compiler_wasm) && File.exist?(ir_json)
              print "Building Rust AOT compiler WASM... "
              $stdout.flush
              begin
                build_riscv_compiler_wasm_for_bench(project_root, pkg_dir, ir_json)
                puts "done"
              rescue => e
                puts "FAILED (#{e.message})"
              end
            end

            if File.exist?(compiler_wasm) && File.exist?(ir_json)
              backends << { name: 'Compiler', wasm_path: compiler_wasm, ir_json_path: ir_json }
            else
              puts "Compiler WASM: SKIPPED (not available)"
            end
          end

          # 2) Arcilator WASM (RISC-V)
          if runner_filter.empty? || runner_filter.include?(:arcilator)
            arc_wasm = File.join(pkg_dir, 'riscv_arcilator.wasm')

            unless File.exist?(arc_wasm)
              print "Building arcilator WASM... "
              $stdout.flush
              begin
                require_relative 'utilities/web_riscv_arcilator_build'
                WebRiscvArcilatorBuild.build(dest_dir: pkg_dir)
                puts "done"
              rescue => e
                puts "FAILED (#{e.message})"
              end
            end

            if File.exist?(arc_wasm)
              backends << { name: 'Arcilator', wasm_path: arc_wasm, ir_json_path: nil }
            else
              puts "Arcilator WASM: SKIPPED (not available)"
            end
          end

          # 3) Verilator WASM (RISC-V)
          if runner_filter.empty? || runner_filter.include?(:verilator)
            ver_wasm = File.join(pkg_dir, 'riscv_verilator.wasm')

            unless File.exist?(ver_wasm)
              print "Building verilator WASM... "
              $stdout.flush
              begin
                require_relative 'utilities/web_riscv_verilator_build'
                WebRiscvVerilatorBuild.build(dest_dir: pkg_dir)
                puts "done"
              rescue => e
                puts "FAILED (#{e.message})"
              end
            end

            if File.exist?(ver_wasm)
              backends << { name: 'Verilator', wasm_path: ver_wasm, ir_json_path: nil }
            else
              puts "Verilator WASM: SKIPPED (not available)"
            end
          end

          backends
        end

        # Build the Rust AOT compiler WASM and generate the Apple II IR JSON.
        def build_compiler_wasm_for_bench(project_root, pkg_dir, ir_json_path)
          # Generate Apple II IR JSON if missing
          unless File.exist?(ir_json_path)
            require 'rhdl'
            require 'rhdl/codegen'

            require File.join(project_root, 'examples/apple2/hdl')
            ir = RHDL::Examples::Apple2::Apple2.to_flat_circt_nodes
            ir_data = RHDL::Sim::Native::IR.sim_json(ir, backend: :compiler)

            FileUtils.mkdir_p(File.dirname(ir_json_path))
            File.write(ir_json_path, ir_data)
          end

          # AOT codegen + cargo build
          sim_dir = File.join(project_root, 'lib/rhdl/sim/native/ir')
          compiler_dir = File.join(sim_dir, 'ir_compiler')
          aot_gen_path = File.join(compiler_dir, 'src/aot_generated.rs')

          unless system('cargo', 'run', '--quiet', '--bin', 'aot_codegen', '--',
                        ir_json_path, aot_gen_path, chdir: compiler_dir)
            raise 'AOT code generation failed'
          end

          unless system('cargo', 'build', '--release', '--target', 'wasm32-unknown-unknown',
                        '--features', 'aot', chdir: compiler_dir)
            raise 'Compiler WASM build failed'
          end

          src_wasm = File.join(compiler_dir, 'target', 'wasm32-unknown-unknown', 'release', 'ir_compiler.wasm')
          raise "Compiler WASM not found at #{src_wasm}" unless File.exist?(src_wasm)

          FileUtils.mkdir_p(pkg_dir)
          FileUtils.cp(src_wasm, File.join(pkg_dir, 'ir_compiler.wasm'))
        end

        # Build the Rust AOT compiler WASM and generate the RISC-V IR JSON.
        def build_riscv_compiler_wasm_for_bench(project_root, pkg_dir, ir_json_path)
          unless File.exist?(ir_json_path)
            require 'rhdl'
            require 'rhdl/codegen'
            require File.join(project_root, 'examples/riscv/hdl/cpu')

            ir = RHDL::Examples::RISCV::CPU.to_flat_circt_nodes(top_name: 'riscv_cpu')
            ir_data = RHDL::Sim::Native::IR.sim_json(ir, backend: :compiler)

            FileUtils.mkdir_p(File.dirname(ir_json_path))
            File.write(ir_json_path, ir_data)
          end

          sim_dir = File.join(project_root, 'lib/rhdl/sim/native/ir')
          compiler_dir = File.join(sim_dir, 'ir_compiler')
          aot_gen_path = File.join(compiler_dir, 'src/aot_generated.rs')

          unless system('cargo', 'run', '--quiet', '--bin', 'aot_codegen', '--',
                        ir_json_path, aot_gen_path, chdir: compiler_dir)
            raise 'AOT code generation failed'
          end

          unless system('cargo', 'build', '--release', '--target', 'wasm32-unknown-unknown',
                        '--features', 'aot', chdir: compiler_dir)
            raise 'Compiler WASM build failed'
          end

          src_wasm = File.join(compiler_dir, 'target', 'wasm32-unknown-unknown', 'release', 'ir_compiler.wasm')
          raise "Compiler WASM not found at #{src_wasm}" unless File.exist?(src_wasm)

          FileUtils.mkdir_p(pkg_dir)
          FileUtils.cp(src_wasm, File.join(pkg_dir, 'ir_compiler_riscv.wasm'))
        end
      end
    end
  end
end
