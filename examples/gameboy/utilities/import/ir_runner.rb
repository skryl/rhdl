# frozen_string_literal: true

require 'json'
require 'rhdl/codegen'
require 'rhdl/sim/native/ir/simulator'

module RHDL
  module Examples
    module GameBoy
      module Import
        # IR runner that can execute either:
        # - a raised component class, or
        # - imported CIRCT MLIR raised in-memory.
        #
        # This runner is intentionally minimal and geared toward deterministic
        # import parity checks.
        class IrRunner
          RuntimePort = Struct.new(:name, :direction, :width, keyword_init: true)
          RuntimeSignal = Struct.new(:name, :width, keyword_init: true)
          RuntimeModule = Struct.new(:ports, :nets, :regs, keyword_init: true)

          attr_reader :cycles, :backend, :top_name

          def initialize(component_class: nil, mlir: nil, runtime_json: nil, top: 'gb', backend: :compile)
            @backend = backend
            @top_name = top.to_s
            resolved = resolve_nodes(
              component_class: component_class,
              mlir: mlir,
              runtime_json: runtime_json,
              top: @top_name
            )
            @nodes = resolved.fetch(:top_module)
            @runtime_nodes = resolved.fetch(:runtime_nodes)

            @input_ports = @nodes.ports.select { |port| port.direction == :in }.map { |port| port.name.to_s }
            @output_ports = @nodes.ports.select { |port| port.direction == :out }.map { |port| port.name.to_s }
            @signal_names = (@nodes.ports.map { |port| port.name.to_s } +
              @nodes.nets.map { |net| net.name.to_s } +
              @nodes.regs.map { |reg| reg.name.to_s }).uniq
            @port_lookup = (@input_ports + @output_ports).each_with_object({}) do |name, acc|
              acc[name] = name
              acc[name.downcase] ||= name
            end
            @signal_lookup = @signal_names.each_with_object({}) do |name, acc|
              acc[name] = name
              acc[name.downcase] ||= name
            end
            @signal_index_cache = {}

            @sim = RHDL::Sim::Native::IR::Simulator.new(
              RHDL::Sim::Native::IR.sim_json(@runtime_nodes, backend: backend),
              backend: backend
            )

            @cycles = 0
            @rom = []
            initialize_inputs
          end

          def load_rom(bytes)
            bytes = bytes.bytes if bytes.is_a?(String)
            @rom = bytes.dup
          end

          def reset
            poke(:reset, 1)
            run_cycles(10)
            poke(:reset, 0)
            run_cycles(100)
            poke(%w[joystick], 0xFF)
            @cycles = 0
          end

          def run_steps(steps)
            steps.to_i.times do
              run_machine_cycle
              @cycles += 1
            end
          end

          def cycle_count
            @cycles
          end

          def native?
            @sim.native?
          end

          def simulator_type
            @sim.simulator_type
          end

          def peek(name)
            signal = resolve_signal_name(name)
            return 0 unless signal

            @sim.peek(signal)
          rescue StandardError
            0
          end

          def snapshot(signal_names)
            Array(signal_names).each_with_object({}) do |name, acc|
              acc[name.to_s] = peek(name)
            end
          end

          def signal_available?(name_or_candidates)
            !resolve_signal_name(name_or_candidates).nil?
          end

          def signal_index(name_or_candidates)
            signal = resolve_signal_name(name_or_candidates)
            return nil if signal.nil?
            return nil unless @sim.respond_to?(:get_signal_idx)

            @signal_index_cache.fetch(signal) do
              @signal_index_cache[signal] = @sim.get_signal_idx(signal)
            end
          rescue StandardError
            nil
          end

          def peek_index(idx)
            return 0 if idx.nil?
            return 0 unless @sim.respond_to?(:peek_by_idx)

            @sim.peek_by_idx(idx)
          rescue StandardError
            0
          end

          def input_ports
            @input_ports.dup
          end

          def output_ports
            @output_ports.dup
          end

          private

          def resolve_nodes(component_class:, mlir:, runtime_json:, top:)
            provided = [component_class, mlir, runtime_json].compact
            if provided.length > 1
              raise ArgumentError, 'Provide only one of component_class, mlir, or runtime_json'
            end

            if component_class
              flat = component_class.to_flat_circt_nodes(top_name: top)
              return { top_module: flat, runtime_nodes: flat }
            end

            if mlir
              imported = RHDL::Codegen.import_circt_mlir(mlir, strict: true, top: top)
              unless imported.success?
                message = Array(imported.diagnostics).map { |diag| diag.respond_to?(:message) ? diag.message : diag.to_s }.join("\n")
                raise RuntimeError, "Failed to import CIRCT MLIR for runtime:\n#{message}"
              end

              flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(imported.modules, top: top)
              return { top_module: flat, runtime_nodes: flat }
            end

            if runtime_json
              payload = runtime_json.is_a?(String) ? JSON.parse(runtime_json, max_nesting: false) : runtime_json
              module_payload = Array(payload['modules']).find { |mod| mod['name'].to_s == top } || Array(payload['modules']).first
              raise ArgumentError, "Runtime JSON missing module '#{top}'" unless module_payload

              return {
                top_module: runtime_module_from_payload(module_payload),
                runtime_nodes: runtime_json
              }
            end

            raise ArgumentError, 'One of component_class, mlir, or runtime_json is required'
          end

          def runtime_module_from_payload(payload)
            RuntimeModule.new(
              ports: Array(payload['ports']).map do |port|
                RuntimePort.new(
                  name: port.fetch('name'),
                  direction: port.fetch('direction').to_sym,
                  width: port.fetch('width').to_i
                )
              end,
              nets: Array(payload['nets']).map do |net|
                RuntimeSignal.new(name: net.fetch('name'), width: net.fetch('width').to_i)
              end,
              regs: Array(payload['regs']).map do |reg|
                RuntimeSignal.new(name: reg.fetch('name'), width: reg.fetch('width').to_i)
              end
            )
          end

          def initialize_inputs
            @input_ports.each { |name| @sim.poke(name, 0) }
            poke(%w[clk_sys], 0)
            poke(%w[ce], 1)
            poke(%w[ce_n], 1)
            poke(%w[ce_2x], 1)
            poke(%w[joystick], 0xFF)
            poke(%w[cart_oe], 1)
            @sim.evaluate
          end

          def run_machine_cycle
            4.times { run_clock_cycle }
          end

          def run_clock_cycle
            poke(%w[clk_sys], 0)
            drive_clock_enable_inputs(falling_edge: false)
            @sim.evaluate
            handle_memory_access

            drive_clock_enable_inputs(falling_edge: false)
            poke(%w[clk_sys], 1)
            @sim.tick
          end

          def run_cycles(steps)
            steps.to_i.times { run_clock_cycle }
          end
          def handle_memory_access
            cart_rd = peek(%w[cart_rd])
            return unless cart_rd == 1

            addr = peek(%w[ext_bus_addr])
            a15 = peek(%w[ext_bus_a15])
            full_addr = ((a15 & 0x1) << 15) | (addr & 0x7FFF)
            poke(%w[cart_do], read_rom(full_addr))
          end

          def read_rom(addr)
            @rom[addr & 0xFFFF] || 0
          end

          def poke(candidates, value = nil)
            if candidates.is_a?(Array)
              port = resolve_port_name(candidates)
              return if port.nil?

              @sim.poke(port, value || 0)
              return
            end

            port = resolve_port_name(candidates)
            return if port.nil?

            @sim.poke(port, value || 0)
          end

          def resolve_port_name(name_or_candidates)
            candidates = Array(name_or_candidates).map(&:to_s)
            candidates.each do |candidate|
              resolved = @port_lookup[candidate] || @port_lookup[candidate.downcase]
              return resolved if resolved
            end

            nil
          end

          def resolve_signal_name(name_or_candidates)
            candidates = Array(name_or_candidates).map(&:to_s)
            candidates.each do |candidate|
              resolved = @signal_lookup[candidate] || @signal_lookup[candidate.downcase]
              return resolved if resolved
            end

            nil
          end

          def drive_clock_enable_inputs(falling_edge:)
            poke(%w[ce], falling_edge ? 0 : 1)
            poke(%w[ce_n], falling_edge ? 1 : 0)
            poke(%w[ce_2x], 1)
          end
        end
      end
    end
  end
end
