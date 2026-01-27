# frozen_string_literal: true

# IR-level bytecode interpreter with Rust backend
#
# This simulator operates at the IR level, interpreting Behavior IR using
# a stack-based bytecode interpreter. It's faster than gate-level netlist
# simulation because it operates on whole words instead of individual bits.

require 'json'

module RHDL
  module Codegen
    module IR
      # Determine library path based on platform
      IR_INTERPRETER_EXT_DIR = File.expand_path('ir_interpreter/lib', __dir__)
      IR_INTERPRETER_LIB_NAME = case RbConfig::CONFIG['host_os']
      when /darwin/ then 'ir_interpreter.bundle'
      when /mswin|mingw/ then 'ir_interpreter.dll'
      else 'ir_interpreter.so'
      end
      IR_INTERPRETER_LIB_PATH = File.join(IR_INTERPRETER_EXT_DIR, IR_INTERPRETER_LIB_NAME)

      # Try to load interpreter extension
      IR_INTERPRETER_AVAILABLE = begin
        if File.exist?(IR_INTERPRETER_LIB_PATH)
          $LOAD_PATH.unshift(IR_INTERPRETER_EXT_DIR) unless $LOAD_PATH.include?(IR_INTERPRETER_EXT_DIR)
          require 'ir_interpreter'
          true
        else
          false
        end
      rescue LoadError => e
        warn "IrInterpreter extension not available: #{e.message}" if ENV['RHDL_DEBUG']
        false
      end

      # Backwards compatibility alias
      RTL_INTERPRETER_AVAILABLE = IR_INTERPRETER_AVAILABLE

      # Wrapper class that uses Rust interpreter if available
      class IrInterpreterWrapper
        attr_reader :ir_json, :sub_cycles

        # @param ir_json [String] JSON representation of the IR
        # @param allow_fallback [Boolean] Allow fallback to Ruby implementation
        # @param sub_cycles [Integer] Number of sub-cycles per CPU cycle (default: 14)
        #   - 14: Full timing accuracy
        #   - 7: ~2x faster, good accuracy
        #   - 2: ~7x faster, minimal accuracy
        def initialize(ir_json, allow_fallback: true, sub_cycles: 14)
          @ir_json = ir_json
          @sub_cycles = sub_cycles.clamp(1, 14)

          if IR_INTERPRETER_AVAILABLE
            @sim = IrInterpreter.new(ir_json, @sub_cycles)
            @backend = :interpret
          elsif allow_fallback
            @sim = RubyIrSim.new(ir_json)
            @backend = :ruby
          else
            raise LoadError, "IR interpreter extension not found at: #{IR_INTERPRETER_LIB_PATH}\nRun 'rake native:build' to build it."
          end
        end

        def simulator_type
          :"hdl_#{@backend}"
        end

        def native?
          IR_INTERPRETER_AVAILABLE && @backend == :interpret
        end

        def poke(name, value)
          @sim.poke(name, value)
        end

        def peek(name)
          @sim.peek(name)
        end

        def evaluate
          @sim.evaluate
        end

        def tick
          @sim.tick
        end

        def reset
          @sim.reset
        end

        def signal_count
          @sim.signal_count
        end

        def reg_count
          @sim.reg_count
        end

        def input_names
          @sim.input_names
        end

        def output_names
          @sim.output_names
        end

        def stats
          @sim.stats
        end

        # Batched execution methods (only available with native backend)
        def load_rom(data)
          @sim.load_rom(data) if @sim.respond_to?(:load_rom)
        end

        def load_ram(data, offset)
          @sim.load_ram(data, offset) if @sim.respond_to?(:load_ram)
        end

        def run_cpu_cycles(n, key_data, key_ready)
          if @sim.respond_to?(:run_cpu_cycles)
            @sim.run_cpu_cycles(n, key_data, key_ready)
          else
            # Fallback: not supported in Ruby simulator
            { cycles_run: 0, text_dirty: false, key_cleared: false }
          end
        end

        def read_ram(start, length)
          if @sim.respond_to?(:read_ram)
            @sim.read_ram(start, length)
          else
            []
          end
        end

        def write_ram(start, data)
          @sim.write_ram(start, data) if @sim.respond_to?(:write_ram)
        end

        def respond_to_missing?(method_name, include_private = false)
          @sim.respond_to?(method_name) || super
        end

        def method_missing(method_name, *args, &block)
          if @sim.respond_to?(method_name)
            @sim.send(method_name, *args, &block)
          else
            super
          end
        end
      end

      # Backwards compatibility alias
      RtlInterpreterWrapper = IrInterpreterWrapper

      # Ruby fallback simulator for when native extension is not available
      class RubyIrSim
        def initialize(json)
          @ir = JSON.parse(json, symbolize_names: true, max_nesting: false)
          @signals = {}
          @widths = {}
          @inputs = []
          @outputs = []

          # Initialize ports
          @ir[:ports]&.each do |port|
            @signals[port[:name]] = 0
            @widths[port[:name]] = port[:width]
            if port[:direction] == 'in'
              @inputs << port[:name]
            else
              @outputs << port[:name]
            end
          end

          # Initialize wires
          @ir[:nets]&.each do |net|
            @signals[net[:name]] = 0
            @widths[net[:name]] = net[:width]
          end

          # Initialize registers (with reset values if present)
          @reset_values = {}
          @ir[:regs]&.each do |reg|
            reset_val = reg[:reset_value] || 0
            @signals[reg[:name]] = reset_val
            @widths[reg[:name]] = reg[:width]
            @reset_values[reg[:name]] = reset_val
          end

          @assigns = @ir[:assigns] || []
          @processes = @ir[:processes] || []
        end

        def native?
          false
        end

        def mask(width)
          width >= 64 ? 0xFFFFFFFFFFFFFFFF : (1 << width) - 1
        end

        def eval_expr(expr)
          case expr[:type]
          when 'signal'
            (@signals[expr[:name]] || 0) & mask(expr[:width])
          when 'literal'
            expr[:value] & mask(expr[:width])
          when 'unary_op'
            val = eval_expr(expr[:operand])
            m = mask(expr[:width])
            case expr[:op]
            when '~', 'not'
              (~val) & m
            when '&', 'reduce_and'
              op_width = expr[:operand][:width]
              (val & mask(op_width)) == mask(op_width) ? 1 : 0
            when '|', 'reduce_or'
              val != 0 ? 1 : 0
            when '^', 'reduce_xor'
              val.to_s(2).count('1') & 1
            else
              val
            end
          when 'binary_op'
            l = eval_expr(expr[:left])
            r = eval_expr(expr[:right])
            m = mask(expr[:width])
            case expr[:op]
            when '&' then l & r
            when '|' then l | r
            when '^' then l ^ r
            when '+' then (l + r) & m
            when '-' then (l - r) & m
            when '*' then (l * r) & m
            when '/' then r != 0 ? l / r : 0
            when '%' then r != 0 ? l % r : 0
            when '<<' then (l << [r, 63].min) & m
            when '>>' then l >> [r, 63].min
            when '==' then l == r ? 1 : 0
            when '!=' then l != r ? 1 : 0
            when '<' then l < r ? 1 : 0
            when '>' then l > r ? 1 : 0
            when '<=', 'le' then l <= r ? 1 : 0
            when '>=' then l >= r ? 1 : 0
            else 0
            end
          when 'mux'
            cond = eval_expr(expr[:condition])
            m = mask(expr[:width])
            if cond != 0
              eval_expr(expr[:when_true]) & m
            else
              eval_expr(expr[:when_false]) & m
            end
          when 'slice'
            val = eval_expr(expr[:base])
            (val >> expr[:low]) & mask(expr[:width])
          when 'concat'
            result = 0
            shift = 0
            expr[:parts].each do |part|
              part_val = eval_expr(part)
              part_width = part[:width]
              result |= (part_val & mask(part_width)) << shift
              shift += part_width
            end
            result & mask(expr[:width])
          when 'resize'
            eval_expr(expr[:expr]) & mask(expr[:width])
          else
            0
          end
        end

        def poke(name, value)
          raise "Unknown input: #{name}" unless @inputs.include?(name)
          width = @widths[name] || 64
          @signals[name] = value & mask(width)
        end

        def peek(name)
          @signals[name] || 0
        end

        def evaluate
          10.times do
            changed = false
            @assigns.each do |assign|
              new_val = eval_expr(assign[:expr])
              width = @widths[assign[:target]] || 64
              masked = new_val & mask(width)
              if @signals[assign[:target]] != masked
                @signals[assign[:target]] = masked
                changed = true
              end
            end
            break unless changed
          end
        end

        def tick
          evaluate

          # Sample register inputs
          next_regs = {}
          @processes.each do |process|
            next unless process[:clocked]
            process[:statements]&.each do |stmt|
              new_val = eval_expr(stmt[:expr])
              width = @widths[stmt[:target]] || 64
              next_regs[stmt[:target]] = new_val & mask(width)
            end
          end

          # Update registers
          next_regs.each do |name, val|
            @signals[name] = val
          end

          evaluate
        end

        def reset
          @signals.transform_values! { 0 }
          # Apply register reset values
          @reset_values.each do |name, val|
            @signals[name] = val
          end
        end

        def signal_count
          @signals.length
        end

        def reg_count
          @processes.sum { |p| p[:statements]&.length || 0 }
        end

        def input_names
          @inputs
        end

        def output_names
          @outputs
        end

        def stats
          {
            signal_count: signal_count,
            reg_count: reg_count,
            input_count: @inputs.length,
            output_count: @outputs.length,
            assign_count: @assigns.length,
            process_count: @processes.length
          }
        end
      end

      # Convert Behavior IR to JSON format for the simulator
      module IRToJson
        module_function

        def convert(ir)
          {
            name: ir.name,
            ports: ir.ports.map { |p| port_to_hash(p) },
            nets: ir.nets.map { |n| net_to_hash(n) },
            regs: ir.regs.map { |r| reg_to_hash(r) },
            assigns: ir.assigns.map { |a| assign_to_hash(a) },
            processes: ir.processes.map { |p| process_to_hash(p) },
            memories: (ir.memories || []).map { |m| memory_to_hash(m) }
          }.to_json(max_nesting: false)
        end

        def port_to_hash(port)
          {
            name: port.name.to_s,
            direction: port.direction.to_s,
            width: port.width
          }
        end

        def net_to_hash(net)
          {
            name: net.name.to_s,
            width: net.width
          }
        end

        def reg_to_hash(reg)
          hash = {
            name: reg.name.to_s,
            width: reg.width
          }
          hash[:reset_value] = reg.reset_value if reg.reset_value
          hash
        end

        def assign_to_hash(assign)
          {
            target: assign.target.to_s,
            expr: expr_to_hash(assign.expr)
          }
        end

        def process_to_hash(process)
          {
            name: process.name.to_s,
            clock: process.clock&.to_s,
            clocked: process.clocked,
            statements: flatten_statements(process.statements)
          }
        end

        # Flatten If statements into conditional assignments
        def flatten_statements(stmts)
          return [] unless stmts
          result = []
          stmts.each do |stmt|
            case stmt
            when IR::SeqAssign
              result << seq_assign_to_hash(stmt)
            when IR::If
              # Convert If to conditional assignments using mux
              flatten_if(stmt, result)
            end
          end
          result
        end

        def flatten_if(if_stmt, result)
          cond = expr_to_hash(if_stmt.condition)

          # Collect assignments from then branch
          then_assigns = {}
          if_stmt.then_statements&.each do |s|
            case s
            when IR::SeqAssign
              then_assigns[s.target.to_s] = expr_to_hash(s.expr)
            when IR::If
              # Nested if - flatten recursively
              flatten_if(s, result)
            end
          end

          # Collect assignments from else branch
          else_assigns = {}
          if_stmt.else_statements&.each do |s|
            case s
            when IR::SeqAssign
              else_assigns[s.target.to_s] = expr_to_hash(s.expr)
            when IR::If
              flatten_if(s, result)
            end
          end

          # Create mux for each assigned target
          all_targets = (then_assigns.keys + else_assigns.keys).uniq
          all_targets.each do |target|
            then_expr = then_assigns[target]
            else_expr = else_assigns[target]
            width = (then_expr || else_expr)&.dig(:width) || 8

            if then_expr && else_expr
              # Both branches assign - create mux
              result << {
                target: target,
                expr: { type: 'mux', condition: cond, when_true: then_expr, when_false: else_expr, width: width }
              }
            elsif then_expr
              # Only then branch assigns - mux with signal (keep current value if false)
              result << {
                target: target,
                expr: { type: 'mux', condition: cond, when_true: then_expr, when_false: { type: 'signal', name: target, width: width }, width: width }
              }
            elsif else_expr
              # Only else branch assigns - invert condition
              inv_cond = { type: 'unary_op', op: '~', operand: cond, width: 1 }
              result << {
                target: target,
                expr: { type: 'mux', condition: inv_cond, when_true: else_expr, when_false: { type: 'signal', name: target, width: width }, width: width }
              }
            end
          end
        end

        def seq_assign_to_hash(stmt)
          {
            target: stmt.target.to_s,
            expr: expr_to_hash(stmt.expr)
          }
        end

        def memory_to_hash(mem)
          hash = {
            name: mem.name.to_s,
            depth: mem.depth,
            width: mem.width
          }
          hash[:initial_data] = mem.initial_data if mem.initial_data
          hash
        end

        def expr_to_hash(expr)
          case expr
          when IR::Signal
            { type: 'signal', name: expr.name.to_s, width: expr.width }
          when IR::Literal
            { type: 'literal', value: expr.value, width: expr.width }
          when IR::UnaryOp
            { type: 'unary_op', op: expr.op.to_s, operand: expr_to_hash(expr.operand), width: expr.width }
          when IR::BinaryOp
            { type: 'binary_op', op: expr.op.to_s, left: expr_to_hash(expr.left), right: expr_to_hash(expr.right), width: expr.width }
          when IR::Mux
            { type: 'mux', condition: expr_to_hash(expr.condition), when_true: expr_to_hash(expr.when_true), when_false: expr_to_hash(expr.when_false), width: expr.width }
          when IR::Slice
            # Handle various range types
            low = 0
            high = expr.width - 1

            if expr.range.is_a?(Range)
              range_begin = expr.range.begin
              range_end = expr.range.end
              # Only use if both are integers
              if range_begin.is_a?(Integer) && range_end.is_a?(Integer)
                low = [range_begin, range_end].min
                high = [range_begin, range_end].max
              end
            elsif expr.range.is_a?(Integer)
              low = expr.range
              high = expr.range
            end
            # Dynamic slices just use width-based extraction
            { type: 'slice', base: expr_to_hash(expr.base), low: low, high: high, width: expr.width }
          when IR::Concat
            { type: 'concat', parts: expr.parts.map { |p| expr_to_hash(p) }, width: expr.width }
          when IR::Resize
            { type: 'resize', expr: expr_to_hash(expr.expr), width: expr.width }
          when IR::Case
            # Convert case to nested muxes
            if expr.cases.empty?
              expr_to_hash(expr.default)
            else
              # Build mux chain
              result = expr.default ? expr_to_hash(expr.default) : { type: 'literal', value: 0, width: expr.width }
              expr.cases.each do |values, case_expr|
                values.each do |v|
                  cond = { type: 'binary_op', op: '==', left: expr_to_hash(expr.selector), right: { type: 'literal', value: v, width: expr.selector.width }, width: 1 }
                  result = { type: 'mux', condition: cond, when_true: expr_to_hash(case_expr), when_false: result, width: expr.width }
                end
              end
              result
            end
          when IR::MemoryRead
            { type: 'mem_read', memory: expr.memory.to_s, addr: expr_to_hash(expr.addr), width: expr.width }
          else
            { type: 'literal', value: 0, width: 1 }
          end
        end
      end
    end
  end
end
