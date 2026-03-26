# frozen_string_literal: true

module AO486SpecSupport
  module IRBackendHelper
    module_function

    def backend_available?(backend)
      case backend
      when :compiler
        RHDL::Sim::Native::IR::COMPILER_AVAILABLE
      when :jit
        RHDL::Sim::Native::IR::JIT_AVAILABLE
      else
        false
      end
    end

    def requested_ir_backend
      backend = ENV['AO486_IR_BACKEND']&.strip
      return nil if backend.nil? || backend.empty?

      case backend
      when 'compiler'
        :compiler
      when 'jit'
        :jit
      else
        raise ArgumentError, "Unknown AO486_IR_BACKEND=#{backend.inspect}; expected 'compiler' or 'jit'"
      end
    end

    def preferred_ir_backend
      requested = requested_ir_backend
      return requested if backend_available?(requested)
      return nil if requested

      # Prefer JIT for ao486: the compiler backend currently rejects ao486
      # designs that contain a small number of combinational assigns it cannot
      # compile (fast-path blocker).  JIT handles them without issue.
      return :jit if backend_available?(:jit)
      return :compiler if backend_available?(:compiler)

      nil
    end

    def cpu_runtime_ir_backend
      requested = requested_ir_backend
      return requested if backend_available?(requested)
      return nil if requested

      # Same JIT-first preference as preferred_ir_backend (see comment above).
      return :jit if backend_available?(:jit)
      return :compiler if backend_available?(:compiler)

      nil
    end

    def preferred_ir_backends
      backend = preferred_ir_backend
      backend ? [backend] : []
    end
  end
end
