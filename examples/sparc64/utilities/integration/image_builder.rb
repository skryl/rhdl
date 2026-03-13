# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open3'

require_relative 'constants'
require_relative 'toolchain'

module RHDL
  module Examples
    module SPARC64
      module Integration
        class ProgramImageBuilder
          BOOT_PROGRAM_ENTRY = PROGRAM_BASE
          BOOT_SHIM_REVISION = 'uncached_boot_prom_slot_branch_table_va_8000'.freeze
          PROGRAM_ENTRY_PAD_REVISION = 'entry_pad_8_nops'.freeze

          BuildResult = Struct.new(
            :program,
            :build_dir,
            :boot_source_path,
            :boot_object_path,
            :boot_elf_path,
            :boot_bin_path,
            :program_source_path,
            :program_object_path,
            :program_elf_path,
            :program_bin_path,
            keyword_init: true
          ) do
            def boot_bytes
              @boot_bytes ||= File.binread(boot_bin_path)
            end

            def program_bytes
              @program_bytes ||= File.binread(program_bin_path)
            end
          end

          attr_reader :cache_root

          def initialize(cache_root: File.expand_path('../../../../tmp/sparc64_program_images', __dir__))
            @cache_root = File.expand_path(cache_root)
          end

          def build(program)
            FileUtils.mkdir_p(cache_root)
            build_dir = File.join(cache_root, build_key(program))
            boot_source_path = File.join(build_dir, 'boot.s')
            boot_object_path = File.join(build_dir, 'boot.o')
            boot_elf_path = File.join(build_dir, 'boot.elf')
            boot_bin_path = File.join(build_dir, 'boot.bin')
            program_source_path = File.join(build_dir, "#{program.name}.s")
            program_object_path = File.join(build_dir, "#{program.name}.o")
            program_elf_path = File.join(build_dir, "#{program.name}.elf")
            program_bin_path = File.join(build_dir, "#{program.name}.bin")
            boot_linker_path = File.join(build_dir, 'boot.ld')
            program_linker_path = File.join(build_dir, 'program.ld')

            return BuildResult.new(
              program: program,
              build_dir: build_dir,
              boot_source_path: boot_source_path,
              boot_object_path: boot_object_path,
              boot_elf_path: boot_elf_path,
              boot_bin_path: boot_bin_path,
              program_source_path: program_source_path,
              program_object_path: program_object_path,
              program_elf_path: program_elf_path,
              program_bin_path: program_bin_path
            ) if File.file?(boot_bin_path) && File.file?(program_bin_path)

            FileUtils.mkdir_p(build_dir)

            File.write(boot_source_path, boot_source(program))
            File.write(boot_linker_path, boot_linker_script)
            compile_source(boot_source_path, boot_object_path)
            link_object(boot_object_path, boot_linker_path, boot_elf_path)
            objcopy_binary(boot_elf_path, boot_bin_path)

            File.write(program_source_path, program_source(program))
            File.write(program_linker_path, program_linker_script)
            compile_source(program_source_path, program_object_path)
            link_object(program_object_path, program_linker_path, program_elf_path)
            objcopy_binary(program_elf_path, program_bin_path)

            BuildResult.new(
              program: program,
              build_dir: build_dir,
              boot_source_path: boot_source_path,
              boot_object_path: boot_object_path,
              boot_elf_path: boot_elf_path,
              boot_bin_path: boot_bin_path,
              program_source_path: program_source_path,
              program_object_path: program_object_path,
              program_elf_path: program_elf_path,
              program_bin_path: program_bin_path
            )
          end

          private

          def build_key(program)
            Digest::SHA256.hexdigest([
              FLASH_BOOT_BASE,
              PROGRAM_BASE,
              STACK_TOP,
              MAILBOX_STATUS,
              MAILBOX_VALUE,
              BOOT_SHIM_REVISION,
              PROGRAM_ENTRY_PAD_REVISION,
              program.name,
              program.program_source
            ].join("\n"))
          end

          def compile_source(source_path, object_path)
            run!(
              Toolchain.llvm_mc,
              '-triple=sparcv9-unknown-none-elf',
              '-filetype=obj',
              source_path,
              '-o',
              object_path
            )
          end

          def link_object(object_path, linker_path, elf_path)
            run!(
              Toolchain.ld_lld,
              '-m', 'elf64_sparc',
              '--image-base=0',
              '-T', linker_path,
              object_path,
              '-o',
              elf_path
            )
          end

          def objcopy_binary(elf_path, bin_path)
            run!(
              Toolchain.llvm_objcopy,
              '-O', 'binary',
              elf_path,
              bin_path
            )
          end

          def run!(*cmd)
            stdout, stderr, status = Open3.capture3(*cmd)
            return if status.success?

            raise "command failed: #{cmd.join(' ')}\n#{stdout}\n#{stderr}"
          end

          def boot_source(_program)
            branch_words = 4.times.map do |index|
              format('0x%08X', boot_branch_word(index * 4))
            end

            <<~ASM
              .section .text
              .global _start
            _start:
              .word #{branch_words[0]}
              .word #{branch_words[1]}
              .word #{branch_words[2]}
              .word #{branch_words[3]}
              nop
              nop
              nop
              nop
              nop
              nop
              nop
              nop
              nop
              nop
              nop
              nop
            ASM
          end

          def boot_branch_word(slot_offset)
            pc = 0x8000 + slot_offset
            disp = (BOOT_PROGRAM_ENTRY - pc) >> 2
            raise "boot branch target out of range for slot #{slot_offset}" unless disp.between?(0, 0x3F_FFFF)

            0x3080_0000 | disp
          end

          def boot_linker_script
            <<~LD
              program_entry = #{format('0x%X', BOOT_PROGRAM_ENTRY)};
              SECTIONS {
                . = 0x8000;
                .text : { *(.text*) }
              }
            LD
          end

          def program_linker_script
            <<~LD
              SECTIONS {
                . = #{format('0x%X', PROGRAM_BASE)};
                .text : { *(.text*) }
                .rodata : { *(.rodata*) }
                .data : { *(.data*) }
                .bss : { *(.bss*) *(COMMON) }
              }
            LD
          end

          def program_source(program)
            <<~ASM
              .equ PROGRAM_BASE, #{format('0x%X', PROGRAM_BASE)}
              .equ STACK_TOP, #{format('0x%X', STACK_TOP)}
              .equ MAILBOX_STATUS, #{format('0x%X', MAILBOX_STATUS)}
              .equ MAILBOX_VALUE, #{format('0x%X', MAILBOX_VALUE)}

              .section .text
              nop
              nop
              nop
              nop
              nop
              nop
              nop
              nop

              #{program.program_source}
            ASM
          end
        end
      end
    end
  end
end
