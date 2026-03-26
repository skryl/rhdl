# frozen_string_literal: true

require 'set'

module RHDL
  module Sim
    module Native
      module Debug
        class VcdTracer
          SignalChange = Struct.new(:time, :signal_idx, :value, keyword_init: true)

          module TraceMode
            BUFFER = :buffer
            STREAMING = :streaming
          end

          attr_reader :signal_names, :signal_widths

          def initialize(signal_names:, signal_widths:, timescale: '1ns', module_name: 'top')
            @signal_names = Array(signal_names).map(&:to_s)
            @signal_widths = Array(signal_widths).map { |width| normalize_width(width) }
            @signal_widths = Array.new(@signal_names.length, 32) if @signal_widths.empty?
            @signal_widths.fill(32, @signal_widths.length...@signal_names.length)

            @time = 0
            @enabled = false
            @mode = TraceMode::BUFFER
            @traced_signals = Set.new
            @prev_values = Array.new(@signal_names.length, 0)
            @vcd_ids = Array.new(@signal_names.length) { |idx| self.class.idx_to_vcd_id(idx) }
            @changes = []
            @file_writer = nil
            @live_chunk = +''
            @header_written = false
            @timescale = timescale.to_s
            @module_name = module_name.to_s
          end

          def set_mode(mode)
            @mode = mode
          end

          def set_timescale(timescale)
            @timescale = timescale.to_s
          end

          def set_module_name(name)
            @module_name = name.to_s
          end

          def add_signal(idx)
            return false unless idx && idx >= 0 && idx < @signal_names.length

            @traced_signals.add(idx)
            true
          end

          def add_signal_by_name(name)
            idx = @signal_names.index(name.to_s)
            return false unless idx

            add_signal(idx)
          end

          def add_signals_matching(pattern)
            needle = pattern.to_s
            count = 0
            @signal_names.each_with_index do |name, idx|
              next unless name.include?(needle)
              next if @traced_signals.include?(idx)

              @traced_signals.add(idx)
              count += 1
            end
            count
          end

          def clear_signals
            @traced_signals.clear
          end

          def trace_all_signals
            @traced_signals = Set.new(0...@signal_names.length)
          end

          def start
            @enabled = true
            @time = 0
            @header_written = false
            @live_chunk.clear
            trace_all_signals if @traced_signals.empty?
          end

          def stop
            @enabled = false
            flush_file
          end

          def open_file(path)
            close_file
            @file_writer = File.open(path, 'wb')
            @mode = TraceMode::STREAMING
            true
          rescue StandardError => e
            raise RuntimeError, "Failed to create VCD file: #{e.message}"
          end

          def close_file
            flush_file
            @file_writer&.close
            @file_writer = nil
          end

          def enabled?
            @enabled
          end

          def capture(values)
            return unless @enabled

            write_header unless @header_written

            changes = []
            Array(values).each_with_index do |raw_value, idx|
              next unless should_trace?(idx)

              value = mask_value(raw_value.to_i, @signal_widths[idx])
              next if value == @prev_values[idx]

              @prev_values[idx] = value
              changes << SignalChange.new(time: @time, signal_idx: idx, value: value)
            end

            unless changes.empty?
              @changes.concat(changes) if @mode == TraceMode::BUFFER
              write_changes(changes)
            end

            @time += 1
          end

          def advance_time(cycles)
            @time += cycles.to_i
          end

          def set_time(time)
            @time = time.to_i
          end

          def time
            @time
          end

          def change_count
            @changes.length
          end

          def signal_count
            @traced_signals.length
          end

          def take_live_chunk
            chunk = @live_chunk.dup
            @live_chunk.clear
            chunk
          end

          def to_vcd
            vcd = +''
            vcd << header_text(initial_values: Array.new(@signal_names.length, 0))

            last_time = nil
            @changes.each do |change|
              if last_time != change.time
                vcd << "##{change.time}\n"
                last_time = change.time
              end

              width = @signal_widths[change.signal_idx]
              vcd_id = @vcd_ids[change.signal_idx]
              vcd << self.class.format_value(change.value, width, vcd_id)
              vcd << "\n"
            end

            vcd
          end

          def save_vcd(path)
            File.binwrite(path, to_vcd)
            true
          rescue StandardError => e
            raise RuntimeError, "Failed to write VCD file: #{e.message}"
          end

          def clear
            @changes.clear
            @time = 0
            @header_written = false
            @live_chunk.clear
          end

          def tracked_signal_indices
            @traced_signals.to_a.sort
          end

          def self.idx_to_vcd_id(idx)
            base = 94
            offset = 33
            return (offset + idx).chr if idx < base

            result = +''
            n = idx
            loop do
              result.prepend((offset + (n % base)).chr)
              n /= base
              break if n.zero?

              n -= 1
            end
            result
          end

          def self.format_value(value, width, vcd_id)
            width = width.to_i
            return "#{value.to_i & 1}#{vcd_id}" if width <= 1

            masked = if width >= 128
                       value.to_i
                     else
                       value.to_i & ((1 << width) - 1)
                     end
            bits = masked.to_s(2)
            bits = bits[-width, width] if bits.length > width
            bits = bits.rjust(width, '0')
            "b#{bits} #{vcd_id}"
          end

          private

          def normalize_width(width)
            value = width.to_i
            value.positive? ? value : 1
          end

          def mask_value(value, width)
            width = normalize_width(width)
            return value if width >= 128

            value & ((1 << width) - 1)
          end

          def should_trace?(idx)
            @traced_signals.empty? || @traced_signals.include?(idx)
          end

          def write_header
            header = header_text(initial_values: @prev_values)
            @file_writer&.write(header)
            @live_chunk << header
            @header_written = true
            flush_file
          end

          def header_text(initial_values:)
            header = +"$timescale #{@timescale} $end\n"
            header << "$scope module #{@module_name} $end\n"

            @signal_names.each_with_index do |name, idx|
              next unless should_trace?(idx)

              width = @signal_widths[idx]
              safe_name = name.gsub('.', '_').gsub('[', '_').delete(']')
              header << "$var wire #{width} #{@vcd_ids[idx]} #{safe_name} $end\n"
            end

            header << "$upscope $end\n"
            header << "$enddefinitions $end\n"
            header << "$dumpvars\n"
            Array(initial_values).each_with_index do |value, idx|
              next unless should_trace?(idx)

              header << self.class.format_value(mask_value(value.to_i, @signal_widths[idx]), @signal_widths[idx], @vcd_ids[idx])
              header << "\n"
            end
            header << "$end\n"
            header
          end

          def write_changes(changes)
            output = +''
            last_time = nil
            changes.each do |change|
              if last_time != change.time
                output << "##{change.time}\n"
                last_time = change.time
              end

              width = @signal_widths[change.signal_idx]
              output << self.class.format_value(change.value, width, @vcd_ids[change.signal_idx])
              output << "\n"
            end

            @file_writer&.write(output)
            @live_chunk << output
            flush_file
          end

          def flush_file
            @file_writer&.flush
          end
        end
      end
    end
  end
end
