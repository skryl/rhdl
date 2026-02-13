# frozen_string_literal: true

require 'optparse'
require 'time'

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/codegen'
require_relative '../../../lib/rhdl/codegen/ir/sim/ir_simulator'
require_relative '../hdl/ir_harness'
require_relative '../hdl/pipeline/ir_harness'

module RHDL
  module Examples
    module RISCV
      # Continuous verbose tracer for xv6 boot progress on native IR backends.
      class Xv6BootTracer
        DEFAULT_KERNEL = File.expand_path('../software/bin/kernel.bin', __dir__)
        DEFAULT_FS_IMG = File.expand_path('../software/bin/fs.img', __dir__)
        DEFAULT_SYMBOLS = File.expand_path('../software/bin/kernel.nm', __dir__)

        STAGE_TABLE = [
          [0x8000_0000..0x8000_0640, 'early_boot'],
          [0x8000_0644..0x8000_1108, 'mem_ops_or_allocator'],
          [0x8000_17B0..0x8000_1870, 'kvm_map_setup'],
          [0x8000_7F40..0x8000_80E0, 'virtio_probe_config'],
          [0x8000_80E0..0x8000_8400, 'virtio_runtime_path']
        ].freeze

        def initialize(options)
          @options = options
          @cpu = build_harness
          @sim = @cpu.sim
          @symbol_table = load_symbol_table(@options[:symbols])
          @last_uart_len = 0
          @last_stage = nil
          @last_mmio_key = nil
          @heartbeat_period = [@options[:heartbeat].to_i, 1].max
          @cycle_count = 0
          @start_time = Time.now
          @last_trap_key = nil
          @last_user_pc_key = nil
        end

        def run
          ensure_native_riscv!
          kernel_bytes = File.binread(@options[:kernel]).bytes
          fs_bytes = File.binread(@options[:fs]).bytes

          phystop_patches = if @options[:fast_boot]
                             patch_phystop_for_fast_boot!(kernel_bytes)
                           else
                             0
                           end

          puts format(
            '[trace] core=%<core>s backend=%<backend>s fast_boot=%<fast>s phystop_patches=%<patch>d',
            core: @options[:core],
            backend: @options[:backend],
            fast: @options[:fast_boot],
            patch: phystop_patches
          )
          puts format('[trace] kernel=%<kernel>s', kernel: @options[:kernel])
          puts format('[trace] fs=%<fs>s', fs: @options[:fs])
          if @options[:symbols]
            if @symbol_table.empty?
              puts format('[trace] symbols=%<symbols>s (missing/empty)', symbols: @options[:symbols])
            else
              puts format('[trace] symbols=%<symbols>s entries=%<count>d',
                          symbols: @options[:symbols], count: @symbol_table.length)
            end
          end

          @cpu.reset!
          @sim.runner_load_rom(kernel_bytes.pack('C*'), 0x8000_0000)
          @sim.runner_riscv_load_disk(fs_bytes, 0)
          write_pc(0x8000_0000)
          puts '[trace] reset done; pc forced to 0x80000000'

          max_cycles = @options[:max_cycles].to_i
          chunk = [@options[:chunk].to_i, 1].max
          fine_chunk = [(@options[:fine_chunk] || chunk).to_i, 1].max
          fine_start = @options[:fine_start].to_i

          while @cycle_count < max_cycles
            active_chunk = @cycle_count >= fine_start ? fine_chunk : chunk
            step = [active_chunk, max_cycles - @cycle_count].min
            @cpu.run_cycles(step)
            @cycle_count += step

            emit_uart_delta
            emit_stage if @options[:stage]
            emit_mmio_sample if @options[:mmio]
            emit_trap_probe
            emit_user_pc_probe if @options[:user_probe]
            emit_allocator_probe if @options[:allocator_probe]
            emit_lock_probe if @options[:lock_probe]
            emit_heartbeat if (@cycle_count % @heartbeat_period).zero?

            break if stop_condition_met?
          end

          emit_heartbeat(force: true)
          puts format('[trace] done cycles=%<cycles>d reason=%<reason>s', cycles: @cycle_count, reason: stop_reason)
        end

        private

        def build_harness
          case @options[:core]
          when :single
            RHDL::Examples::RISCV::IRHarness.new(
              backend: @options[:backend],
              allow_fallback: false
            )
          when :pipeline
            RHDL::Examples::RISCV::Pipeline::IRHarness.new(
              'xv6_pipeline_trace',
              backend: @options[:backend],
              allow_fallback: false
            )
          else
            raise ArgumentError, "Unsupported core #{@options[:core]}"
          end
        end

        def ensure_native_riscv!
          unless @cpu.native? && @sim.runner_kind == :riscv
            raise "Native RISC-V runner not available for backend=#{@options[:backend]}"
          end
        end

        def patch_phystop_for_fast_boot!(bytes)
          patches = 0
          (0..(bytes.length - 4)).step(4) do |offset|
            word = bytes[offset, 4].pack('C*').unpack1('V')
            opcode = word & 0x7F
            next unless opcode == 0x37

            imm20 = (word >> 12) & 0xFFFFF
            next unless imm20 == 0x88000

            rd = (word >> 7) & 0x1F
            new_word = (0x80200 << 12) | (rd << 7) | 0x37
            bytes[offset, 4] = [new_word].pack('V').bytes
            patches += 1
          end
          patches
        end

        def emit_uart_delta
          bytes = @cpu.uart_tx_bytes
          return if bytes.length <= @last_uart_len

          delta = bytes[@last_uart_len..-1] || []
          @last_uart_len = bytes.length
          text = delta.pack('C*')
          print text
        end

        def emit_stage
          pc = read_pc
          stage = stage_for_pc(pc)
          return if stage == @last_stage

          @last_stage = stage
          inst = read_inst
          puts format(
            "\n[stage] cycles=%<cycles>d pc=0x%<pc>08x inst=0x%<inst>08x stage=%<stage>s%<symbol>s",
            cycles: @cycle_count,
            pc: pc,
            inst: inst,
            stage: stage,
            symbol: symbol_suffix_for_pc(pc)
          )
        end

        def emit_mmio_sample
          addr = peek_optional('data_addr')
          return if addr.nil?

          addr &= 0xFFFF_FFFF
          return unless mmio_addr?(addr)

          data_re = (peek_optional('data_re') || 0).to_i & 0x1
          data_we = (peek_optional('data_we') || 0).to_i & 0x1
          return if data_re == 0 && data_we == 0

          funct3 = (peek_optional('data_funct3') || 0).to_i & 0x7
          write_data = (peek_optional('data_wdata') || 0).to_i & 0xFFFF_FFFF
          read_data = (peek_optional('data_rdata') || 0).to_i & 0xFFFF_FFFF
          op = data_we == 1 ? 'W' : 'R'
          value = data_we == 1 ? write_data : read_data
          key = [op, addr, funct3, value]
          return if key == @last_mmio_key

          @last_mmio_key = key
          puts format(
            '[mmio] cycles=%<cycles>d op=%<op>s region=%<region>s addr=0x%<addr>08x funct3=%<f3>d val=0x%<val>08x',
            cycles: @cycle_count,
            op: op,
            region: mmio_region(addr),
            addr: addr,
            f3: funct3,
            val: value
          )
        end

        def emit_heartbeat(force: false)
          return unless force || (@cycle_count % @heartbeat_period).zero?

          elapsed = Time.now - @start_time
          cps = (@cycle_count / [elapsed, 1e-9].max).round
          pc = read_pc
          inst = read_inst
          puts format(
            '[tick] cycles=%<cycles>d pc=0x%<pc>08x inst=0x%<inst>08x cps=%<cps>d stage=%<stage>s%<symbol>s',
            cycles: @cycle_count,
            pc: pc,
            inst: inst,
            cps: cps,
            stage: stage_for_pc(pc),
            symbol: symbol_suffix_for_pc(pc)
          )
        end

        def emit_trap_probe
          trap_taken = (peek_optional('trap_taken') || 0).to_i & 0x1
          return if trap_taken.zero?

          pc = read_pc
          inst = read_inst
          cause = (peek_optional('trap_cause') || 0).to_i & 0xFFFF_FFFF
          return if cause == 0x00000009 && !@options[:trap_external]

          tval = (peek_optional('trap_tval') || 0).to_i & 0xFFFF_FFFF
          a7 = safe_reg_read(17)
          a0 = safe_reg_read(10)
          a1 = safe_reg_read(11)
          key = [pc, inst, cause, tval, a7, a0, a1]
          return if key == @last_trap_key

          @last_trap_key = key
          puts format(
            '[trap] cycles=%<cycles>d pc=0x%<pc>08x inst=0x%<inst>08x cause=0x%<cause>08x tval=0x%<tval>08x a7=0x%<a7>08x a0=0x%<a0>08x a1=0x%<a1>08x%<symbol>s',
            cycles: @cycle_count,
            pc: pc,
            inst: inst,
            cause: cause,
            tval: tval,
            a7: a7,
            a0: a0,
            a1: a1,
            symbol: symbol_suffix_for_pc(pc)
          )
        end

        def emit_user_pc_probe
          pc = read_pc
          return unless pc < 0x0000_2000

          inst = read_inst
          a0 = safe_reg_read(10)
          a1 = safe_reg_read(11)
          a7 = safe_reg_read(17)
          key = [pc, inst, a0, a1, a7]
          return if key == @last_user_pc_key

          @last_user_pc_key = key
          puts format(
            '[user] cycles=%<cycles>d pc=0x%<pc>08x inst=0x%<inst>08x a0=0x%<a0>08x a1=0x%<a1>08x a7=0x%<a7>08x',
            cycles: @cycle_count,
            pc: pc,
            inst: inst,
            a0: a0,
            a1: a1,
            a7: a7
          )
        end

        def emit_allocator_probe
          pc = read_pc
          return unless (0x8000_0FEC..0x8000_0FF4).cover?(pc)

          begin
            a0 = @cpu.read_reg(10) & 0xFFFF_FFFF
            a2 = @cpu.read_reg(12) & 0xFFFF_FFFF
            a5 = @cpu.read_reg(15) & 0xFFFF_FFFF
          rescue StandardError
            return
          end

          total = (a2 - a0) & 0xFFFF_FFFF
          remaining = (a2 - a5) & 0xFFFF_FFFF
          puts format(
            '[probe] cycles=%<cycles>d memset a0=0x%<a0>08x a5=0x%<a5>08x a2=0x%<a2>08x total=%<total>d rem=%<rem>d',
            cycles: @cycle_count,
            a0: a0,
            a5: a5,
            a2: a2,
            total: total,
            rem: remaining
          )
        end

        def emit_lock_probe
          pc = read_pc
          return unless (0x8000_0E98..0x8000_0FAC).cover?(pc)

          begin
            ra = @cpu.read_reg(1) & 0xFFFF_FFFF
            s1 = @cpu.read_reg(9) & 0xFFFF_FFFF
            a0 = @cpu.read_reg(10) & 0xFFFF_FFFF
          rescue StandardError
            return
          end

          symbol = symbol_for_pc(ra)
          puts format(
            '[probe] cycles=%<cycles>d lock pc=0x%<pc>08x ra=0x%<ra>08x s1=0x%<s1>08x a0=0x%<a0>08x%<symbol>s',
            cycles: @cycle_count,
            pc: pc,
            ra: ra,
            s1: s1,
            a0: a0,
            symbol: symbol ? " ra_symbol=#{symbol}" : ''
          )
        end

        def safe_reg_read(index)
          @cpu.read_reg(index) & 0xFFFF_FFFF
        rescue StandardError
          0
        end

        def stop_condition_met?
          out = @cpu.uart_tx_bytes.pack('C*')
          out.include?('panic:') || out.include?('init: starting sh') || out.include?('$ ')
        end

        def stop_reason
          out = @cpu.uart_tx_bytes.pack('C*')
          return 'panic' if out.include?('panic:')
          return 'init_shell' if out.include?('init: starting sh')
          return 'shell_prompt' if out.include?('$ ')

          'max_cycles'
        end

        def read_pc
          if @cpu.respond_to?(:read_pc)
            @cpu.read_pc & 0xFFFF_FFFF
          else
            @cpu.pc & 0xFFFF_FFFF
          end
        end

        def read_inst
          if @cpu.respond_to?(:state)
            (@cpu.state[:inst] || 0).to_i & 0xFFFF_FFFF
          elsif @cpu.respond_to?(:current_inst)
            (@cpu.current_inst || 0).to_i & 0xFFFF_FFFF
          else
            0
          end
        rescue StandardError
          0
        end

        def write_pc(value)
          @cpu.write_pc(value & 0xFFFF_FFFF)
        end

        def stage_for_pc(pc)
          return 'panic_loop' if pc == 0x8000_0754
          return 'allocator_hot_loop' if [0x8000_0FEC, 0x8000_0FF0, 0x8000_0FF4].include?(pc)

          STAGE_TABLE.each do |range, label|
            return label if range.include?(pc)
          end
          'unknown'
        end

        def peek_optional(*names)
          names.each do |name|
            begin
              next unless @sim.has_signal?(name)

              return @sim.peek(name)
            rescue StandardError
              # keep trying alternates
            end
          end
          nil
        end

        def mmio_addr?(addr)
          return true if addr >= 0x0200_0000 && addr <= 0x0200_BFFF
          return true if addr >= 0x0C00_0000 && addr <= 0x0C20_0004
          return true if addr >= 0x1000_0000 && addr <= 0x1000_0007
          return true if addr >= 0x1000_1000 && addr <= 0x1000_1104

          false
        end

        def mmio_region(addr)
          return 'clint' if addr >= 0x0200_0000 && addr <= 0x0200_BFFF
          return 'plic' if addr >= 0x0C00_0000 && addr <= 0x0C20_0004
          return 'uart' if addr >= 0x1000_0000 && addr <= 0x1000_0007
          return 'virtio' if addr >= 0x1000_1000 && addr <= 0x1000_1104

          'mmio'
        end

        def load_symbol_table(path)
          return [] if path.nil? || path.empty?
          return [] unless File.file?(path)

          entries = File.readlines(path, chomp: true).filter_map do |line|
            fields = line.split
            next nil unless fields.length >= 3

            begin
              [Integer(fields[0], 16), fields[2]]
            rescue StandardError
              nil
            end
          end
          entries.sort_by(&:first)
        end

        def symbol_suffix_for_pc(pc)
          symbol = symbol_for_pc(pc)
          symbol ? " symbol=#{symbol}" : ''
        end

        def symbol_for_pc(pc)
          return nil if @symbol_table.empty?

          lo = 0
          hi = @symbol_table.length - 1
          best = nil
          while lo <= hi
            mid = (lo + hi) / 2
            if @symbol_table[mid][0] <= pc
              best = @symbol_table[mid]
              lo = mid + 1
            else
              hi = mid - 1
            end
          end
          return nil unless best

          base, name = best
          offset = pc - base
          offset.zero? ? name : format('%<name>s+0x%<offset>x', name: name, offset: offset)
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  opts = {
    core: :single,
    backend: :compiler,
    kernel: RHDL::Examples::RISCV::Xv6BootTracer::DEFAULT_KERNEL,
    fs: RHDL::Examples::RISCV::Xv6BootTracer::DEFAULT_FS_IMG,
    symbols: RHDL::Examples::RISCV::Xv6BootTracer::DEFAULT_SYMBOLS,
    max_cycles: 20_000_000,
    chunk: 100_000,
    fine_start: 0,
    fine_chunk: nil,
    heartbeat: 200_000,
    fast_boot: true,
    stage: true,
    mmio: true,
    allocator_probe: true,
    lock_probe: true,
    trap_external: false,
    user_probe: false
  }

  parser = OptionParser.new do |o|
    o.banner = 'Usage: bundle exec ruby examples/riscv/utilities/xv6_boot_tracer.rb [options]'
    o.on('--core CORE', 'single|pipeline (default: single)') do |v|
      value = v.to_s.strip.downcase.to_sym
      raise OptionParser::InvalidArgument, v unless %i[single pipeline].include?(value)

      opts[:core] = value
    end
    o.on('--backend BACKEND', 'interpreter|jit|compiler (default: compiler)') do |v|
      value = v.to_s.strip.downcase.to_sym
      raise OptionParser::InvalidArgument, v unless %i[interpreter jit compiler].include?(value)

      opts[:backend] = value
    end
    o.on('--kernel PATH', 'Path to xv6 kernel.bin') { |v| opts[:kernel] = File.expand_path(v) }
    o.on('--fs PATH', 'Path to xv6 fs.img') { |v| opts[:fs] = File.expand_path(v) }
    o.on('--symbols PATH', 'Path to kernel.nm symbol map (default: software/bin/kernel.nm)') do |v|
      opts[:symbols] = File.expand_path(v)
    end
    o.on('--no-symbols', 'Disable symbolized PC labels') { opts[:symbols] = nil }
    o.on('--max-cycles N', Integer, 'Maximum cycles to run (default: 20000000)') { |v| opts[:max_cycles] = v }
    o.on('--chunk N', Integer, 'Cycles per run chunk (default: 100000)') { |v| opts[:chunk] = v }
    o.on('--fine-start N', Integer, 'Switch to fine chunking at cycle N (default: 0)') { |v| opts[:fine_start] = v }
    o.on('--fine-chunk N', Integer, 'Cycles per run chunk at/after fine-start (default: chunk)') do |v|
      opts[:fine_chunk] = v
    end
    o.on('--heartbeat N', Integer, 'Progress print period in cycles (default: 200000)') { |v| opts[:heartbeat] = v }
    o.on('--[no-]fast-boot', 'Patch PHYSTOP LUI for faster tracing (default: true)') { |v| opts[:fast_boot] = v }
    o.on('--[no-]stage', 'Enable stage transition logs (default: true)') { |v| opts[:stage] = v }
    o.on('--[no-]mmio', 'Enable MMIO access logs (default: true)') { |v| opts[:mmio] = v }
    o.on('--[no-]allocator-probe', 'Enable allocator memset probes (default: true)') { |v| opts[:allocator_probe] = v }
    o.on('--[no-]lock-probe', 'Enable lock/callsite probes (default: true)') { |v| opts[:lock_probe] = v }
    o.on('--[no-]trap-external', 'Include supervisor external interrupts in trap log (default: false)') do |v|
      opts[:trap_external] = v
    end
    o.on('--[no-]user-probe', 'Log low-address user PC/reg transitions (default: false)') { |v| opts[:user_probe] = v }
    o.on('-h', '--help', 'Show this help') do
      puts o
      exit 0
    end
  end

  begin
    parser.parse!(ARGV)
    tracer = RHDL::Examples::RISCV::Xv6BootTracer.new(opts)
    tracer.run
  rescue OptionParser::ParseError => e
    warn e.message
    warn parser
    exit 2
  rescue StandardError => e
    warn "[trace] error: #{e.class}: #{e.message}"
    exit 1
  end
end
