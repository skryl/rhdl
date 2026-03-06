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
end
