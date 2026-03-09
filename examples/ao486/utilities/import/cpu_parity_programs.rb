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

          class Program
            attr_reader :name, :description, :source, :max_cycles, :min_fetch_groups

            def initialize(name:, description:, source:, max_cycles:, min_fetch_groups:, expected_memory: {}, expected_fetch_pc_trace: nil)
              @name = name.to_sym
              @description = description
              @source = source
              @max_cycles = max_cycles
              @min_fetch_groups = min_fetch_groups
              @expected_memory = expected_memory
              @expected_fetch_pc_trace = Array(expected_fetch_pc_trace).map { |pc, bytes| [pc, Array(bytes).dup.freeze] }.freeze
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

            def load_into(runtime)
              runtime.clear_memory! if runtime.respond_to?(:clear_memory!)
              runtime.load_bytes(RESET_VECTOR_PHYSICAL, bytes)
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
              description: 'Compact self-checking prime scan with a success HLT inside the current fetch window.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                mov bx, 2
                xor di, di
                mov cx, 2

              outer_loop:
                cmp cx, bx
                jae found_prime
                mov ax, bx
                xor dx, dx
                div cx
                cmp dx, 0
                je next_candidate
                inc cx
                jmp outer_loop

              found_prime:
                add di, bx

              next_candidate:
                inc bx
                cmp bx, 32
                jb outer_loop

                cmp di, #{expected_prime_sum}
                jne bad_loop
                hlt

              bad_loop:
                jmp bad_loop
              ASM
              max_cycles: 256,
              min_fetch_groups: 16,
              expected_fetch_pc_trace: prime_sieve_expected_fetch_pc_trace
            )
          end

          def mandelbrot_program
            Program.new(
              name: :mandelbrot,
              description: 'Compact fixed-point Mandelbrot orbit check with a success HLT inside the current fetch window.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                xor ax, ax
                xor dx, dx
                mov bx, 4

              orbit_loop:
                mov cx, ax
                imul cx, dx
                shl cx, 1
                add cx, 1
                mov si, ax
                imul si, ax
                mov di, dx
                imul di, dx
                sub si, di
                mov ax, si
                mov dx, cx
                dec bx
                jnz orbit_loop

                cmp ax, 0xFFF0
                je success

              bad_loop:
                jmp bad_loop

              success:
                hlt
              ASM
              max_cycles: 256,
              min_fetch_groups: 16,
              expected_fetch_pc_trace: mandelbrot_expected_fetch_pc_trace
            )
          end

          def game_of_life_program
            Program.new(
              name: :game_of_life,
              description: 'Compact self-checking Game of Life center-cell update with a success HLT inside the current fetch window.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                mov ax, 0x001A
                xor cx, cx
                test ax, 0x0002
                jz skip_a
                inc cx
              skip_a:
                test ax, 0x0008
                jz skip_b
                inc cx
              skip_b:
                test ax, 0x0010
                jz skip_c
                inc cx
              skip_c:
                cmp cx, 2
                je success

              bad_loop:
                jmp bad_loop

              success:
                hlt
              ASM
              max_cycles: 256,
              min_fetch_groups: 16,
              expected_fetch_pc_trace: game_of_life_expected_fetch_pc_trace
            )
          end

          def prime_sieve_expected_fetch_pc_trace
            [
              [0xFFF0, [0xBB, 0x02, 0x00, 0x31]],
              [0xFFF4, [0xFF, 0xB9, 0x02, 0x00]],
              [0xFFF8, [0x39, 0xD9, 0x73, 0x0E]],
              [0xFFFC, [0x89, 0xD8, 0x31, 0xD2]],
              [0x10000, [0xF7, 0xF1, 0x83, 0xFA]],
              [0x10004, [0x00, 0x74, 0x05, 0x41]],
              [0x10008, [0xEB, 0xEE, 0x01, 0xDF]],
              [0x1000C, [0x43, 0x83, 0xFB, 0x20]],
              [0x10000, [0xF7, 0xF1, 0x83, 0xFA]],
              [0x10004, [0x00, 0x74, 0x05, 0x41]],
              [0x10008, [0xEB, 0xEE, 0x01, 0xDF]],
              [0x1000C, [0x43, 0x83, 0xFB, 0x20]],
              [0x10010, [0x72, 0xE6, 0x81, 0xFF]],
              [0x10014, [0xA0, 0x00, 0x75, 0x01]],
              [0x10018, [0xF4, 0xEB, 0xFE, 0x00]],
              [0x1001C, [0x00, 0x00, 0x00, 0x00]]
            ]
          end

          def mandelbrot_expected_fetch_pc_trace
            [
              [0xFFF0, [0x31, 0xC0, 0x31, 0xD2]],
              [0xFFF4, [0xBB, 0x04, 0x00, 0x89]],
              [0xFFF8, [0xC1, 0x0F, 0xAF, 0xCA]],
              [0xFFFC, [0xD1, 0xE1, 0x83, 0xC1]],
              [0x10000, [0x01, 0x89, 0xC6, 0x0F]],
              [0x10004, [0xAF, 0xF0, 0x89, 0xD7]],
              [0x10008, [0x0F, 0xAF, 0xFA, 0x29]],
              [0x1000C, [0xFE, 0x89, 0xF0, 0x89]]
            ]
          end

          def game_of_life_expected_fetch_pc_trace
            [
              [0xFFF0, [0xB8, 0x1A, 0x00, 0x31]],
              [0xFFF4, [0xC9, 0xA9, 0x02, 0x00]],
              [0xFFF8, [0x74, 0x01, 0x41, 0xA9]],
              [0xFFFC, [0x08, 0x00, 0x74, 0x01]],
              [0x10000, [0x41, 0xA9, 0x10, 0x00]],
              [0x10004, [0x74, 0x01, 0x41, 0x83]],
              [0x10008, [0xF9, 0x02, 0x74, 0x02]],
              [0x1000C, [0xEB, 0xFE, 0xF4, 0x00]]
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
