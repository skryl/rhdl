# frozen_string_literal: true

module RHDL
  module Sim
    module Native
      module HeadlessTrace
        TRACE_METHODS = %i[
          trace_start
          trace_start_streaming
          trace_stop
          trace_enabled?
          trace_capture
          trace_add_signal
          trace_add_signals_matching
          trace_all_signals
          trace_clear_signals
          trace_to_vcd
          trace_take_live_vcd
          trace_save_vcd
          trace_clear
          trace_change_count
          trace_signal_count
          trace_set_timescale
          trace_set_module_name
        ].freeze

        def trace_supported?
          delegate = trace_delegate
          return false unless delegate

          return delegate.trace_supported? if delegate.respond_to?(:trace_supported?)

          TRACE_METHODS.all? { |name| delegate.respond_to?(name) }
        end

        TRACE_METHODS.each do |method_name|
          define_method(method_name) do |*args, &block|
            delegate = trace_delegate
            unless delegate
              raise RuntimeError, "#{self.class} does not support tracing for the active backend"
            end

            if method_name == :trace_enabled? && delegate.respond_to?(:trace_supported?) && !delegate.trace_supported?
              return false
            end

            unless delegate.respond_to?(method_name)
              raise RuntimeError, "#{self.class} does not support tracing for the active backend"
            end

            delegate.public_send(method_name, *args, &block)
          end
        end

        private

        def trace_delegate
          candidates = []
          candidates << @runner if instance_variable_defined?(:@runner)
          candidates << @cpu if instance_variable_defined?(:@cpu)
          candidates.compact.each do |candidate|
            return candidate if candidate.respond_to?(:trace_supported?) || TRACE_METHODS.any? { |name| candidate.respond_to?(name) }

            next unless candidate.respond_to?(:sim)

            sim = candidate.sim
            next unless sim

            return sim if sim.respond_to?(:trace_supported?) || TRACE_METHODS.any? { |name| sim.respond_to?(name) }
          end
          nil
        end
      end
    end
  end
end
