# frozen_string_literal: true

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
          attr_reader :cycles, :backend, :top_name

          def initialize(component_class: nil, mlir: nil, top: 'gb', backend: :compile)
            @backend = backend
            @top_name = top.to_s
            @nodes = resolve_nodes(component_class: component_class, mlir: mlir, top: @top_name)

            @input_ports = @nodes.ports.select { |port| port.direction == :in }.map { |port| port.name.to_s }
            @output_ports = @nodes.ports.select { |port| port.direction == :out }.map { |port| port.name.to_s }

            @sim = RHDL::Sim::Native::IR::Simulator.new(
              RHDL::Sim::Native::IR.sim_json(@nodes, backend: backend),
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
            run_steps(8)
            poke(:reset, 0)
            run_steps(16)
            @cycles = 0
          end

          def run_steps(steps)
            steps.to_i.times do
              run_cycle
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
            port = resolve_port_name(name)
            return 0 unless port

            @sim.peek(port)
          rescue StandardError
            0
          end

          def snapshot(signal_names)
            Array(signal_names).each_with_object({}) do |name, acc|
              acc[name.to_s] = peek(name)
            end
          end

          def input_ports
            @input_ports.dup
          end

          def output_ports
            @output_ports.dup
          end

          private

          def resolve_nodes(component_class:, mlir:, top:)
            if component_class && mlir
              raise ArgumentError, 'Provide either component_class or mlir, not both'
            end

            if component_class
              return component_class.to_flat_circt_nodes(top_name: top)
            end

            if mlir
              raised = RHDL::Codegen.raise_circt_components(mlir, namespace: Module.new, top: top, strict: true)
              unless raised.success?
                message = Array(raised.diagnostics).map { |diag| diag.respond_to?(:message) ? diag.message : diag.to_s }.join("\n")
                raise RuntimeError, "Failed to raise imported MLIR components:\n#{message}"
              end

              component = raised.components.fetch(top) do
                raise KeyError, "Top component '#{top}' not present in raised import set"
              end
              return component.to_flat_circt_nodes(top_name: top)
            end

            raise ArgumentError, 'One of component_class or mlir is required'
          end

          def initialize_inputs
            @input_ports.each { |name| @sim.poke(name, 0) }
            poke(%w[joystick], 0xFF)
            poke(%w[cart_oe], 1)
            @sim.evaluate
          end

          def run_cycle
            poke(%w[ce], 1)
            poke(%w[ce_n], 0)
            poke(%w[ce_2x], 1)
            @sim.evaluate
            handle_memory_access

            poke(%w[ce], 0)
            poke(%w[ce_n], 1)
            @sim.tick
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
              return candidate if @input_ports.include?(candidate) || @output_ports.include?(candidate)
            end

            lowered = (@input_ports + @output_ports).map(&:downcase)
            candidates.each do |candidate|
              idx = lowered.index(candidate.downcase)
              next if idx.nil?

              ports = @input_ports + @output_ports
              return ports[idx]
            end

            nil
          end
        end
      end
    end
  end
end
