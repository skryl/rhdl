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

          sim = RHDL::Export.gate_level([not_gate, dff], backend: :cpu, lanes: lanes, name: 'bench_toggle')

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

        private

        def rspec_cmd
          binstub = File.join(Config.project_root, 'bin/rspec')
          File.executable?(binstub) ? binstub : 'rspec'
        end
      end
    end
  end
end
