# frozen_string_literal: true

require_relative '../../../lib/rhdl'

module RHDL
  module Examples
    module GameBoy
      # Loader for selecting which Game Boy HDL source tree to use at runtime.
      module HdlLoader
        HDL_DIR_ENV = 'RHDL_GAMEBOY_HDL_DIR'
        DEFAULT_HDL_DIR = File.expand_path('../hdl', __dir__).freeze
        ORDERED_COMPONENT_FILES = %w[
          cpu/alu
          cpu/registers
          cpu/mcode
          cpu/sm83
          ppu/sprites
          ppu/lcd
          ppu/video
          apu/channel_square
          apu/channel_wave
          apu/channel_noise
          apu/sound
          memory/dpram
          memory/spram
          dma/hdma
          mappers/mappers
          timer
          link
          speedcontrol
          gb
        ].freeze

        class << self
          def resolve_hdl_dir(hdl_dir: nil)
            File.expand_path(hdl_dir || ENV[HDL_DIR_ENV] || DEFAULT_HDL_DIR)
          end

          def loaded_from
            @loaded_from
          end

          def configure!(hdl_dir: nil)
            resolved = resolve_hdl_dir(hdl_dir: hdl_dir)
            if loaded_from && loaded_from != resolved
              raise ArgumentError,
                    "Game Boy HDL is already loaded from #{loaded_from}; "\
                    "cannot switch to #{resolved} in the same process"
            end
            ENV[HDL_DIR_ENV] = resolved
            resolved
          end

          def load_component_tree!(hdl_dir: nil)
            resolved = configure!(hdl_dir: hdl_dir)
            raise ArgumentError, "Game Boy HDL directory not found: #{resolved}" unless Dir.exist?(resolved)
            return resolved if loaded_from == resolved

            if resolved == DEFAULT_HDL_DIR
              require_ordered_components(resolved)
            else
              require_directory_tree_with_retries(resolved)
              install_import_compat_aliases
            end

            @loaded_from = resolved
            resolved
          end

          private

          def require_ordered_components(root)
            ORDERED_COMPONENT_FILES.each do |relative|
              path = File.join(root, "#{relative}.rb")
              raise ArgumentError, "Expected Game Boy HDL file missing: #{path}" unless File.file?(path)

              require path
            end
          end

          def require_directory_tree_with_retries(root)
            files = Dir.glob(File.join(root, '**', '*.rb')).sort
            raise ArgumentError, "No Ruby HDL files found in #{root}" if files.empty?

            pending = files
            last_errors = {}

            while pending.any?
              progressed = false
              still_pending = []

              pending.each do |path|
                begin
                  require path
                  progressed = true
                rescue NameError => e
                  still_pending << path
                  last_errors[path] = e
                end
              end

              break if still_pending.empty?
              unless progressed
                details = still_pending.first(8).map do |path|
                  "#{path}: #{last_errors[path].message}"
                end.join("\n")

                raise RuntimeError,
                      "Unable to resolve dependencies while loading HDL directory #{root}.\n#{details}"
              end

              pending = still_pending
            end
          end

          def install_import_compat_aliases
            if Object.const_defined?(:Gb, false) && !Object.const_defined?(:GB, false)
              Object.const_set(:GB, Object.const_get(:Gb, false))
            end
          end
        end
      end
    end
  end
end
