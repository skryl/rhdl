# FIRRTL code generator for CIRCT toolchain
# Generates FIRRTL 5.1.0 format that can be compiled by firtool to Verilog

require_relative "../behavior/ir"

module RHDL
  module Export
    module CIRCT
      module FIRRTL
        FIRRTL_KEYWORDS = %w[
          circuit module input output wire reg node when else skip stop printf
          mux validif add sub mul div rem lt leq gt geq eq neq pad asUInt asSInt
          asClock asFixedPoint asInterval shl shr dshl dshr cvt neg not and or xor
          andr orr xorr cat bits head tail mux validif connect
        ].freeze

        module_function

        def generate(module_def)
          lines = []
          lines << "FIRRTL version 5.1.0"
          lines << "circuit #{sanitize(module_def.name)}:"
          lines << "  public module #{sanitize(module_def.name)}:"

          # Build set of output port names
          output_ports = module_def.ports.select { |p| p.direction == :out }.map(&:name).to_set
          output_widths = module_def.ports.select { |p| p.direction == :out }.map { |p| [p.name, p.width] }.to_h

          # Find clock for sequential processes
          clock = find_clock_for_reg(module_def, nil)

          # Collect targets of sequential assignments that are outputs (need internal registers)
          seq_targets = collect_seq_targets(module_def)
          seq_output_targets = seq_targets.select { |t| output_ports.include?(t) }

          # Ports
          module_def.ports.each do |port|
            dir = port.direction == :in ? "input" : "output"
            # Use Clock type for clock signals
            type = clock_port?(port.name) ? "Clock" : type_decl(port.width)
            lines << "    #{dir} #{sanitize(port.name)}: #{type}"
          end

          lines << "" unless module_def.ports.empty?

          # Internal wires (nets)
          module_def.nets.each do |net|
            lines << "    wire #{sanitize(net.name)}: #{type_decl(net.width)}"
          end

          # Explicit registers from IR
          module_def.regs.each do |reg|
            reg_clock = find_clock_for_reg(module_def, reg.name) || clock
            if reg_clock
              lines << "    reg #{sanitize(reg.name)}: #{type_decl(reg.width)}, #{sanitize(reg_clock)}"
            else
              lines << "    wire #{sanitize(reg.name)}: #{type_decl(reg.width)}"
            end
          end

          # Create internal registers for output ports that have sequential assignments
          seq_output_targets.each do |target|
            width = output_widths[target] || 1
            reg_name = "#{target}_reg"
            if clock
              lines << "    reg #{sanitize(reg_name)}: #{type_decl(width)}, #{sanitize(clock)}"
            end
          end

          # Memory arrays
          module_def.memories.each do |mem|
            lines << "    mem #{sanitize(mem.name)}:"
            lines << "      data-type => #{type_decl(mem.width)}"
            lines << "      depth => #{mem.depth}"
            lines << "      read-latency => 0"
            lines << "      write-latency => 1"
            lines << "      reader => read"
            lines << "      writer => write"
          end

          has_decls = !module_def.nets.empty? || !module_def.regs.empty? ||
                      !module_def.memories.empty? || !seq_output_targets.empty?
          lines << "" if has_decls

          # Continuous assignments
          module_def.assigns.each do |assign|
            lines << "    connect #{sanitize(assign.target)}, #{expr(assign.expr)}"
          end

          # Connect output ports to their internal registers
          seq_output_targets.each do |target|
            lines << "    connect #{sanitize(target)}, #{sanitize("#{target}_reg")}"
          end

          # Sequential processes (register updates)
          # Rewrite targets that are outputs to use internal registers
          module_def.processes.each do |process|
            if process.clocked
              process.statements.each do |stmt|
                lines.concat(statement(stmt, indent: 4, output_regs: seq_output_targets))
              end
            else
              # Combinational process - convert to assignments
              process.statements.each do |stmt|
                lines.concat(statement(stmt, indent: 4, output_regs: Set.new))
              end
            end
          end

          # Memory write ports
          module_def.write_ports.each do |wp|
            lines << "    connect #{sanitize(wp.memory)}.write.clk, #{sanitize(wp.clock)}"
            lines << "    connect #{sanitize(wp.memory)}.write.en, #{expr(wp.enable)}"
            lines << "    connect #{sanitize(wp.memory)}.write.addr, #{expr(wp.addr)}"
            lines << "    connect #{sanitize(wp.memory)}.write.data, #{expr(wp.data)}"
          end

          # Module instances
          module_def.instances.each do |instance|
            lines << ""
            lines << "    inst #{sanitize(instance.name)} of #{sanitize(instance.module_name)}"
            instance.connections.each do |conn|
              signal_str = conn.signal.is_a?(String) ? sanitize(conn.signal) : expr(conn.signal)
              lines << "    connect #{sanitize(instance.name)}.#{sanitize(conn.port_name)}, #{signal_str}"
            end
          end

          lines.join("\n")
        end

        def collect_seq_targets(module_def)
          targets = Set.new
          module_def.processes.each do |process|
            next unless process.clocked

            process.statements.each do |stmt|
              collect_targets_from_stmt(stmt, targets)
            end
          end
          targets
        end

        def collect_targets_from_stmt(stmt, targets)
          case stmt
          when IR::SeqAssign
            targets.add(stmt.target)
          when IR::If
            stmt.then_statements.each { |s| collect_targets_from_stmt(s, targets) }
            stmt.else_statements.each { |s| collect_targets_from_stmt(s, targets) }
          end
        end

        def find_clock_for_reg(module_def, reg_name)
          module_def.processes.each do |process|
            return process.clock if process.clocked && process.clock
          end
          nil
        end

        def clock_port?(name)
          name.to_s == "clk" || name.to_s == "clock"
        end

        def type_decl(width)
          "UInt<#{width}>"
        end

        def statement(stmt, indent:, output_regs: Set.new)
          pad = " " * indent
          case stmt
          when IR::SeqAssign
            # Rewrite target to use internal register if it's an output
            target = output_regs.include?(stmt.target) ? "#{stmt.target}_reg" : stmt.target
            ["#{pad}connect #{sanitize(target)}, #{expr(stmt.expr, output_regs: output_regs)}"]
          when IR::MemoryWrite
            ["#{pad}connect #{sanitize(stmt.memory)}[#{expr(stmt.addr)}], #{expr(stmt.data)}"]
          when IR::If
            lines = []
            lines << "#{pad}when #{expr(stmt.condition)}:"
            stmt.then_statements.each { |s| lines.concat(statement(s, indent: indent + 2, output_regs: output_regs)) }
            unless stmt.else_statements.empty?
              lines << "#{pad}else:"
              stmt.else_statements.each { |s| lines.concat(statement(s, indent: indent + 2, output_regs: output_regs)) }
            end
            lines
          else
            []
          end
        end

        def expr(expr_node, output_regs: Set.new)
          case expr_node
          when IR::Signal
            # Use internal register for sequential reads of outputs
            name = output_regs.include?(expr_node.name) ? "#{expr_node.name}_reg" : expr_node.name
            sanitize(name)
          when IR::Literal
            literal(expr_node.value, expr_node.width)
          when IR::UnaryOp
            unary_expr(expr_node, output_regs: output_regs)
          when IR::BinaryOp
            binary_expr(expr_node, output_regs: output_regs)
          when IR::Mux
            "mux(#{expr(expr_node.condition, output_regs: output_regs)}, #{expr(expr_node.when_true, output_regs: output_regs)}, #{expr(expr_node.when_false, output_regs: output_regs)})"
          when IR::Concat
            "cat(#{expr_node.parts.map { |p| expr(p, output_regs: output_regs) }.join(', ')})"
          when IR::Slice
            slice_expr(expr_node, output_regs: output_regs)
          when IR::Resize
            resize_expr(expr_node, output_regs: output_regs)
          when IR::Case
            case_expr(expr_node, output_regs: output_regs)
          when IR::MemoryRead
            "#{sanitize(expr_node.memory)}[#{expr(expr_node.addr, output_regs: output_regs)}]"
          else
            raise ArgumentError, "Unsupported FIRRTL expression: #{expr_node.inspect}"
          end
        end

        def unary_expr(node, output_regs: Set.new)
          case node.op
          when :~
            "not(#{expr(node.operand, output_regs: output_regs)})"
          when :!
            "not(#{expr(node.operand, output_regs: output_regs)})"
          else
            raise ArgumentError, "Unsupported unary op: #{node.op}"
          end
        end

        def binary_expr(node, output_regs: Set.new)
          left = expr(node.left, output_regs: output_regs)
          right = expr(node.right, output_regs: output_regs)

          case node.op
          when :&
            "and(#{left}, #{right})"
          when :|
            "or(#{left}, #{right})"
          when :^
            "xor(#{left}, #{right})"
          when :+
            "add(#{left}, #{right})"
          when :-
            "sub(#{left}, #{right})"
          when :*
            "mul(#{left}, #{right})"
          when :/
            "div(#{left}, #{right})"
          when :%
            "rem(#{left}, #{right})"
          when :<<
            "shl(#{left}, #{right})"
          when :>>
            "shr(#{left}, #{right})"
          when :==
            "eq(#{left}, #{right})"
          when :!=
            "neq(#{left}, #{right})"
          when :<
            "lt(#{left}, #{right})"
          when :>
            "gt(#{left}, #{right})"
          when :<=
            "leq(#{left}, #{right})"
          when :>=
            "geq(#{left}, #{right})"
          else
            raise ArgumentError, "Unsupported binary op: #{node.op}"
          end
        end

        def slice_expr(node, output_regs: Set.new)
          base = expr(node.base, output_regs: output_regs)
          high = [node.range.begin, node.range.end].max
          low = [node.range.begin, node.range.end].min

          "bits(#{base}, #{high}, #{low})"
        end

        def resize_expr(node, output_regs: Set.new)
          inner = expr(node.expr, output_regs: output_regs)
          target_width = node.width
          source_width = node.expr.width

          if target_width == source_width
            inner
          elsif target_width > source_width
            "pad(#{inner}, #{target_width})"
          else
            "bits(#{inner}, #{target_width - 1}, 0)"
          end
        end

        def case_expr(node, output_regs: Set.new)
          # Convert case to nested mux
          selector = expr(node.selector, output_regs: output_regs)
          default_expr = node.default ? expr(node.default, output_regs: output_regs) : literal(0, node.width)

          result = default_expr
          node.cases.reverse_each do |values, branch|
            values.each do |v|
              cond = "eq(#{selector}, #{literal(v, node.selector.width)})"
              result = "mux(#{cond}, #{expr(branch, output_regs: output_regs)}, #{result})"
            end
          end
          result
        end

        def literal(value, width)
          "UInt<#{width}>(#{value})"
        end

        def sanitize(name)
          base = name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
          base = "_#{base}" if base.match?(/\A\d/)
          return "#{base}_fir" if FIRRTL_KEYWORDS.include?(base.downcase)

          base
        end
      end
    end
  end
end
