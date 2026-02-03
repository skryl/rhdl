# frozen_string_literal: true

module RHDL
  module GameBoy
    module Tasks
      # Factory for creating Game Boy simulation runners
      # Handles mode/backend selection and fallback logic
      class RunnerFactory
        VALID_MODES = [:hdl, :verilog].freeze
        VALID_BACKENDS = [:ruby, :interpret, :jit, :compile].freeze
        DEFAULT_MODE = :hdl
        DEFAULT_BACKEND = :compile

        attr_reader :mode, :backend, :runner, :fallback_used

        def initialize(mode: DEFAULT_MODE, backend: DEFAULT_BACKEND)
          @mode = mode || DEFAULT_MODE
          @backend = backend || DEFAULT_BACKEND
          @fallback_used = false
          @runner = nil

          validate_mode!
          validate_backend!
        end

        # Create and return the appropriate runner
        def create
          @runner = case @mode
                    when :hdl
                      create_hdl_runner
                    when :verilog
                      create_verilator_runner
                    end
          @runner
        end

        # Returns info about the created runner
        def runner_info
          return nil unless @runner

          {
            mode: @mode,
            backend: @backend,
            fallback_used: @fallback_used,
            simulator_type: @runner.simulator_type,
            native: @runner.native?
          }
        end

        private

        def validate_mode!
          return if VALID_MODES.include?(@mode)

          raise ArgumentError, "Unknown mode: #{@mode}. Use one of: #{VALID_MODES.join(', ')}"
        end

        def validate_backend!
          return if VALID_BACKENDS.include?(@backend)

          raise ArgumentError, "Unknown backend: #{@backend}. Use one of: #{VALID_BACKENDS.join(', ')}"
        end

        def create_hdl_runner
          if @backend == :ruby
            create_ruby_runner
          else
            create_ir_runner
          end
        end

        def create_ruby_runner
          require 'gameboy_hdl'
          RHDL::GameBoy::HdlRunner.new
        end

        def create_ir_runner
          require 'gameboy_ir'
          RHDL::GameBoy::IrRunner.new(backend: @backend)
        rescue LoadError, NoMethodError => e
          @fallback_used = true
          @backend = :ruby
          warn "Warning: Native backend not available: #{e.message}"
          warn "Falling back to Ruby simulation..."
          create_ruby_runner
        end

        def create_verilator_runner
          require 'gameboy_verilator'
          RHDL::GameBoy::VerilatorRunner.new
        rescue LoadError => e
          raise ArgumentError, "Verilator mode requires Verilator to be installed: #{e.message}"
        end
      end
    end
  end
end
