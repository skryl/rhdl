# frozen_string_literal: true

require_relative 'constants'

module RHDL
  module Examples
    module SPARC64
      module Integration
        module Programs
          Program = Struct.new(
            :name,
            :description,
            :program_source,
            :expected_value,
            :max_cycles,
            :min_transactions,
            keyword_init: true
          )

          class << self
            def all
              @all ||= [
                prime_sieve,
                mandelbrot,
                game_of_life
              ].freeze
            end

            def fetch(name)
              all.find { |program| program.name == name.to_sym } ||
                raise(KeyError, "Unknown SPARC64 integration program: #{name}")
            end

            private

            def prime_sieve
              Program.new(
                name: :prime_sieve,
                description: 'Compact memory-backed prime sieve with checksum mailbox.',
                expected_value: 0xA0,
                max_cycles: 2_000_000,
                min_transactions: 32,
                program_source: <<~ASM
                  .section .text
                  .global _start
                _start:
                  sethi %hi(sieve), %g1
                  or %g1, %lo(sieve), %g1
                  mov 0, %g2
                  mov 1, %g3
                init_loop:
                  cmp %g2, 32
                  bge init_done
                  nop
                  stb %g3, [%g1 + %g2]
                  add %g2, 1, %g2
                  ba,a init_loop
                  nop
                init_done:
                  stb %g0, [%g1]
                  stb %g0, [%g1 + 1]
                  mov 2, %g2
                outer_loop:
                  cmp %g2, 32
                  bge sum_init
                  nop
                  ldub [%g1 + %g2], %g4
                  cmp %g4, 0
                  be next_candidate
                  nop
                  add %g2, %g2, %g5
                mark_loop:
                  cmp %g5, 32
                  bge next_candidate
                  nop
                  stb %g0, [%g1 + %g5]
                  add %g5, %g2, %g5
                  ba,a mark_loop
                  nop
                next_candidate:
                  add %g2, 1, %g2
                  ba,a outer_loop
                  nop
                sum_init:
                  mov 0, %g6
                  mov 0, %g2
                sum_loop:
                  cmp %g2, 32
                  bge verify_result
                  nop
                  ldub [%g1 + %g2], %g4
                  cmp %g4, 0
                  be skip_sum
                  nop
                  add %g6, %g2, %g6
                skip_sum:
                  add %g2, 1, %g2
                  ba,a sum_loop
                  nop
                verify_result:
                  cmp %g6, 0xA0
                  be success
                  nop
                  mov 0xA1, %g3
                  ba,a failure
                  nop

                success:
                  sethi %hi(MAILBOX_STATUS), %g4
                  or %g4, %lo(MAILBOX_STATUS), %g4
                  mov 1, %g5
                  stx %g5, [%g4]
                  sethi %hi(MAILBOX_VALUE), %g4
                  or %g4, %lo(MAILBOX_VALUE), %g4
                  mov 0xA0, %g5
                  stx %g5, [%g4]
                success_spin:
                  ba,a success_spin
                  nop

                failure:
                  sethi %hi(MAILBOX_STATUS), %g4
                  or %g4, %lo(MAILBOX_STATUS), %g4
                  mov -1, %g5
                  stx %g5, [%g4]
                  sethi %hi(MAILBOX_VALUE), %g4
                  or %g4, %lo(MAILBOX_VALUE), %g4
                  stx %g3, [%g4]
                failure_spin:
                  ba,a failure_spin
                  nop

                  .section .bss
                  .align 8
                sieve:
                  .skip 32
                ASM
              )
            end

            def mandelbrot
              Program.new(
                name: :mandelbrot,
                description: 'Compact fixed-point style orbit loop with memory-backed state.',
                expected_value: 0xFFF0,
                max_cycles: 3_000_000,
                min_transactions: 24,
                program_source: <<~ASM
                  .section .text
                  .global _start
                _start:
                  sethi %hi(accumulator), %g1
                  or %g1, %lo(accumulator), %g1
                  sethi %hi(orbit_x), %g2
                  or %g2, %lo(orbit_x), %g2
                  sethi %hi(orbit_y), %g3
                  or %g3, %lo(orbit_y), %g3
                  mov 4, %g4
                orbit_loop:
                  cmp %g4, 0
                  be orbit_done
                  nop
                  ldx [%g2], %g5
                  ldx [%g3], %g6
                  add %g5, 1, %g5
                  sub %g6, 1, %g6
                  stx %g5, [%g2]
                  stx %g6, [%g3]
                  ldx [%g1], %g7
                  sub %g7, 4, %g7
                  stx %g7, [%g1]
                  sub %g4, 1, %g4
                  ba,a orbit_loop
                  nop
                orbit_done:
                  ldx [%g1], %g5
                  sethi %hi(0xFFF0), %g6
                  or %g6, %lo(0xFFF0), %g6
                  cmp %g5, %g6
                  be success
                  nop
                  mov 0xB0, %g3
                  ba,a failure
                  nop

                success:
                  sethi %hi(MAILBOX_STATUS), %g4
                  or %g4, %lo(MAILBOX_STATUS), %g4
                  mov 1, %g5
                  stx %g5, [%g4]
                  sethi %hi(MAILBOX_VALUE), %g4
                  or %g4, %lo(MAILBOX_VALUE), %g4
                  sethi %hi(0xFFF0), %g5
                  or %g5, %lo(0xFFF0), %g5
                  stx %g5, [%g4]
                success_spin:
                  ba,a success_spin
                  nop

                failure:
                  sethi %hi(MAILBOX_STATUS), %g4
                  or %g4, %lo(MAILBOX_STATUS), %g4
                  mov -1, %g5
                  stx %g5, [%g4]
                  sethi %hi(MAILBOX_VALUE), %g4
                  or %g4, %lo(MAILBOX_VALUE), %g4
                  stx %g3, [%g4]
                failure_spin:
                  ba,a failure_spin
                  nop

                  .section .data
                  .align 8
                accumulator:
                  .xword 0x10000
                orbit_x:
                  .xword 0
                orbit_y:
                  .xword 0
                ASM
              )
            end

            def game_of_life
              Program.new(
                name: :game_of_life,
                description: 'Compact memory-backed center-cell neighbor count check.',
                expected_value: 0x2,
                max_cycles: 2_000_000,
                min_transactions: 16,
                program_source: <<~ASM
                  .section .text
                  .global _start
                _start:
                  sethi %hi(board), %g1
                  or %g1, %lo(board), %g1
                  sethi %hi(next_board), %g2
                  or %g2, %lo(next_board), %g2
                  mov 0, %g6
                  ldub [%g1 + 0], %g3
                  add %g6, %g3, %g6
                  ldub [%g1 + 1], %g3
                  add %g6, %g3, %g6
                  ldub [%g1 + 2], %g3
                  add %g6, %g3, %g6
                  ldub [%g1 + 3], %g3
                  add %g6, %g3, %g6
                  ldub [%g1 + 5], %g3
                  add %g6, %g3, %g6
                  ldub [%g1 + 6], %g3
                  add %g6, %g3, %g6
                  ldub [%g1 + 7], %g3
                  add %g6, %g3, %g6
                  ldub [%g1 + 8], %g3
                  add %g6, %g3, %g6
                  stb %g6, [%g2 + 4]
                  cmp %g6, 2
                  be success
                  nop
                  mov 0xC0, %g3
                  ba,a failure
                  nop

                success:
                  sethi %hi(MAILBOX_STATUS), %g4
                  or %g4, %lo(MAILBOX_STATUS), %g4
                  mov 1, %g5
                  stx %g5, [%g4]
                  sethi %hi(MAILBOX_VALUE), %g4
                  or %g4, %lo(MAILBOX_VALUE), %g4
                  mov 2, %g5
                  stx %g5, [%g4]
                success_spin:
                  ba,a success_spin
                  nop

                failure:
                  sethi %hi(MAILBOX_STATUS), %g4
                  or %g4, %lo(MAILBOX_STATUS), %g4
                  mov -1, %g5
                  stx %g5, [%g4]
                  sethi %hi(MAILBOX_VALUE), %g4
                  or %g4, %lo(MAILBOX_VALUE), %g4
                  stx %g3, [%g4]
                failure_spin:
                  ba,a failure_spin
                  nop

                  .section .data
                  .align 8
                board:
                  .byte 0, 1, 0, 1, 1, 0, 0, 0, 0
                next_board:
                  .skip 9
                ASM
              )
            end
          end
        end
      end
    end
  end
end
