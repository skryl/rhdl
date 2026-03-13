# frozen_string_literal: true

module RHDL
  module Examples
    module AO486
      module Unit
        COVERED_SOURCE_FILES = {
            "ao486/ao486.v" => %w[ao486],
            "ao486/exception.v" => %w[exception],
            "ao486/global_regs.v" => %w[global_regs],
            "ao486/memory/avalon_mem.v" => %w[avalon_mem],
            "ao486/memory/icache.v" => %w[icache],
            "ao486/memory/link_dcacheread.v" => %w[link_dcacheread],
            "ao486/memory/link_dcachewrite.v" => %w[link_dcachewrite],
            "ao486/memory/memory.v" => %w[memory],
            "ao486/memory/memory_read.v" => %w[memory_read],
            "ao486/memory/memory_write.v" => %w[memory_write],
            "ao486/memory/prefetch.v" => %w[prefetch],
            "ao486/memory/prefetch_control.v" => %w[prefetch_control],
            "ao486/memory/prefetch_fifo.v" => %w[prefetch_fifo],
            "ao486/memory/tlb.v" => %w[tlb],
            "ao486/memory/tlb_memtype.v" => %w[tlb_memtype],
            "ao486/memory/tlb_regs.v" => %w[tlb_regs],
            "ao486/pipeline/condition.v" => %w[condition],
            "ao486/pipeline/decode.v" => %w[decode],
            "ao486/pipeline/decode_commands.v" => %w[decode_commands],
            "ao486/pipeline/decode_prefix.v" => %w[decode_prefix],
            "ao486/pipeline/decode_ready.v" => %w[decode_ready],
            "ao486/pipeline/decode_regs.v" => %w[decode_regs],
            "ao486/pipeline/execute.v" => %w[execute],
            "ao486/pipeline/execute_commands.v" => %w[execute_commands],
            "ao486/pipeline/execute_divide.v" => %w[execute_divide],
            "ao486/pipeline/execute_multiply.v" => %w[execute_multiply],
            "ao486/pipeline/execute_offset.v" => %w[execute_offset],
            "ao486/pipeline/execute_shift.v" => %w[execute_shift],
            "ao486/pipeline/fetch.v" => %w[fetch],
            "ao486/pipeline/microcode.v" => %w[microcode],
            "ao486/pipeline/microcode_commands.v" => %w[microcode_commands],
            "ao486/pipeline/pipeline.v" => %w[pipeline],
            "ao486/pipeline/read.v" => %w[read],
            "ao486/pipeline/read_commands.v" => %w[read_commands],
            "ao486/pipeline/read_debug.v" => %w[read_debug],
            "ao486/pipeline/read_effective_address.v" => %w[read_effective_address],
            "ao486/pipeline/read_mutex.v" => %w[read_mutex],
            "ao486/pipeline/read_segment.v" => %w[read_segment],
            "ao486/pipeline/write.v" => %w[write],
            "ao486/pipeline/write_commands.v" => %w[write_commands],
            "ao486/pipeline/write_debug.v" => %w[write_debug],
            "ao486/pipeline/write_register.v" => %w[write_register],
            "ao486/pipeline/write_stack.v" => %w[write_stack],
            "ao486/pipeline/write_string.v" => %w[write_string],
            "cache/l1_icache.v" => %w[l1_icache],
            "common/simple_fifo_mlab.v" => %w[simple_fifo_mlab],
            "common/simple_mult.v" => %w[simple_mult]        }.freeze

        COVERED_SOURCE_FILE_COUNT = COVERED_SOURCE_FILES.size
        COVERED_MODULE_COUNT = COVERED_SOURCE_FILES.values.sum(&:size)

        def self.spec_relative_path_for(source_relative_path)
          basename = "#{File.basename(source_relative_path, File.extname(source_relative_path))}_spec.rb"
          dirname = File.dirname(source_relative_path)
          return basename if dirname == '.'

          File.join(dirname, basename)
        end
      end
    end
  end
end
