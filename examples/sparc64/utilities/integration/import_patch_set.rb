# frozen_string_literal: true

module RHDL
  module Examples
    module SPARC64
      module Integration
        module ImportPatchSet
          PATCH_ROOT = File.expand_path('../../patches', __dir__).freeze
          MINIMAL_PATCH_DIR = File.join(PATCH_ROOT, 'minimal').freeze
          MINIMAL_MEM_SIZE = "64'h00000000_00000020"
          MINIMAL_PATCH_TARGETS = %w[
            os2wb/os2wb_dual.v
            T1-CPU/ifu/sparc_ifu_swl.v
          ].freeze

          class << self
            def patches_dir(fast_boot: false, override: nil)
              return nil if override_disabled?(override)
              return File.expand_path(override) if override
              return MINIMAL_PATCH_DIR if fast_boot

              nil
            end

            def patch_files(fast_boot: false, override: nil)
              patch_dir_files(patches_dir(fast_boot: fast_boot, override: override))
            end

            def staged_verilog_patches_dir(fast_boot: false, override: nil)
              return nil if override_disabled?(override)
              return File.expand_path(override) if override
              MINIMAL_PATCH_DIR
            end

            def staged_verilog_patch_files(fast_boot: false, override: nil)
              patch_dir_files(staged_verilog_patches_dir(fast_boot: fast_boot, override: override))
            end

            private

            def override_disabled?(override)
              override == :none || override == false
            end

            def patch_dir_files(root)
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
