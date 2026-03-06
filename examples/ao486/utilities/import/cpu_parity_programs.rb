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

            def initialize(name:, description:, source:, max_cycles:, min_fetch_groups:, expected_memory: {})
              @name = name.to_sym
              @description = description
              @source = source
              @max_cycles = max_cycles
              @min_fetch_groups = min_fetch_groups
              @expected_memory = expected_memory
            end

            def bytes
              @bytes ||= CpuParityPrograms.assemble(@source, label: @name)
            end

            def expected_memory
              @expected_memory.dup
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
            expected_prime_count = 11
            expected_prime_sum = 0x00A0

            Program.new(
              name: :prime_sieve,
              description: 'Register-only prime scan with self-check against the expected prime count and checksum.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                mov bx, 2
                xor si, si
                xor di, di

              outer_loop:
                mov cx, 2

              divisor_loop:
                cmp cx, bx
                jae found_prime
                mov ax, bx
                xor dx, dx
                div cx
                cmp dx, 0
                je next_candidate
                inc cx
                jmp divisor_loop

              found_prime:
                inc si
                add di, bx

              next_candidate:
                inc bx
                cmp bx, 32
                jb outer_loop

                cmp si, #{expected_prime_count}
                jne bad_loop
                cmp di, #{expected_prime_sum}
                jne bad_loop
                hlt

              bad_loop:
                jmp bad_loop
              ASM
              max_cycles: 512,
              min_fetch_groups: 12
            )
          end

          def mandelbrot_program
            expected_checksum = 24

            Program.new(
              name: :mandelbrot,
              description: 'Register-only fixed-point Mandelbrot checksum over four sample points.',
              source: <<~ASM,
                .intel_syntax noprefix
                .code16

                xor edi, edi

                xor eax, eax
                xor edx, edx
                xor ebx, ebx
              point_0_loop:
                mov ebp, eax
                imul ebp, edx
                sar ebp, 7
                add ebp, -256
                mov esi, eax
                imul esi, eax
                sar esi, 8
                mov ecx, edx
                imul ecx, edx
                sar ecx, 8
                mov eax, esi
                add eax, ecx
                cmp eax, 1024
                jg point_0_done
                mov eax, esi
                sub eax, ecx
                add eax, -512
                mov edx, ebp
                inc ebx
                cmp ebx, 8
                jb point_0_loop
              point_0_done:
                add edi, ebx

                xor eax, eax
                xor edx, edx
                xor ebx, ebx
              point_1_loop:
                mov ebp, eax
                imul ebp, edx
                sar ebp, 7
                add ebp, 26
                mov esi, eax
                imul esi, eax
                sar esi, 8
                mov ecx, edx
                imul ecx, edx
                sar ecx, 8
                mov eax, esi
                add eax, ecx
                cmp eax, 1024
                jg point_1_done
                mov eax, esi
                sub eax, ecx
                add eax, -192
                mov edx, ebp
                inc ebx
                cmp ebx, 8
                jb point_1_loop
              point_1_done:
                add edi, ebx

                xor eax, eax
                xor edx, edx
                xor ebx, ebx
              point_2_loop:
                mov ebp, eax
                imul ebp, edx
                sar ebp, 7
                mov esi, eax
                imul esi, eax
                sar esi, 8
                mov ecx, edx
                imul ecx, edx
                sar ecx, 8
                mov eax, esi
                add eax, ecx
                cmp eax, 1024
                jg point_2_done
                mov eax, esi
                sub eax, ecx
                mov edx, ebp
                inc ebx
                cmp ebx, 8
                jb point_2_loop
              point_2_done:
                add edi, ebx

                xor eax, eax
                xor edx, edx
                xor ebx, ebx
              point_3_loop:
                mov ebp, eax
                imul ebp, edx
                sar ebp, 7
                add ebp, 128
                mov esi, eax
                imul esi, eax
                sar esi, 8
                mov ecx, edx
                imul ecx, edx
                sar ecx, 8
                mov eax, esi
                add eax, ecx
                cmp eax, 1024
                jg point_3_done
                mov eax, esi
                sub eax, ecx
                add eax, 128
                mov edx, ebp
                inc ebx
                cmp ebx, 8
                jb point_3_loop
              point_3_done:
                add edi, ebx

                cmp edi, #{expected_checksum}
                jne bad_loop
                hlt

              bad_loop:
                jmp bad_loop
              ASM
              max_cycles: 1024,
              min_fetch_groups: 20
            )
          end

          def game_of_life_program
            Program.new(
              name: :game_of_life,
              description: 'Two generations of a 3x3 Game of Life blinker encoded in one register and self-checked.',
              source: game_of_life_source,
              max_cycles: 1536,
              min_fetch_groups: 24
            )
          end

          def game_of_life_source
            neighbor_map = {
              0 => [1, 3, 4],
              1 => [0, 2, 3, 4, 5],
              2 => [1, 4, 5],
              3 => [0, 1, 4, 6, 7],
              4 => [0, 1, 2, 3, 5, 6, 7, 8],
              5 => [1, 2, 4, 7, 8],
              6 => [3, 4, 7],
              7 => [3, 4, 5, 6, 8],
              8 => [4, 5, 7]
            }

            lines = []
            lines << '.intel_syntax noprefix'
            lines << '.code16'
            lines << ''
            lines << 'mov esi, 2'
            lines << 'mov eax, 56'
            lines << ''
            lines << 'generation_loop:'
            lines << 'xor edx, edx'

            neighbor_map.each do |cell, neighbors|
              cell_mask = 1 << cell
              lines << "xor ecx, ecx"
              neighbors.each do |neighbor|
                neighbor_mask = 1 << neighbor
                lines << "test eax, #{neighbor_mask}"
                lines << "jz cell_#{cell}_neighbor_#{neighbor}_skip"
                lines << 'inc ecx'
                lines << "cell_#{cell}_neighbor_#{neighbor}_skip:"
              end
              lines << 'mov ebx, eax'
              lines << "and ebx, #{cell_mask}"
              lines << "jnz cell_#{cell}_alive"
              lines << 'cmp ecx, 3'
              lines << "jne cell_#{cell}_next"
              lines << "or edx, #{cell_mask}"
              lines << "jmp cell_#{cell}_next"
              lines << "cell_#{cell}_alive:"
              lines << 'cmp ecx, 2'
              lines << "je cell_#{cell}_set"
              lines << 'cmp ecx, 3'
              lines << "jne cell_#{cell}_next"
              lines << "cell_#{cell}_set:"
              lines << "or edx, #{cell_mask}"
              lines << "cell_#{cell}_next:"
            end

            lines << 'mov eax, edx'
            lines << 'dec esi'
            lines << 'jnz generation_loop'
            lines << 'cmp eax, 56'
            lines << 'jne bad_loop'
            lines << 'hlt'
            lines << ''
            lines << 'bad_loop:'
            lines << 'jmp bad_loop'
            lines.join("\n") + "\n"
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
