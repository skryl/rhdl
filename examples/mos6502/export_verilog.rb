# Export MOS 6502S (Synthesizable) to Verilog
# Run with: bundle exec ruby examples/mos6502/export_verilog.rb

require 'active_support/core_ext/string/inflections'
require_relative '../../lib/rhdl'
require_relative 'datapath'
require_relative 'memory'

module MOS6502
  def self.export_all_verilog(output_dir = "verilog/mos6502")
    FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

    components = {
      "mos6502_registers" => Registers,
      "mos6502_stack_pointer" => StackPointer,
      "mos6502_program_counter" => ProgramCounter,
      "mos6502_instruction_register" => InstructionRegister,
      "mos6502_address_latch" => AddressLatch,
      "mos6502_data_latch" => DataLatch,
      "mos6502_status_register" => StatusRegister,
      "mos6502_address_generator" => AddressGenerator,
      "mos6502_indirect_addr_calc" => IndirectAddressCalc,
      "mos6502_alu" => ALU,
      "mos6502_instruction_decoder" => InstructionDecoder,
      "mos6502_control_unit" => ControlUnit,
      "mos6502_memory" => Memory
    }

    exported = []
    components.each do |filename, klass|
      if klass.respond_to?(:to_verilog)
        verilog = klass.to_verilog
        filepath = File.join(output_dir, "#{filename}.v")
        File.write(filepath, verilog)
        exported << filename
        puts "Exported: #{filepath}"
      else
        puts "Skipped (no to_verilog): #{klass.name}"
      end
    end

    puts "\nExported #{exported.size} Verilog files to #{output_dir}/"
    exported
  end
end

if __FILE__ == $0
  MOS6502.export_all_verilog
end
