# frozen_string_literal: true

module RHDL
  module Import
    module Checks
      class Comparator
        class << self
          def compare(expected:, actual:)
            new.compare(expected: expected, actual: actual)
          end
        end

        def compare(expected:, actual:)
          expected_cycles = normalize_cycles(expected)
          actual_cycles = normalize_cycles(actual)
          cycles = sorted_cycles(expected_cycles.keys | actual_cycles.keys)

          mismatches = []
          signals_compared = 0
          pass_count = 0

          cycles.each do |cycle|
            expected_signals = expected_cycles.fetch(cycle, {})
            actual_signals = actual_cycles.fetch(cycle, {})
            signals = (expected_signals.keys | actual_signals.keys).sort

            signals.each do |signal|
              signals_compared += 1
              expected_value = expected_signals[signal]
              actual_value = actual_signals[signal]

              if expected_value == actual_value
                pass_count += 1
              else
                mismatches << {
                  cycle: cycle,
                  signal: signal,
                  expected: expected_value,
                  actual: actual_value
                }
              end
            end
          end

          fail_count = mismatches.length

          {
            passed: fail_count.zero?,
            summary: {
              cycles_compared: cycles.length,
              signals_compared: signals_compared,
              pass_count: pass_count,
              fail_count: fail_count
            },
            mismatches: mismatches
          }
        end

        private

        def normalize_cycles(values)
          case values
          when Array
            values.each_with_index.each_with_object({}) do |(signals, cycle), memo|
              memo[cycle] = normalize_signals(signals)
            end
          when Hash
            values.each_with_object({}) do |(cycle, signals), memo|
              memo[normalize_cycle(cycle)] = normalize_signals(signals)
            end
          else
            {}
          end
        end

        def normalize_signals(signals)
          return {} unless signals.is_a?(Hash)

          signals.each_with_object({}) do |(signal, value), memo|
            memo[signal.to_s] = value
          end
        end

        def normalize_cycle(cycle)
          return cycle if cycle.is_a?(Numeric)

          text = cycle.to_s.strip
          return text.to_i if text.match?(/\A\d+\z/)

          text
        end

        def sorted_cycles(cycles)
          cycles.sort_by do |cycle|
            if cycle.is_a?(Numeric)
              [0, cycle]
            else
              [1, cycle.to_s]
            end
          end
        end
      end
    end
  end
end
