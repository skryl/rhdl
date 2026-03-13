# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RHDL::Codegen::CIRCT::ImportCleanup do
  def firtool_accepts?(mlir_text)
    return nil unless HdlToolchain.which('firtool')

    Dir.mktmpdir('circt_import_cleanup_spec') do |dir|
      in_path = File.join(dir, 'input.mlir')
      out_path = File.join(dir, 'output.v')
      File.write(in_path, mlir_text)
      system('firtool', in_path, '--verilog', '-o', out_path, out: File::NULL, err: File::NULL)
    end
  end

  def imported_module_for(mlir_text, top:)
    result = RHDL::Codegen.import_circt_mlir(mlir_text, strict: true, top: top, resolve_forward_refs: true)
    expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
    result.modules.find { |mod| mod.name.to_s == top }
  end

  def imported_modules_for(mlir_text, top:)
    result = RHDL::Codegen.import_circt_mlir(mlir_text, strict: true, top: top, resolve_forward_refs: true)
    expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
    result.modules.each_with_object({}) { |mod, acc| acc[mod.name.to_s] = mod }
  end

  def process_targets_for(mod)
    targets = []
    walker = lambda do |statements|
      Array(statements).each do |statement|
        case statement
        when RHDL::Codegen::CIRCT::IR::SeqAssign
          targets << statement.target.to_s
        when RHDL::Codegen::CIRCT::IR::If
          walker.call(statement.then_statements)
          walker.call(statement.else_statements)
        end
      end
    end

    Array(mod.processes).each { |process| walker.call(process.statements) }
    targets.uniq.sort
  end

  def assigned_signal_for(mod, target)
    assign = mod.assigns.find { |item| item.target.to_s == target.to_s }
    return nil unless assign&.expr.is_a?(RHDL::Codegen::CIRCT::IR::Signal)

    assign.expr.name.to_s
  end

  it 'removes the LLHD signal overlay from an imported register wrapper module' do
    mlir = <<~MLIR
      hw.module private @eReg_SavestateV__vhdl_c2a6c3cbd0d4(in %clk : i1, in %BUS_Din : i64, in %BUS_Adr : i10, in %BUS_wren : i1, in %BUS_rst : i1, in %Din : i61, out BUS_Dout : i64, out Dout : i61) {
        %c0_i3 = hw.constant 0 : i3
        %0 = llhd.constant_time <0ns, 0d, 1e>
        %c9_i10 = hw.constant 9 : i10
        %c0_i61 = hw.constant 0 : i61
        %dout_buffer = llhd.sig %c0_i61 : i61
        %n324 = llhd.sig %c0_i61 : i61
        %1 = llhd.prb %dout_buffer : i61
        %2 = llhd.prb %n324 : i61
        llhd.drv %dout_buffer, %2 after %0 : i61
        llhd.drv %dout_buffer, %c0_i61 after %0 : i61
        %3 = comb.icmp eq %BUS_Adr, %c9_i10 : i10
        %4 = comb.and %BUS_wren, %3 : i1
        %5 = comb.extract %BUS_Din from 0 : (i64) -> i61
        %6 = comb.mux %4, %5, %1 : i61
        %7 = comb.mux %BUS_rst, %c0_i61, %6 : i61
        %8 = seq.to_clock %clk
        %n324_0 = seq.firreg %7 clock %8 : i61
        llhd.drv %n324, %n324_0 after %0 : i61
        llhd.drv %n324, %c0_i61 after %0 : i61
        %9 = comb.concat %c0_i3, %1 : i3, i61
        hw.output %9, %1 : i64, i61
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'eReg_SavestateV__vhdl_c2a6c3cbd0d4')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')
    expect(result.cleaned_text).to include('seq.compreg')
    output_match = result.cleaned_text.match(/hw\.output [^,\n]+, (?<dout>%[A-Za-z0-9_]+) : i64, i61/)
    reg_match = result.cleaned_text.match(/(?<reg>%[A-Za-z0-9_]+) = seq\.compreg .* : i61/)
    expect(output_match).not_to be_nil
    expect(reg_match).not_to be_nil
    expect(output_match[:dout]).to eq(reg_match[:reg])

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'preserves live register reads when the LLHD overlay initializer is non-zero' do
    mlir = <<~MLIR
      hw.module @overlay_nonzero(in %clk : i1, in %din : i8, in %rst : i1, out dout : i8) {
        %t0 = llhd.constant_time <0ns, 0d, 1e>
        %c5_i8 = hw.constant 5 : i8
        %overlay = llhd.sig %c5_i8 : i8
        %state = llhd.sig %c5_i8 : i8
        %0 = llhd.prb %overlay : i8
        %1 = llhd.prb %state : i8
        llhd.drv %overlay, %1 after %t0 : i8
        llhd.drv %overlay, %c5_i8 after %t0 : i8
        %clk_0 = seq.to_clock %clk
        %2 = comb.mux %rst, %c5_i8, %din : i8
        %state_0 = seq.firreg %2 clock %clk_0 : i8
        llhd.drv %state, %state_0 after %t0 : i8
        llhd.drv %state, %c5_i8 after %t0 : i8
        hw.output %0 : i8
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'overlay_nonzero')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')
    expect(result.cleaned_text).to include('seq.compreg').or include('seq.firreg')

    output_match = result.cleaned_text.match(/hw\.output (?<dout>%[A-Za-z0-9_]+) : i8/)
    reg_match = result.cleaned_text.match(/(?<reg>%[A-Za-z0-9_]+) = seq\.(?:compreg|firreg) .* : i8/)
    expect(output_match).not_to be_nil
    expect(reg_match).not_to be_nil
    expect(output_match[:dout]).to eq(reg_match[:reg])

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'removes LLHD array_get and sig.extract overlays from imported state packing logic' do
    mlir = <<~MLIR
      hw.module @arrw(in %clk : i1, in %in_data : i8) -> (out_data : i8) {
        %false = hw.constant false : i1
        %true = hw.constant true
        %c0_i8 = hw.constant 0 : i8
        %c1_i1 = hw.constant 1 : i1
        %t0 = llhd.constant_time <0s, 0d, 0e>
        %t1 = llhd.constant_time <0s, 1d, 0e>
        %clk_0 = llhd.sig name "clk" %false : i1
        %clk_probe = llhd.prb %clk_0 : i1
        %in_data_0 = llhd.sig name "in_data" %c0_i8 : i8
        %arr_init = hw.array_create %c0_i8, %c0_i8 : i8
        %arr = llhd.sig %arr_init : !hw.array<2xi8>
        llhd.process {
          cf.br ^bb1
        ^bb1:
          %pclk = llhd.prb %clk_0 : i1
          llhd.wait (%clk_probe : i1), ^bb2
        ^bb2:
          %nclk = llhd.prb %clk_0 : i1
          %inv = comb.xor bin %pclk, %true : i1
          %edge = comb.and bin %inv, %nclk : i1
          cf.cond_br %edge, ^bb3, ^bb1
        ^bb3:
          %slot = llhd.sig.array_get %arr[%c1_i1] : <!hw.array<2xi8>>
          %din = llhd.prb %in_data_0 : i8
          llhd.drv %slot, %din after %t0 : i8
          cf.br ^bb1
        }
        llhd.drv %clk_0, %clk after %t1 : i1
        llhd.drv %in_data_0, %in_data after %t1 : i8
        %arr_probe = llhd.prb %arr : !hw.array<2xi8>
        %outv = comb.extract %arr_probe from 8 : (i16) -> i8
        hw.output %outv : i8
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'arrw')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')
    expect(result.cleaned_text).to include('seq.compreg')
    expect(result.cleaned_text).to include('comb.extract')

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'cleans imported array state ops and inverted clocks from circt-verilog core output' do
    mlir = <<~MLIR
      hw.module @arrmem(in %clk : i1, in %idx : i2, in %din : i8, in %we : i1, out dout : i8) {
        %init = hw.aggregate_constant [0 : i8, 0 : i8, 0 : i8, 0 : i8] : !hw.array<4xi8>
        %t0 = llhd.constant_time <0ns, 0d, 1e>
        %clk_c = seq.to_clock %clk
        %clk_n = seq.clock_inv %clk_c
        %mem = llhd.sig %init : !hw.array<4xi8>
        llhd.drv %mem, %init after %t0 : !hw.array<4xi8>
        %probe = llhd.prb %mem : !hw.array<4xi8>
        %old = hw.array_get %probe[%idx] : !hw.array<4xi8>, i2
        %next_arr = hw.array_inject %probe[%idx], %din : !hw.array<4xi8>, i2
        %selected = comb.mux %we, %next_arr, %probe : !hw.array<4xi8>
        %mem_next = seq.firreg %selected clock %clk_n : !hw.array<4xi8>
        llhd.drv %mem, %mem_next after %t0 : !hw.array<4xi8>
        hw.output %old : i8
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'arrmem')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')
    expect(result.cleaned_text).not_to include('seq.clock_inv')
    expect(result.cleaned_text).to include('comb.extract')
    expect(result.cleaned_text).to include('seq.compreg').or include('seq.firreg')

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'preserves explicit hw.instance output widths when selectively cleaning an LLHD parent module' do
    mlir = <<~MLIR
      hw.module @child(in %clk : i1, in %din : i61, out bus_dout : i64, out dout : i61) {
        %pad = hw.constant 0 : i3
        %bus = comb.concat %pad, %din : i3, i61
        hw.output %bus, %din : i64, i61
      }

      hw.module @parent(in %clk : i1, out out_bit : i1, out out_word : i61) {
        %c0_i61 = hw.constant 0 : i61
        %t0 = llhd.constant_time <0s, 1d, 0e>
        %state = llhd.sig %c0_i61 : i61
        %state_q = llhd.prb %state : i61
        %child_bus, %child_dout = hw.instance "u_child" @child(clk: %clk : i1, din: %c0_i61 : i61) -> (bus_dout: i64, dout: i61)
        llhd.drv %state, %child_dout after %t0 : i61
        %bit0 = comb.extract %state_q from 0 : (i61) -> i1
        hw.output %bit0, %state_q : i1, i61
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'parent')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')
    expect(result.cleaned_text).to include('-> (bus_dout: i64, dout: i61)')

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'only reparses dirty modules when cleaning a wrapped multi-module package' do
    mlir = <<~MLIR
      module {
        hw.module @clean(in %a : i1, out y : i1) {
          hw.output %a : i1
        }

        hw.module @dirty(in %clk : i1, in %d : i8, out q : i8) {
          %c0_i8 = hw.constant 0 : i8
          %t0 = llhd.constant_time <0ns, 0d, 1e>
          %state = llhd.sig %c0_i8 : i8
          %state_q = llhd.prb %state : i8
          %clock = seq.to_clock %clk
          %next = seq.firreg %d clock %clock : i8
          llhd.drv %state, %next after %t0 : i8
          hw.output %state_q : i8
        }
      }
    MLIR

    parsed_chunks = []
    allow(described_class).to receive(:parse_imported_core_mlir).and_wrap_original do |method, *args, **kwargs|
      parsed_chunks << args.first
      method.call(*args, **kwargs)
    end

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'dirty')

    expect(result).to be_success
    expect(result.cleaned_text).to include('hw.module @clean')
    expect(result.cleaned_text).not_to include('llhd.')
    expect(parsed_chunks.length).to eq(1)
    expect(parsed_chunks.first).to include('hw.module @dirty')
    expect(parsed_chunks.first).not_to include('hw.module @clean')
  end

  it 'cleans async-reset firregs that feed resultful LLHD process drives' do
    mlir = <<~MLIR
      hw.module @async_result_proc(in %clk : i1, in %rst : i1, in %req : i1, out gnt : i1) {
        %false = hw.constant false
        %true = hw.constant true
        %t0 = llhd.constant_time <0ns, 0d, 1e>
        %c0_i1 = hw.constant 0 : i1
        %next_state = llhd.sig %c0_i1 : i1
        %next_state_q = llhd.prb %next_state : i1
        %clk_c = seq.to_clock %clk
        %state = seq.firreg %next_state_q clock %clk_c reset async %rst, %c0_i1 : i1
        %proc:2 = llhd.process -> i1, i1 {
          cf.br ^bb1(%c0_i1, %false : i1, i1)
        ^bb1(%value: i1, %enable: i1):
          llhd.wait yield (%value, %enable : i1, i1), (%state, %req : i1, i1), ^bb2
        ^bb2:
          cf.cond_br %req, ^bb1(%true, %true : i1, i1), ^bb1(%state, %true : i1, i1)
        }
        llhd.drv %next_state, %proc#0 after %t0 if %proc#1 : i1
        hw.output %state : i1
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'async_result_proc')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')
    expect(result.cleaned_text).to include('seq.compreg')
    expect(result.cleaned_text).to include('hw.output')

    imported = imported_module_for(result.cleaned_text, top: 'async_result_proc')
    process_targets = process_targets_for(imported)
    expect(process_targets).not_to be_empty
    expect(assigned_signal_for(imported, 'gnt')).to be_a(String)
    expect(process_targets).to include(assigned_signal_for(imported, 'gnt'))

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'binds resultful LLHD drive outputs to yielded values instead of sampled wait inputs' do
    mlir = <<~MLIR
      hw.module @result_yield_bind(in %din : i1, in %clk : i1, in %rst_l : i1, in %se : i1, in %si : i1, out q : i1) {
        %t0 = llhd.constant_time <0ns, 1d, 0e>
        %true = hw.constant true
        %false = hw.constant false
        %q_sig = llhd.sig %false : i1
        %proc:2 = llhd.process -> i1, i1 {
          cf.br ^bb1(%clk, %rst_l, %false, %false : i1, i1, i1, i1)
        ^bb1(%prev_clk: i1, %prev_rst_l: i1, %value: i1, %enable: i1):
          llhd.wait yield (%value, %enable : i1, i1), (%clk, %rst_l : i1, i1), ^bb2(%prev_clk, %prev_rst_l : i1, i1)
        ^bb2(%seen_clk: i1, %seen_rst_l: i1):
          %edge_clk = comb.xor bin %seen_clk, %true : i1
          %posedge_clk = comb.and bin %edge_clk, %clk : i1
          %rst_low = comb.xor bin %rst_l, %true : i1
          %negedge_rst_l = comb.and bin %seen_rst_l, %rst_low : i1
          %trigger = comb.or bin %posedge_clk, %negedge_rst_l : i1
          cf.cond_br %trigger, ^bb3, ^bb1(%clk, %rst_l, %false, %false : i1, i1, i1, i1)
        ^bb3:
          %selected = comb.mux %se, %si, %din : i1
          %next_q = comb.and %rst_l, %selected : i1
          cf.br ^bb1(%clk, %rst_l, %next_q, %true : i1, i1, i1, i1)
        }
        llhd.drv %q_sig, %proc#0 after %t0 if %proc#1 : i1
        %q_value = llhd.prb %q_sig : i1
        hw.output %q_value : i1
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'result_yield_bind')

    expect(result).to be_success
    expect(result.cleaned_text).to include('comb.mux %se, %si, %din')
    expect(result.cleaned_text).to include('comb.and %rst_l')
    expect(result.cleaned_text).not_to include('comb.mux %rst_l, %clk')

    imported = imported_module_for(result.cleaned_text, top: 'result_yield_bind')
    process_targets = process_targets_for(imported)
    expect(process_targets).not_to be_empty
    expect(assigned_signal_for(imported, 'q')).to be_a(String)
    expect(process_targets).to include(assigned_signal_for(imported, 'q'))
  end

  it 'cleans one-shot resultful LLHD array init processes even with unrelated llhd.drv lines in front' do
    mlir = <<~MLIR
      hw.module @resultful_array_init(in %clk : i1, in %rd : i1, out y : i8) {
        %t0 = llhd.constant_time <0ns, 1d, 0e>
        %c0_i32 = hw.constant 0 : i32
        %c1_i32 = hw.constant 1 : i32
        %c2_i32 = hw.constant 2 : i32
        %c0_i8 = hw.constant 0 : i8
        %true = hw.constant true
        %false = hw.constant false
        %zero_arr = hw.aggregate_constant [0 : i8, 0 : i8] : !hw.array<2xi8>
        %q_sig = llhd.sig %c0_i8 : i8
        %mem = llhd.sig %zero_arr : !hw.array<2xi8>
        %proc:2 = llhd.process -> i32, !hw.array<2xi8>, i1 {
          cf.br ^bb1(%c0_i32, %zero_arr, %false : i32, !hw.array<2xi8>, i1)
        ^bb1(%i: i32, %acc: !hw.array<2xi8>, %done: i1):
          %lt = comb.icmp slt %i, %c2_i32 : i32
          cf.cond_br %lt, ^bb2, ^bb3
        ^bb2:
          %idx = comb.extract %i from 0 : (i32) -> i1
          %next = hw.array_inject %acc[%idx], %c0_i8 : !hw.array<2xi8>, i1
          %i_next = comb.add %i, %c1_i32 : i32
          cf.br ^bb1(%i_next, %next, %true : i32, !hw.array<2xi8>, i1)
        ^bb3:
          llhd.halt %i, %acc, %done : i32, !hw.array<2xi8>, i1
        }
        llhd.drv %q_sig, %c0_i8 after %t0 : i8
        llhd.drv %mem, %proc#1 after %t0 if %proc#2 : !hw.array<2xi8>
        %read = hw.array_get %mem[%rd] : !hw.array<2xi8>, i1
        %next_arr = hw.array_inject %mem[%rd], %c0_i8 : !hw.array<2xi8>, i1
        %clock = seq.to_clock %clk
        %mem_next = seq.firreg %next_arr clock %clock : !hw.array<2xi8>
        llhd.drv %mem, %mem_next after %t0 : !hw.array<2xi8>
        hw.output %read : i8
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'resultful_array_init')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')
    expect(result.cleaned_text).to include('hw.output')
  end

  it 'cleans resultful LLHD array-copy loops through arg-less helper blocks without zeroing yielded state' do
    mlir = <<~MLIR
      hw.module @shadow_loop(in %clk : i1, in %din : i8, out y : i8) {
        %t0 = llhd.constant_time <0ns, 0d, 1e>
        %c0_i32 = hw.constant 0 : i32
        %c1_i32 = hw.constant 1 : i32
        %c2_i32 = hw.constant 2 : i32
        %c0_i8 = hw.constant 0 : i8
        %true = hw.constant true
        %false = hw.constant false
        %zero_arr = hw.aggregate_constant [0 : i8, 0 : i8] : !hw.array<2xi8>
        %state = llhd.sig %c0_i8 : i8
        %arr = llhd.sig %zero_arr : !hw.array<2xi8>
        %probe_arr = llhd.prb %arr : !hw.array<2xi8>
        %proc:4 = llhd.process -> i8, i1, !hw.array<2xi8>, i1 {
          cf.br ^bb1(%clk, %c0_i8, %false, %zero_arr, %false : i1, i8, i1, !hw.array<2xi8>, i1)
        ^bb1(%prev_clk: i1, %data: i8, %en: i1, %acc: !hw.array<2xi8>, %done: i1):
          llhd.wait yield (%data, %en, %acc, %done : i8, i1, !hw.array<2xi8>, i1), (%clk : i1), ^bb2(%prev_clk : i1)
        ^bb2(%seen_clk: i1):
          %edge = comb.xor bin %seen_clk, %true : i1
          %posedge = comb.and bin %edge, %clk : i1
          cf.cond_br %posedge, ^bb3(%c0_i32, %probe_arr, %false : i32, !hw.array<2xi8>, i1), ^bb1(%clk, %c0_i8, %false, %probe_arr, %false : i1, i8, i1, !hw.array<2xi8>, i1)
        ^bb3(%i: i32, %loop_acc: !hw.array<2xi8>, %loop_done: i1):
          %lt = comb.icmp slt %i, %c2_i32 : i32
          cf.cond_br %lt, ^bb4, ^bb1(%clk, %din, %true, %loop_acc, %loop_done : i1, i8, i1, !hw.array<2xi8>, i1)
        ^bb4:
          %bit = comb.extract %i from 0 : (i32) -> i1
          %next_arr = hw.array_inject %loop_acc[%bit], %din : !hw.array<2xi8>, i1
          %next_idx = comb.add %i, %c1_i32 : i32
          cf.br ^bb3(%next_idx, %next_arr, %true : i32, !hw.array<2xi8>, i1)
        }
        llhd.drv %state, %proc#0 after %t0 if %proc#1 : i8
        llhd.drv %arr, %proc#2 after %t0 if %proc#3 : !hw.array<2xi8>
        %read = hw.array_get %arr[%false] : !hw.array<2xi8>, i1
        hw.output %read : i8
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'shadow_loop')

    expect(result).to be_success
    expect(result.cleaned_text).not_to include('llhd.')

    imported = imported_module_for(result.cleaned_text, top: 'shadow_loop')
    process_targets = process_targets_for(imported)
    expect(process_targets.length).to eq(2)

    seq_assigns = []
    walker = lambda do |statements|
      Array(statements).each do |statement|
        case statement
        when RHDL::Codegen::CIRCT::IR::SeqAssign
          seq_assigns << statement
        when RHDL::Codegen::CIRCT::IR::If
          walker.call(statement.then_statements)
          walker.call(statement.else_statements)
        end
      end
    end
    imported.processes.each { |process| walker.call(process.statements) }

    expect(seq_assigns.length).to eq(2)
    expect(seq_assigns.map { |statement| statement.expr.inspect }.join("\n")).to include('din')

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'preserves dual-port memories as seq.firmem through imported cleanup' do
    skip 'circt-verilog not available' unless HdlToolchain.which('circt-verilog')

    Dir.mktmpdir('dual_port_import_cleanup') do |dir|
      verilog_path = File.join(dir, 'simple_dpram.v')
      mlir_path = File.join(dir, 'simple_dpram.mlir')
      File.write(verilog_path, <<~VERILOG)
        module simple_dpram(
          input clock0,
          input clock1,
          input clocken0,
          input clocken1,
          input [4:0] address_a,
          input [4:0] address_b,
          input [7:0] data_a,
          input [7:0] data_b,
          input wren_a,
          input wren_b,
          output reg [7:0] q_a,
          output reg [7:0] q_b
        );
          reg [7:0] mem [0:31];
          always @(posedge clock0) begin
            if (clocken0) begin
              if (wren_a) mem[address_a] <= data_a;
              q_a <= mem[address_a];
            end
          end
          always @(posedge clock1) begin
            if (clocken1) begin
              if (wren_b) mem[address_b] <= data_b;
              q_b <= mem[address_b];
            end
          end
        endmodule
      VERILOG

      system('circt-verilog', '--detect-memories', '--ir-hw', '--top=simple_dpram', verilog_path, out: mlir_path, err: File::NULL)
      mlir = File.read(mlir_path)

      result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'simple_dpram')

      expect(result).to be_success
      expect(result.cleaned_text).to include('seq.firmem 0, 1, undefined, port_order : <32 x 8>')
      expect(result.cleaned_text.scan('seq.firmem.write_port %mem[').length).to eq(2)
      read_clock_tokens = result.cleaned_text.scan(/seq\.firmem\.read_port %mem\[[^\]]+\], clock (%[A-Za-z0-9_]+)/).flatten
      expect(read_clock_tokens.length).to eq(2)
      expect(read_clock_tokens.uniq.length).to eq(2)
      expect(result.cleaned_text).not_to include('seq.compreg %rt_tmp_1_256')
      expect(result.cleaned_text).not_to include('seq.compreg %rt_tmp_3_256')
      firtool_result = firtool_accepts?(result.cleaned_text)
      expect(firtool_result).not_to eq(false)
    end
  end

  it 'leaves aggregate-only core modules untouched when no LLHD overlay is present' do
    mlir = <<~MLIR
      hw.module @codes_like(in %idx : i2, out y : i8) {
        %init = hw.aggregate_constant [1 : i8, 2 : i8, 3 : i8, 4 : i8] : !hw.array<4xi8>
        %selected = hw.array_get %init[%idx] : !hw.array<4xi8>, i2
        hw.output %selected : i8
      }
    MLIR

    expect(described_class).not_to receive(:parse_imported_core_mlir)

    result = described_class.cleanup_imported_core_mlir(mlir, strict: true, top: 'codes_like')

    expect(result).to be_success
    expect(result.cleaned_text).to eq(mlir)
  end

  it 'stubs selected clean core modules even when no LLHD overlay is present' do
    mlir = <<~MLIR
      hw.module @child(in %reset_in : i1, in %din : i8, out reset_out : i1, out dout : i8) {
        %false = hw.constant false
        %c1_i8 = hw.constant 1 : i8
        hw.output %false, %c1_i8 : i1, i8
      }

      hw.module @top(in %reset_in : i1, in %din : i8, out reset_out : i1, out dout : i8) {
        %child_reset, %child_dout = hw.instance "u_child" @child(reset_in: %reset_in : i1, din: %din : i8) -> (reset_out: i1, dout: i8)
        hw.output %child_reset, %child_dout : i1, i8
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(
      mlir,
      strict: true,
      top: 'top',
      stub_modules: [
        {
          name: 'child',
          outputs: {
            'reset_out' => { signal: 'reset_in' },
            'dout' => { value: 5 }
          }
        }
      ]
    )

    expect(result).to be_success
    expect(result.stubbed_modules).to eq(['child'])

    modules = imported_modules_for(result.cleaned_text, top: 'top')
    child = modules.fetch('child')
    expect(assigned_signal_for(child, 'reset_out')).to eq('reset_in')
    dout_assign = child.assigns.find { |assign| assign.target.to_s == 'dout' }
    expect(dout_assign&.expr).to be_a(RHDL::Codegen::CIRCT::IR::Literal)
    expect(dout_assign.expr.value).to eq(5)

    firtool_result = firtool_accepts?(result.cleaned_text)
    expect(firtool_result).not_to eq(false)
  end

  it 'fails when a requested stub module is missing from the imported package' do
    mlir = <<~MLIR
      hw.module @top(in %a : i1, out y : i1) {
        hw.output %a : i1
      }
    MLIR

    result = described_class.cleanup_imported_core_mlir(
      mlir,
      strict: true,
      top: 'top',
      stub_modules: ['missing_child']
    )

    expect(result.success?).to be(false)
    expect(result.import_result.diagnostics.map(&:op)).to include('import.stub')
    expect(result.import_result.diagnostics.map(&:message).join("\n")).to include('missing_child')
  end
end
