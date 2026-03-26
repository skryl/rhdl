# frozen_string_literal: true

require 'rhdl/sim/native/debug/vcd_tracer'

module RHDL
  module Sim
    module Native
      module Debug
        module TraceSupport
          def self.attach(simulator, module_name: nil)
            simulator.extend(self)
            simulator.send(:initialize_soft_trace!, module_name: module_name)
            simulator
          end

          def trace_supported?
            return super if native_trace_capable?

            soft_trace_available?
          end

          def trace_streaming_supported?
            return super if native_trace_capable?

            soft_trace_available?
          end

          def trace_start
            return super if native_trace_capable?

            tracer = ensure_soft_trace!
            tracer.close_file
            tracer.set_mode(VcdTracer::TraceMode::BUFFER)
            tracer.clear
            tracer.start
            true
          end

          def trace_start_streaming(path)
            return super if native_trace_capable?

            tracer = ensure_soft_trace!
            tracer.clear
            tracer.open_file(path)
            tracer.start
            true
          end

          def trace_stop
            return super if native_trace_capable?

            return { ok: true, value: 0 } unless @soft_trace

            @soft_trace.stop
            { ok: true, value: 0 }
          end

          def trace_enabled?
            return super if native_trace_capable?

            !!@soft_trace&.enabled?
          end

          def trace_capture
            return super if native_trace_capable?

            tracer = ensure_soft_trace!
            values = soft_trace_signal_values
            tracer.capture(values)
            { ok: true, value: 0 }
          end

          def trace_add_signal(name)
            return super if native_trace_capable?

            ensure_soft_trace!.add_signal_by_name(name)
          end

          def trace_add_signals_matching(pattern)
            return super if native_trace_capable?

            ensure_soft_trace!.add_signals_matching(pattern)
          end

          def trace_all_signals
            return super if native_trace_capable?

            ensure_soft_trace!.trace_all_signals
            { ok: true, value: 0 }
          end

          def trace_clear_signals
            return super if native_trace_capable?

            ensure_soft_trace!.clear_signals
            { ok: true, value: 0 }
          end

          def trace_to_vcd
            return super if native_trace_capable?

            ensure_soft_trace!.to_vcd
          end

          def trace_take_live_vcd
            return super if native_trace_capable?

            ensure_soft_trace!.take_live_chunk
          end

          def trace_save_vcd(path)
            return super if native_trace_capable?

            ensure_soft_trace!.save_vcd(path)
          end

          def trace_clear
            return super if native_trace_capable?

            ensure_soft_trace!.clear
            { ok: true, value: 0 }
          end

          def trace_change_count
            return super if native_trace_capable?

            @soft_trace ? @soft_trace.change_count : 0
          end

          def trace_signal_count
            return super if native_trace_capable?

            @soft_trace ? @soft_trace.signal_count : 0
          end

          def trace_set_timescale(timescale)
            return super if native_trace_capable?

            ensure_soft_trace!.set_timescale(timescale)
            true
          end

          def trace_set_module_name(name)
            return super if native_trace_capable?

            @soft_trace_module_name = name.to_s
            ensure_soft_trace!.set_module_name(name)
            true
          end

          private

          def initialize_soft_trace!(module_name: nil)
            return if instance_variable_defined?(:@soft_trace_initialized)

            @soft_trace_initialized = true
            @soft_trace_module_name = (module_name || default_soft_trace_module_name).to_s
            return unless soft_trace_available?

            @sim_caps_flags = @sim_caps_flags.to_i |
                              RHDL::Sim::Native::ABI::SIM_CAP_TRACE |
                              RHDL::Sim::Native::ABI::SIM_CAP_TRACE_STREAMING
          end

          def native_trace_capable?
            @native_trace_capable ||= begin
              flags = instance_variable_defined?(:@sim_caps_flags) ? @sim_caps_flags.to_i : 0
              (flags & RHDL::Sim::Native::ABI::SIM_CAP_TRACE) != 0 && !soft_trace_promoted?
            end
          end

          def soft_trace_promoted?
            @soft_trace_promoted == true
          end

          def soft_trace_available?
            return @soft_trace_available unless @soft_trace_available.nil?

            names = safe_trace_signal_names
            @soft_trace_available = !names.empty?
            @soft_trace_promoted = @soft_trace_available
            @soft_trace_available
          end

          def ensure_soft_trace!
            raise RuntimeError, "#{@backend_label || 'native HDL'} simulator does not support tracing" unless soft_trace_available?

            @soft_trace ||= begin
              names = safe_trace_signal_names
              widths = safe_trace_signal_widths(names)
              VcdTracer.new(
                signal_names: names,
                signal_widths: widths,
                module_name: @soft_trace_module_name
              )
            end
          end

          def safe_trace_signal_names
            @soft_trace_signal_names ||= begin
              names = input_names + output_names
              names.map!(&:to_s)
              names
            rescue StandardError
              []
            end
          end

          def safe_trace_signal_widths(names)
            widths_by_name =
              if instance_variable_defined?(:@signal_widths_by_name)
                instance_variable_get(:@signal_widths_by_name) || {}
              else
                {}
              end

            widths_by_idx =
              if instance_variable_defined?(:@signal_widths_by_idx)
                Array(instance_variable_get(:@signal_widths_by_idx))
              else
                []
              end

            names.each_with_index.map do |name, idx|
              width = widths_by_name[name.to_s]
              width = widths_by_idx[idx] if width.nil?
              width = infer_soft_trace_width(name) if width.nil?
              width.to_i.positive? ? width.to_i : 32
            end
          end

          def infer_soft_trace_width(_name)
            32
          end

          def soft_trace_signal_values
            names = safe_trace_signal_names
            names.each_index.map do |idx|
              peek_by_idx(idx)
            rescue StandardError
              0
            end
          end

          def default_soft_trace_module_name
            if respond_to?(:runner_kind) && runner_kind
              runner_kind.to_s
            elsif instance_variable_defined?(:@backend_label)
              @backend_label.to_s.downcase.gsub(/[^a-z0-9]+/, '_').sub(/\A_+/, '').sub(/_+\z/, '')
            else
              'top'
            end
          end
        end
      end
    end
  end
end
