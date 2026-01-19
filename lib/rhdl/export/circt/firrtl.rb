# FIRRTL code generator for CIRCT toolchain
# Generates FIRRTL 1.0 format that can be compiled by firtool to Verilog

require_relative "../behavior/ir"

module RHDL
  module Export
    module CIRCT
      module FIRRTL
        FIRRTL_KEYWORDS = %w[
          circuit module input output wire reg node when else skip stop printf
          mux validif add sub mul div rem lt leq gt geq eq neq pad asUInt asSInt
          asClock asFixedPoint asInterval shl shr dshl dshr cvt neg not and or xor
          andr orr xorr cat bits head tail mux validif
        ].freeze

        module_function

        def generate(module_def)
          lines = []
          lines << "FIRRTL version 1.0.0"
          lines << "circuit #{sanitize(module_def.name)}:"
          lines << "  module #{sanitize(module_def.name)}:"

          # Ports
          module_def.ports.each do |port|
            dir = port.direction == :in ? "input" : "output"
            lines << "    #{dir} #{sanitize(port.name)}: #{type_decl(port.width)}"
          end

          lines << "" unless module_def.ports.empty?

          # Internal wires (nets)
          module_def.nets.each do |net|
            lines << "    wire #{sanitize(net.name)}: #{type_decl(net.width)}"
          end

          # Registers
          module_def.regs.each do |reg|
            # Find the clock for this register from processes
            clock = find_clock_for_reg(module_def, reg.name)
            if clock
              lines << "    reg #{sanitize(reg.name)}: #{type_decl(reg.width)}, #{sanitize(clock)}"
            else
              # Default to a wire if no clock found (shouldn't happen for proper regs)
              lines << "    wire #{sanitize(reg.name)}: #{type_decl(reg.width)}"
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

          lines << "" unless module_def.nets.empty? && module_def.regs.empty? && module_def.memories.empty?

          # Continuous assignments
          module_def.assigns.each do |assign|
            lines << "    #{sanitize(assign.target)} <= #{expr(assign.expr)}"
          end

          # Sequential processes (register updates)
          module_def.processes.each do |process|
            if process.clocked
              process.statements.each do |stmt|
                lines.concat(statement(stmt, indent: 4))
              end
            else
              # Combinational process - convert to assignments
              process.statements.each do |stmt|
                lines.concat(statement(stmt, indent: 4))
              end
            end
          end

          # Memory write ports
          module_def.write_ports.each do |wp|
            lines << "    #{sanitize(wp.memory)}.write.clk <= #{sanitize(wp.clock)}"
            lines << "    #{sanitize(wp.memory)}.write.en <= #{expr(wp.enable)}"
            lines << "    #{sanitize(wp.memory)}.write.addr <= #{expr(wp.addr)}"
            lines << "    #{sanitize(wp.memory)}.write.data <= #{expr(wp.data)}"
          end

          # Module instances
          module_def.instances.each do |instance|
            lines << ""
            lines << "    inst #{sanitize(instance.name)} of #{sanitize(instance.module_name)}"
            instance.connections.each do |conn|
              signal_str = conn.signal.is_a?(String) ? sanitize(conn.signal) : expr(conn.signal)
              lines << "    #{sanitize(instance.name)}.#{sanitize(conn.port_name)} <= #{signal_str}"
            end
          end

          lines.join("\n")
        end

        def find_clock_for_reg(module_def, reg_name)
          module_def.processes.each do |process|
            return process.clock if process.clocked && process.clock
          end
          nil
        end

        def type_decl(width)
          "UInt<#{width}>"
        end

        def statement(stmt, indent:)
          pad = " " * indent
          case stmt
          when IR::SeqAssign
            ["#{pad}#{sanitize(stmt.target)} <= #{expr(stmt.expr)}"]
          when IR::MemoryWrite
            ["#{pad}#{sanitize(stmt.memory)}[#{expr(stmt.addr)}] <= #{expr(stmt.data)}"]
          when IR::If
            lines = []
            lines << "#{pad}when #{expr(stmt.condition)}:"
            stmt.then_statements.each { |s| lines.concat(statement(s, indent: indent + 2)) }
            unless stmt.else_statements.empty?
              lines << "#{pad}else:"
              stmt.else_statements.each { |s| lines.concat(statement(s, indent: indent + 2)) }
            end
            lines
          else
            []
          end
        end

        def expr(expr_node)
          case expr_node
          when IR::Signal
            sanitize(expr_node.name)
          when IR::Literal
            literal(expr_node.value, expr_node.width)
          when IR::UnaryOp
            unary_expr(expr_node)
          when IR::BinaryOp
            binary_expr(expr_node)
          when IR::Mux
            "mux(#{expr(expr_node.condition)}, #{expr(expr_node.when_true)}, #{expr(expr_node.when_false)})"
          when IR::Concat
            "cat(#{expr_node.parts.map { |p| expr(p) }.join(', ')})"
          when IR::Slice
            slice_expr(expr_node)
          when IR::Resize
            resize_expr(expr_node)
          when IR::Case
            case_expr(expr_node)
          when IR::MemoryRead
            "#{sanitize(expr_node.memory)}[#{expr(expr_node.addr)}]"
          else
            raise ArgumentError, "Unsupported FIRRTL expression: #{expr_node.inspect}"
          end
        end

        def unary_expr(node)
          case node.op
          when :~
            "not(#{expr(node.operand)})"
          when :!
            "not(#{expr(node.operand)})"
          else
            raise ArgumentError, "Unsupported unary op: #{node.op}"
          end
        end

        def binary_expr(node)
          left = expr(node.left)
          right = expr(node.right)

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

        def slice_expr(node)
          base = expr(node.base)
          high = [node.range.begin, node.range.end].max
          low = [node.range.begin, node.range.end].min

          "bits(#{base}, #{high}, #{low})"
        end

        def resize_expr(node)
          inner = expr(node.expr)
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

        def case_expr(node)
          # Convert case to nested mux
          selector = expr(node.selector)
          default_expr = node.default ? expr(node.default) : literal(0, node.width)

          result = default_expr
          node.cases.reverse_each do |values, branch|
            values.each do |v|
              cond = "eq(#{selector}, #{literal(v, node.selector.width)})"
              result = "mux(#{cond}, #{expr(branch)}, #{result})"
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
