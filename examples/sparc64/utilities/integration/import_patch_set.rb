# frozen_string_literal: true

module RHDL
  module Examples
    module SPARC64
      module Integration
        module ImportPatchSet
          PATCH_ROOT = File.expand_path('patches', __dir__).freeze
          FAST_BOOT_PATCH_DIR = File.join(PATCH_ROOT, 'fast_boot').freeze
          FAST_BOOT_MEM_SIZE = "64'h00000000_00000020"
          FAST_BOOT_PATCH_TARGETS = %w[
            os2wb/os2wb.v
            os2wb/os2wb_dual.v
            T1-CPU/exu/sparc_exu_rml.v
            T1-CPU/ifu/sparc_ifu.v
            T1-CPU/ifu/sparc_ifu_swl.v
            T1-CPU/ifu/sparc_ifu_fdp.v
            T1-CPU/lsu/lsu_qctl1.v
            T1-CPU/rtl/sparc.v
          ].freeze

          class << self
            def patches_dir(fast_boot: false, override: nil)
              return File.expand_path(override) if override
              return FAST_BOOT_PATCH_DIR if fast_boot

              nil
            end

            def patch_files(fast_boot: false, override: nil)
              root = patches_dir(fast_boot: fast_boot, override: override)
              return [] unless root && Dir.exist?(root)

              Dir.glob(File.join(root, '**', '*'))
                 .select { |path| File.file?(path) && %w[.patch .diff].include?(File.extname(path)) }
                 .sort
            end
          end
        end
      end
    end
  end
end
