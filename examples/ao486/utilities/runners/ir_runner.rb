# frozen_string_literal: true

require 'tmpdir'
require 'thread'

require 'rhdl/codegen'
require 'rhdl/sim/native/ir/simulator'

require_relative 'backend_runner'
require_relative '../import/cpu_importer'
require_relative '../import/cpu_parity_package'
require_relative '../import/cpu_runner_package'

module RHDL
  module Examples
    module AO486
      class IrRunner < BackendRunner
        class << self
          def runtime_bundle(backend:)
            mutex.synchronize do
              runtime_cache[backend] ||= build_runtime_bundle(backend: backend)
            end
          end

          private

          def runtime_cache
            @runtime_cache ||= {}
          end

          def mutex
            @mutex ||= Mutex.new
          end

          def build_runtime_bundle(backend:)
            out_dir = Dir.mktmpdir('rhdl_ao486_ir_runner_out')
            workspace_dir = Dir.mktmpdir('rhdl_ao486_ir_runner_ws')
            import_result = RHDL::Examples::AO486::Import::CpuImporter.new(
              output_dir: out_dir,
              workspace_dir: workspace_dir,
              keep_workspace: true,
              strict: false
            ).run

            cleaned_mlir = File.read(import_result.normalized_core_mlir_path)
            runner_pkg = RHDL::Examples::AO486::Import::CpuRunnerPackage.from_cleaned_mlir(cleaned_mlir)
            raise Array(runner_pkg[:diagnostics]).join("\n") unless runner_pkg[:success]

            flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(runner_pkg.fetch(:package), top: 'ao486')
            {
              backend: backend,
              ir_json: RHDL::Sim::Native::IR.sim_json(flat, backend: backend),
              import_result: import_result
            }
          end
        end

        attr_reader :sim

        def initialize(backend: :compile, **kwargs)
          super(backend: :ir, sim: backend, **kwargs)
          @sim = nil
          @runtime_loaded = false
        end

        def simulator_type
          :"ao486_ir_#{sim_backend}"
        end

        def load_bios(**kwargs)
          metadata = super
          if @sim
            sync_rom_segment(File.binread(bios_paths.fetch(:boot0)).bytes, BOOT0_ADDR)
            sync_rom_segment(File.binread(bios_paths.fetch(:boot1)).bytes, BOOT1_ADDR)
          end
          metadata
        end

        def load_dos(**kwargs)
          metadata = super
          @sim&.runner_load_disk(metadata.fetch(:bytes), 0)
          metadata
        end

        def load_bytes(base, bytes, target: memory_store)
          super
          @sim&.runner_load_memory(Array(bytes), base, false)
          self
        end

        def read_bytes(base, length, mapped: true)
          return super unless @sim

          @sim.runner_read_memory(base, length, mapped: mapped)
        end

        def write_memory(addr, value)
          super
          @sim&.runner_write_memory(addr, [value.to_i & 0xFF], mapped: false)
        end

        def reset
          super
          return self unless @sim

          @sim.reset
          sync_runtime_windows!
          self
        end

        def run(cycles: nil, speed: nil, headless: @headless)
          ensure_sim!
          chunk = cycles || @requested_cycles || speed || @speed || 0
          result = @sim.runner_run_cycles(chunk.to_i, 0, false) || { cycles_run: 0 }
          @cycles_run += result[:cycles_run].to_i
          sync_runtime_windows!
          state.merge(cycles: @cycles_run, speed: speed || @speed, headless: headless)
        end

        def peek(signal_name)
          ensure_sim!
          @sim.peek(signal_name)
        end

        private

        def ensure_sim!
          return @sim if @sim

          bundle = self.class.runtime_bundle(backend: sim_backend || :compile)
          @sim = RHDL::Sim::Native::IR::Simulator.new(
            bundle.fetch(:ir_json),
            backend: bundle.fetch(:backend)
          )
          raise "Imported AO486 runner did not bind to native :ao486 mode" unless @sim.runner_kind == :ao486

          @sim.reset
          sync_loaded_artifacts_to_sim!
          sync_runtime_windows!
          @runtime_loaded = true
          @sim
        end

        def sync_loaded_artifacts_to_sim!
          sync_sparse_store!(rom_store, rom: true)
          sync_sparse_store!(memory_store, rom: false)
          sync_disk_image!
        end

        def sync_sparse_store!(store, rom:)
          contiguous_ranges(store).each do |offset, bytes|
            if rom
              @sim.runner_load_rom(bytes, offset)
            else
              @sim.runner_load_memory(bytes, offset, false)
            end
          end
        end

        def contiguous_ranges(store)
          return [] if store.empty?

          ranges = []
          current_start = nil
          current_end = nil
          current_bytes = []

          store.keys.sort.each do |addr|
            if current_start.nil?
              current_start = addr
              current_end = addr
              current_bytes = [store.fetch(addr)]
              next
            end

            if addr == current_end + 1
              current_end = addr
              current_bytes << store.fetch(addr)
            else
              ranges << [current_start, current_bytes]
              current_start = addr
              current_end = addr
              current_bytes = [store.fetch(addr)]
            end
          end

          ranges << [current_start, current_bytes] unless current_start.nil?
          ranges
        end

        def sync_rom_segment(bytes, base)
          return unless @sim

          @sim.runner_load_rom(bytes, base)
        end

        def sync_disk_image!
          return unless @sim
          return unless dos_loaded?

          @sim.runner_load_disk(@floppy_image.bytes, 0)
        end

        def sync_runtime_windows!
          sync_display_window!
          sync_cursor_window!
        end

        def sync_display_window!
          bytes = @sim.runner_read_memory(
            DisplayAdapter::TEXT_BASE,
            DisplayAdapter::TEXT_ROWS * DisplayAdapter::TEXT_COLUMNS * 2,
            mapped: true
          )
          update_display_buffer(bytes)
        end

        def sync_cursor_window!
          bytes = @sim.runner_read_memory(DisplayAdapter::CURSOR_BDA, 2, mapped: true)
          memory_store[DisplayAdapter::CURSOR_BDA] = bytes.fetch(0, 0)
          memory_store[DisplayAdapter::CURSOR_BDA + 1] = bytes.fetch(1, 0)
        end
      end
    end
  end
end
