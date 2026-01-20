# Topological sort for gate scheduling

module RHDL
  module Codegen
    module Structure
      module Toposort
        def self.schedule(gates)
          output_to_gate = {}
          gates.each_with_index { |g, idx| output_to_gate[g.output] = idx }

          indegree = Array.new(gates.length, 0)
          edges = Array.new(gates.length) { [] }

          gates.each_with_index do |gate, idx|
            gate.inputs.each do |net|
              producer = output_to_gate[net]
              next unless producer

              edges[producer] << idx
              indegree[idx] += 1
            end
          end

          queue = indegree.each_index.select { |i| indegree[i].zero? }
          order = []
          until queue.empty?
            node = queue.shift
            order << node
            edges[node].each do |succ|
              indegree[succ] -= 1
              queue << succ if indegree[succ].zero?
            end
          end

          order.length == gates.length ? order : (0...gates.length).to_a
        end
      end
    end
  end
end
