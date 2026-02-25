# frozen_string_literal: true

require_relative '../runners/ruby_runner'

module RHDL
  module Examples
    module AO486
      module Tasks
        # Task for running ao486 simulation from CLI or rake.
        class RunTask
          attr_reader :runner, :options

          def initialize(options = {})
            @options = options
            @debug = !!options[:debug]
            @headless = !!options[:headless]
            @max_steps = options[:max_steps] || 1_000_000
            @runner = RubyRunner.new
            @io_output = []
          end

          def software_path(relative)
            File.expand_path("../../software/#{relative}", __dir__)
          end

          def load_com(path)
            bytes = File.binread(path).bytes
            @runner.load_com(bytes)
          end

          def load_binary(path, addr: 0x0100)
            bytes = File.binread(path).bytes
            @runner.load_at(addr, bytes)
          end

          def run
            @runner.on_io_write do |port, value, _size|
              if port == 0xE9 # bochs/qemu debug port
                $stdout.write(value.chr)
                $stdout.flush
              end
              @io_output << { port: port, value: value }
            end

            if @debug
              $stderr.puts "ao486 Runner: starting execution (max #{@max_steps} steps)"
            end

            result = @runner.run(max_steps: @max_steps)

            if @debug
              $stderr.puts "\nao486 Runner: #{result} after #{@runner.clock_count} cycles"
              state = @runner.state
              $stderr.puts format(
                "  EIP=%08X EAX=%08X EBX=%08X ECX=%08X EDX=%08X",
                state[:eip], state[:eax], state[:ebx], state[:ecx], state[:edx]
              )
              $stderr.puts format(
                "  ESP=%08X EBP=%08X ESI=%08X EDI=%08X",
                state[:esp], state[:ebp], state[:esi], state[:edi]
              )
            end

            result
          end
        end
      end
    end
  end
end
