# FIRRTL code generator for CIRCT toolchain
# Generates FIRRTL 5.1.0 format that can be compiled by firtool to Verilog

require_relative "../verilog/ir"

module RHDL
  module Codegen
    module CIRCT
      module FIRRTL
        FIRRTL_KEYWORDS = %w[
          circuit module input output wire reg node when else skip stop printf
          mux validif add sub mul div rem lt leq gt geq eq neq pad asUInt asSInt
          asClock asFixedPoint asInterval shl shr dshl dshr cvt neg not and or xor
          andr orr xorr cat bits head tail mux validif connect
        ].freeze

        module_function

        # Generate a complete FIRRTL circuit with a single module
        def generate(module_def)
          lines = []
          lines << "FIRRTL version 5.1.0"
          lines << "circuit #{sanitize(module_def.name)}:"
          lines << generate_module_body(module_def, is_public: true)
          lines.join("\n")
        end

        # Generate a complete FIRRTL circuit with multiple modules (hierarchical)
        # @param module_defs [Array<IR::ModuleDef>] Array of module definitions, top module last
        # @param top_name [String] Name of the circuit (usually the top module name)
        def generate_hierarchy(module_defs, top_name:)
          lines = []
          lines << "FIRRTL version 5.1.0"
          lines << "circuit #{sanitize(top_name)}:"

          # Build a map of module name -> module definition for looking up submodule ports
          module_map = {}
          module_defs.each do |mod_def|
            module_map[sanitize(mod_def.name)] = mod_def
          end

          module_defs.each_with_index do |mod_def, idx|
            is_top = (idx == module_defs.length - 1)
            lines << generate_module_body(mod_def, is_public: is_top, module_map: module_map)
            lines << "" unless is_top # Add blank line between modules
          end

          lines.join("\n")
        end

        # Generate just the module body (without circuit header)
        # @param module_def [IR::ModuleDef] The module definition
        # @param is_public [Boolean] Whether this is the public top-level module
        # @param module_map [Hash{String => IR::ModuleDef}] Map of module names to definitions (for hierarchical)
        # @return [String] The module body FIRRTL code
        def generate_module_body(module_def, is_public: false, module_map: {})
          lines = []
          module_keyword = is_public ? "public module" : "module"
          lines << "  #{module_keyword} #{sanitize(module_def.name)}:"

          # Build set of output port names
          output_ports = module_def.ports.select { |p| p.direction == :out }.map(&:name).to_set
          output_widths = module_def.ports.select { |p| p.direction == :out }.map { |p| [p.name, p.width] }.to_h

          # Find clock for sequential processes or from write ports
          clock = find_clock_for_reg(module_def, nil) || find_clock_from_write_ports(module_def)

          # Collect targets of sequential assignments that are outputs (need internal registers)
          seq_targets = collect_seq_targets(module_def)
          seq_output_targets = seq_targets.select { |t| output_ports.include?(t) }

          # Collect memory reads to set up read ports
          memory_reads = collect_memory_reads(module_def)

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

          # Pre-compute read counts per memory for consistent port naming
          # Normalize memory names to strings for consistent lookup
          reads_per_mem = Hash.new(0)
          memory_reads.each { |mr| reads_per_mem[mr.memory.to_s] += 1 }

          # Memory arrays - determine read/write ports needed
          module_def.memories.each do |mem|
            mem_key = mem.name.to_s
            # Count how many read ports this memory needs
            read_count = reads_per_mem[mem_key]
            read_count = 1 if read_count == 0 # At least one reader if memory exists
            # For dual-port RAM with 2 reads and 2 writes, we need multiple ports
            write_count = module_def.write_ports.count { |wp| wp.memory.to_s == mem_key }

            lines << "    mem #{sanitize(mem.name)}:"
            lines << "      data-type => #{type_decl(mem.width)}"
            lines << "      depth => #{mem.depth}"
            lines << "      read-latency => 0"
            lines << "      write-latency => 1"

            # Generate reader declarations - use numbered ports if multiple readers
            if read_count == 1
              lines << "      reader => read"
            else
              read_count.times { |i| lines << "      reader => read#{i}" }
            end

            # Generate writer declarations only if there are write ports
            if write_count == 1
              lines << "      writer => write"
            elsif write_count > 1
              write_count.times { |i| lines << "      writer => write#{i}" }
            end
            # No writer declaration for read-only memories (write_count == 0)
          end

          # For memories without a clock input, generate a fake clock
          needs_fake_clock = !module_def.memories.empty? && !clock
          if needs_fake_clock
            lines << "    wire _fake_clk: Clock"
            lines << "    connect _fake_clk, asClock(UInt<1>(0))"
          end

          has_decls = !module_def.nets.empty? || !module_def.regs.empty? ||
                      !module_def.memories.empty? || !seq_output_targets.empty? || needs_fake_clock
          lines << "" if has_decls

          # Memory read port connections - must come before assigns that use them
          # Track which memory read we're on for multi-port memories
          mem_read_index = Hash.new(0)
          memory_reads.each do |mr|
            mem_key = mr.memory.to_s
            mem_name = sanitize(mr.memory)
            idx = mem_read_index[mem_key]
            # Use numbered ports only if multiple readers
            read_port = reads_per_mem[mem_key] > 1 ? "read#{idx}" : "read"

            # Use real clock if available, otherwise fake clock
            clk_signal = clock ? sanitize(clock) : "_fake_clk"
            lines << "    connect #{mem_name}.#{read_port}.clk, #{clk_signal}"
            lines << "    connect #{mem_name}.#{read_port}.en, UInt<1>(1)"
            lines << "    connect #{mem_name}.#{read_port}.addr, #{expr(mr.addr)}"
            mem_read_index[mem_key] += 1
          end

          # Continuous assignments - use memory read port data
          mem_read_index = Hash.new(0)
          module_def.assigns.each do |assign|
            lines << "    connect #{sanitize(assign.target)}, #{expr_with_mem_reads(assign.expr, memory_reads, mem_read_index)}"
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
          write_port_index = Hash.new(0)
          module_def.write_ports.each do |wp|
            mem_name = sanitize(wp.memory)
            idx = write_port_index[wp.memory]
            write_count = module_def.write_ports.count { |w| w.memory == wp.memory }
            port_suffix = write_count > 1 ? idx.to_s : ""
            write_port = "write#{port_suffix}"

            # Find memory width for mask
            mem = module_def.memories.find { |m| m.name == wp.memory }
            mem_width = mem&.width || 8

            lines << "    connect #{mem_name}.#{write_port}.clk, #{sanitize(wp.clock)}"
            lines << "    connect #{mem_name}.#{write_port}.en, #{expr(wp.enable)}"
            lines << "    connect #{mem_name}.#{write_port}.addr, #{expr(wp.addr)}"
            lines << "    connect #{mem_name}.#{write_port}.mask, UInt<#{mem_width}>(#{(1 << mem_width) - 1})"
            lines << "    connect #{mem_name}.#{write_port}.data, #{expr(wp.data)}"
            write_port_index[wp.memory] += 1
          end

          # Module instances
          module_def.instances.each do |instance|
            lines << ""
            lines << "    inst #{sanitize(instance.name)} of #{sanitize(instance.module_name)}"

            # Get connected port names
            connected_ports = instance.connections.map { |c| c.port_name.to_sym }.to_set

            # Generate explicit connections
            instance.connections.each do |conn|
              signal_str = conn.signal.is_a?(String) ? sanitize(conn.signal) : expr(conn.signal)
              inst_port = "#{sanitize(instance.name)}.#{sanitize(conn.port_name)}"
              # FIRRTL flow: input ports are sinks (connect TO them), output ports are sources (connect FROM them)
              if conn.direction == :out
                lines << "    connect #{signal_str}, #{inst_port}"
              else
                lines << "    connect #{inst_port}, #{signal_str}"
              end
            end

            # Add default connections for unconnected input ports (if module_map is available)
            submod_def = module_map[sanitize(instance.module_name)]
            if submod_def
              submod_def.ports.each do |port|
                next unless port.direction == :in  # Only need to connect inputs (sinks)
                next if connected_ports.include?(port.name.to_sym)

                inst_port = "#{sanitize(instance.name)}.#{sanitize(port.name)}"
                # Use appropriate default: Clock ports get a clock, others get 0
                if clock_port?(port.name)
                  # Find the clock port in the current module if available
                  clock_port = module_def.ports.find { |p| clock_port?(p.name) && p.direction == :in }
                  if clock_port
                    lines << "    connect #{inst_port}, #{sanitize(clock_port.name)}"
                  else
                    lines << "    connect #{inst_port}, asClock(UInt<1>(0))"
                  end
                else
                  lines << "    connect #{inst_port}, #{literal(0, port.width)}"
                end
              end
            end
          end

          lines.join("\n")
        end

        private_class_method :generate_module_body

        def find_clock_from_write_ports(module_def)
          module_def.write_ports.first&.clock
        end

        def collect_memory_reads(module_def)
          reads = []
          module_def.assigns.each do |assign|
            collect_memory_reads_from_expr(assign.expr, reads)
          end
          module_def.processes.each do |process|
            process.statements.each do |stmt|
              collect_memory_reads_from_stmt(stmt, reads)
            end
          end
          reads
        end

        def collect_memory_reads_from_expr(expr_node, reads)
          case expr_node
          when IR::MemoryRead
            reads << expr_node
          when IR::UnaryOp
            collect_memory_reads_from_expr(expr_node.operand, reads)
          when IR::BinaryOp
            collect_memory_reads_from_expr(expr_node.left, reads)
            collect_memory_reads_from_expr(expr_node.right, reads)
          when IR::Mux
            collect_memory_reads_from_expr(expr_node.condition, reads)
            collect_memory_reads_from_expr(expr_node.when_true, reads)
            collect_memory_reads_from_expr(expr_node.when_false, reads)
          when IR::Concat
            expr_node.parts.each { |p| collect_memory_reads_from_expr(p, reads) }
          when IR::Slice
            collect_memory_reads_from_expr(expr_node.base, reads)
          when IR::Resize
            collect_memory_reads_from_expr(expr_node.expr, reads)
          when IR::Case
            collect_memory_reads_from_expr(expr_node.selector, reads)
            expr_node.cases.each { |_v, branch| collect_memory_reads_from_expr(branch, reads) }
            collect_memory_reads_from_expr(expr_node.default, reads) if expr_node.default
          end
        end

        def collect_memory_reads_from_stmt(stmt, reads)
          case stmt
          when IR::SeqAssign
            collect_memory_reads_from_expr(stmt.expr, reads)
          when IR::If
            collect_memory_reads_from_expr(stmt.condition, reads)
            stmt.then_statements.each { |s| collect_memory_reads_from_stmt(s, reads) }
            stmt.else_statements.each { |s| collect_memory_reads_from_stmt(s, reads) }
          end
        end

        def expr_with_mem_reads(expr_node, memory_reads, mem_read_index, output_regs: Set.new)
          case expr_node
          when IR::MemoryRead
            # Find which read port this corresponds to
            mem_key = expr_node.memory.to_s
            mem_name = sanitize(expr_node.memory)
            read_count = memory_reads.count { |mr| mr.memory.to_s == mem_key }
            idx = mem_read_index[mem_key]
            # Use numbered ports only if multiple readers
            read_port = read_count > 1 ? "read#{idx}" : "read"
            mem_read_index[mem_key] += 1
            "#{mem_name}.#{read_port}.data"
          when IR::Signal
            name = output_regs.include?(expr_node.name) ? "#{expr_node.name}_reg" : expr_node.name
            sanitize(name)
          when IR::Literal
            literal(expr_node.value, expr_node.width)
          when IR::UnaryOp
            case expr_node.op
            when :~, :!
              "not(#{expr_with_mem_reads(expr_node.operand, memory_reads, mem_read_index, output_regs: output_regs)})"
            else
              raise ArgumentError, "Unsupported unary op: #{expr_node.op}"
            end
          when IR::BinaryOp
            left = expr_with_mem_reads(expr_node.left, memory_reads, mem_read_index, output_regs: output_regs)
            right = expr_with_mem_reads(expr_node.right, memory_reads, mem_read_index, output_regs: output_regs)
            binary_op_str(expr_node.op, left, right)
          when IR::Mux
            cond = expr_with_mem_reads(expr_node.condition, memory_reads, mem_read_index, output_regs: output_regs)
            when_true = expr_with_mem_reads(expr_node.when_true, memory_reads, mem_read_index, output_regs: output_regs)
            when_false = expr_with_mem_reads(expr_node.when_false, memory_reads, mem_read_index, output_regs: output_regs)
            "mux(#{cond}, #{when_true}, #{when_false})"
          when IR::Concat
            parts = expr_node.parts.map { |p| expr_with_mem_reads(p, memory_reads, mem_read_index, output_regs: output_regs) }
            "cat(#{parts.join(', ')})"
          when IR::Slice
            base = expr_with_mem_reads(expr_node.base, memory_reads, mem_read_index, output_regs: output_regs)
            high = [expr_node.range.begin, expr_node.range.end].max
            low = [expr_node.range.begin, expr_node.range.end].min
            "bits(#{base}, #{high}, #{low})"
          when IR::Resize
            inner = expr_with_mem_reads(expr_node.expr, memory_reads, mem_read_index, output_regs: output_regs)
            target_width = expr_node.width
            source_width = expr_node.expr.width
            if target_width == source_width
              inner
            elsif target_width > source_width
              "pad(#{inner}, #{target_width})"
            else
              "bits(#{inner}, #{target_width - 1}, 0)"
            end
          when IR::Case
            selector = expr_with_mem_reads(expr_node.selector, memory_reads, mem_read_index, output_regs: output_regs)
            default_expr = expr_node.default ? expr_with_mem_reads(expr_node.default, memory_reads, mem_read_index, output_regs: output_regs) : literal(0, expr_node.width)
            result = default_expr
            expr_node.cases.reverse_each do |values, branch|
              values.each do |v|
                cond = "eq(#{selector}, #{literal(v, expr_node.selector.width)})"
                result = "mux(#{cond}, #{expr_with_mem_reads(branch, memory_reads, mem_read_index, output_regs: output_regs)}, #{result})"
              end
            end
            result
          else
            raise ArgumentError, "Unsupported FIRRTL expression: #{expr_node.inspect}"
          end
        end

        def binary_op_str(op, left, right)
          case op
          when :& then "and(#{left}, #{right})"
          when :| then "or(#{left}, #{right})"
          when :^ then "xor(#{left}, #{right})"
          when :+ then "add(#{left}, #{right})"
          when :- then "sub(#{left}, #{right})"
          when :* then "mul(#{left}, #{right})"
          when :/ then "div(#{left}, #{right})"
          when :% then "rem(#{left}, #{right})"
          when :<< then "shl(#{left}, #{right})"
          when :>> then "shr(#{left}, #{right})"
          when :== then "eq(#{left}, #{right})"
          when :!= then "neq(#{left}, #{right})"
          when :< then "lt(#{left}, #{right})"
          when :> then "gt(#{left}, #{right})"
          when :<= then "leq(#{left}, #{right})"
          when :>= then "geq(#{left}, #{right})"
          else raise ArgumentError, "Unsupported binary op: #{op}"
          end
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
