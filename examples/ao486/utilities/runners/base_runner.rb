# frozen_string_literal: true

require_relative '../display_adapter'

module RHDL
  module Examples
    module AO486
      module RunnerSupport
        module_function

        def software_root
          File.expand_path('../../software', __dir__)
        end

        def software_path(*segments)
          flattened = segments.flatten.compact.map(&:to_s)
          return software_root if flattened.empty?

          File.expand_path(File.join(*flattened), software_root)
        end

        def bios_paths
          {
            boot0: software_path('rom', 'boot0.rom'),
            boot1: software_path('rom', 'boot1.rom')
          }
        end

        def dos_path
          software_path('bin', 'msdos4_disk1.img')
        end
      end

      module RunnerCommon
        TEXT_MODE_BASE = 0xB8000
        TEXT_MODE_COLUMNS = DisplayAdapter::TEXT_COLUMNS
        TEXT_MODE_ROWS = DisplayAdapter::TEXT_ROWS
        TEXT_MODE_BUFFER_SIZE = DisplayAdapter::BUFFER_SIZE

        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          def software_root
            RunnerSupport.software_root
          end

          def software_path(*segments)
            RunnerSupport.software_path(*segments)
          end

          def bios_paths
            RunnerSupport.bios_paths
          end

          def dos_path
            RunnerSupport.dos_path
          end
        end

        attr_reader :mode, :backend, :debug, :speed, :headless, :cycles, :bios_images, :dos_image

        def initialize(mode:, backend:, debug: false, speed: nil, headless: false, cycles: nil,
                       display_adapter: DisplayAdapter.new)
          @mode = mode.to_sym
          @backend = backend.to_sym
          @debug = !!debug
          @speed = speed
          @headless = !!headless
          @cycles = cycles
          @display_adapter = display_adapter
          reset
        end

        def software_root
          self.class.software_root
        end

        def software_path(*segments)
          self.class.software_path(*segments)
        end

        def bios_paths
          self.class.bios_paths
        end

        def dos_path
          self.class.dos_path
        end

        def load_bios(boot0: bios_paths.fetch(:boot0), boot1: bios_paths.fetch(:boot1))
          @bios_images = {
            boot0: read_binary_file(boot0, label: 'AO486 BIOS ROM'),
            boot1: read_binary_file(boot1, label: 'AO486 BIOS ROM')
          }
        end

        def load_dos(path: dos_path)
          @dos_image = read_binary_file(path, label: 'AO486 DOS image')
        end

        def bios_loaded?
          !@bios_images.nil?
        end

        def dos_loaded?
          !@dos_image.nil?
        end

        def reset
          @run_cycles = 0
          @display_buffer = Array.new(TEXT_MODE_BUFFER_SIZE, 0)
          self
        end

        def run(cycles = nil)
          @run_cycles += resolve_run_cycles(cycles)
          state
        end

        def native?
          false
        end

        def simulator_type
          :"ao486_#{mode}"
        end

        def state
          {
            mode: mode,
            backend: backend,
            simulator_type: simulator_type,
            native: native?,
            cycles: @run_cycles,
            speed: speed,
            headless: headless,
            bios_loaded: bios_loaded?,
            dos_loaded: dos_loaded?
          }
        end

        def display_buffer
          @display_buffer.dup
        end

        def update_display_buffer(bytes)
          @display_buffer = normalize_display_buffer(bytes)
        end

        def render_display(debug_lines: default_debug_lines)
          @display_adapter.render(@display_buffer, debug_lines: debug_lines)
        end

        private

        def default_debug_lines
          [
            "mode=#{mode}",
            "backend=#{backend}",
            "cycles=#{@run_cycles}",
            "bios=#{bios_loaded? ? 'loaded' : 'missing'} dos=#{dos_loaded? ? 'loaded' : 'missing'}"
          ]
        end

        def read_binary_file(path, label:)
          resolved = File.expand_path(path.to_s)
          unless File.file?(resolved)
            raise ArgumentError, "#{label} not found: #{resolved}"
          end

          bytes = File.binread(resolved)
          {
            path: resolved,
            bytes: bytes,
            size: bytes.bytesize
          }
        end

        def normalize_display_buffer(bytes)
          raw =
            case bytes
            when String
              bytes.b.bytes
            when Array
              bytes.map { |byte| byte.to_i & 0xFF }
            else
              raise ArgumentError, "AO486 display buffer must be a String or Array of bytes, got #{bytes.class}"
            end

          raw.fill(0, raw.length...TEXT_MODE_BUFFER_SIZE) if raw.length < TEXT_MODE_BUFFER_SIZE
          raw.first(TEXT_MODE_BUFFER_SIZE)
        end

        def resolve_run_cycles(cycles)
          value = cycles.nil? ? (@cycles || 0) : cycles
          value.to_i
        end
      end
    end
  end
end
