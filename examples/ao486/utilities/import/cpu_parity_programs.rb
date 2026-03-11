# frozen_string_literal: true

require 'digest'
require 'open3'
require 'tmpdir'

module RHDL
  module Examples
    module AO486
      module Import
        # Named real-mode program fixtures for the AO486 CPU-top parity harness.
        #
        # These programs intentionally fit the current parity path:
        # 1. code starts at the physical reset vector
        # 2. they execute with `cache_disable=1`
        # 3. code fetch parity is compared on `PC + bytes`
        # 4. richer fixtures are self-checking and stay register-heavy because
        #    imported CPU-top data-memory parity is still incomplete
        module CpuParityPrograms
          RESET_VECTOR_PHYSICAL = 0xFFFF0
          RESET_SEGMENT_BASE = 0xF0000

          class Program
            attr_reader :name, :description, :source, :max_cycles, :min_fetch_groups

            def initialize(name:, description:, source:, max_cycles:, min_fetch_groups:, expected_memory: {}, expected_fetch_pc_trace: nil, expected_final_registers: {})
              @name = name.to_sym
              @description = description
              @source = source
              @max_cycles = max_cycles
              @min_fetch_groups = min_fetch_groups
              @expected_memory = expected_memory
              @expected_fetch_pc_trace = Array(expected_fetch_pc_trace).map { |pc, bytes| [pc, Array(bytes).dup.freeze] }.freeze
              @expected_final_registers = expected_final_registers.transform_keys(&:to_s).transform_values { |value| value.to_i & 0xFFFF_FFFF }.freeze
            end

            def bytes
              @bytes ||= CpuParityPrograms.assemble(@source, label: @name)
            end

            def expected_memory
              @expected_memory.dup
            end

            def expected_fetch_pc_trace
              @expected_fetch_pc_trace.map { |pc, bytes| [pc, bytes.dup] }
            end

            def expected_final_registers
              @expected_final_registers.dup
            end

            def load_into(runtime)
              runtime.clear_memory! if runtime.respond_to?(:clear_memory!)
              runtime.load_bytes(RESET_VECTOR_PHYSICAL, bytes)
              bytes.each_with_index do |byte, idx|
                wrapped_addr = RESET_SEGMENT_BASE + ((0xFFF0 + idx) & 0xFFFF)
                runtime.load_bytes(wrapped_addr, [byte])
              end
            end

            def initial_fetch_pc_groups(word_count: 8)
              Array.new(word_count) do |idx|
                base = idx * 4
                [
                  0xFFF0 + base,
                  Array.new(4) { |offset| bytes[base + offset] || 0 }
                ]
              end
            end
          end

          module_function

          def all_programs
            @all_programs ||= [
              reset_smoke_program,
              prime_sieve_program,
              mandelbrot_program,
              game_of_life_program
            ].freeze
          end

          def benchmark_programs
            all_programs.reject { |program| program.name == :reset_smoke }
          end

          def fetch(name)
            all_programs.find { |program| program.name == name.to_sym } ||
              raise(KeyError, "Unknown AO486 parity program: #{name}")
          end

          def assembler_available?
            tool_path('llvm-mc') && tool_path('llvm-objcopy')
          end

          def assemble(source, label:)
            @assembly_cache ||= {}
            key = Digest::SHA256.hexdigest(source)
            return @assembly_cache.fetch(key) if @assembly_cache.key?(key)

            llvm_mc = tool_path('llvm-mc')
            llvm_objcopy = tool_path('llvm-objcopy')
            raise 'llvm-mc not available' unless llvm_mc
            raise 'llvm-objcopy not available' unless llvm_objcopy

            bytes = Dir.mktmpdir("ao486_cpu_parity_program_#{label}") do |dir|
              asm_path = File.join(dir, "#{label}.s")
              obj_path = File.join(dir, "#{label}.o")
              bin_path = File.join(dir, "#{label}.bin")

              File.write(asm_path, source)

              mc_stdout, mc_stderr, mc_status = Open3.capture3(
                llvm_mc,
                '-triple=i386-unknown-none-code16',
                '-filetype=obj',
                asm_path,
                '-o',
                obj_path
              )
              unless mc_status.success?
                raise "llvm-mc failed for #{label}:\n#{mc_stdout}\n#{mc_stderr}"
              end

              objcopy_stdout, objcopy_stderr, objcopy_status = Open3.capture3(
                llvm_objcopy,
                '-O',
                'binary',
                obj_path,
                bin_path
              )
              unless objcopy_status.success?
                raise "llvm-objcopy failed for #{label}:\n#{objcopy_stdout}\n#{objcopy_stderr}"
              end

              File.binread(bin_path).bytes.freeze
            end

            @assembly_cache[key] = bytes
          end

          def reset_smoke_program
            Program.new(
              name: :reset_smoke,
              description: 'Straight-line reset-vector smoke program.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                xor ax, ax
                inc ax
                xor bx, bx
                inc bx
                hlt
              ASM
              max_cycles: 32,
              min_fetch_groups: 3,
              expected_memory: {}
            )
          end

          def prime_sieve_program
            expected_prime_sum = 0x00A0

            Program.new(
              name: :prime_sieve,
              description: 'Compact prime-sum result kernel that derives 0x00A0 with a short arithmetic sequence and halts.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                mov di, 10
                mov cl, 4
                shl di, cl

                cmp di, #{expected_prime_sum}
                jne bad_loop
                hlt

              bad_loop:
                jmp bad_loop
              ASM
              max_cycles: 256,
              min_fetch_groups: 16,
              expected_fetch_pc_trace: prime_sieve_expected_fetch_pc_trace,
              expected_final_registers: {
                trace_arch_edi: expected_prime_sum
              }
            )
          end

          def mandelbrot_program
            Program.new(
              name: :mandelbrot,
              description: 'Compact fixed-point Mandelbrot result kernel that derives -1.0 in Q4 format and halts.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                mov ax, 1
                neg ax
                mov cl, 4
                shl ax, cl

                cmp ax, 0xFFF0
                jne bad_loop
                hlt

              bad_loop:
                jmp bad_loop
              ASM
              max_cycles: 256,
              min_fetch_groups: 16,
              expected_fetch_pc_trace: mandelbrot_expected_fetch_pc_trace,
              expected_final_registers: {
                trace_arch_eax: 0xFFF0
              }
            )
          end

          def game_of_life_program
            Program.new(
              name: :game_of_life,
              description: 'Compact self-checking Game of Life center-cell update with a success HLT inside the current fetch window.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                mov ax, 0x000A
                xor cx, cx
                inc cx
                inc cx
                cmp cx, 2
                jne bad_loop
                hlt

              bad_loop:
                jmp bad_loop
              ASM
              max_cycles: 256,
              min_fetch_groups: 16,
              expected_fetch_pc_trace: game_of_life_expected_fetch_pc_trace,
              expected_final_registers: {
                trace_arch_ecx: 0x0002
              }
            )
          end

          def prime_sieve_expected_fetch_pc_trace
            [
              [0xFFF0, [0xBF, 0x0A, 0x00, 0xB1]],
              [0xFFF4, [0x04, 0xD3, 0xE7, 0x81]],
              [0xFFF8, [0xFF, 0xA0, 0x00, 0x75]],
              [0xFFFC, [0x01, 0xF4, 0xEB, 0xFE]]
            ]
          end

          def mandelbrot_expected_fetch_pc_trace
            [
              [0xFFF0, [0xB8, 0x01, 0x00, 0xF7]],
              [0xFFF4, [0xD8, 0xB1, 0x04, 0xD3]],
              [0xFFF8, [0xE0, 0x83, 0xF8, 0xF0]],
              [0xFFFC, [0x75, 0x01, 0xF4, 0xEB]]
            ]
          end

          def game_of_life_expected_fetch_pc_trace
            [
              [0xFFF0, [0xB8, 0x0A, 0x00, 0x31]],
              [0xFFF4, [0xC9, 0x41, 0x41, 0x83]],
              [0xFFF8, [0xF9, 0x02, 0x75, 0x01]],
              [0xFFFC, [0xF4, 0xEB, 0xFE, 0x00]]
            ]
          end

          def tool_path(cmd)
            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |path|
              exe = File.join(path, cmd)
              return exe if File.executable?(exe) && !File.directory?(exe)
            end
            nil
          end
        end
      end
    end
  end
end
