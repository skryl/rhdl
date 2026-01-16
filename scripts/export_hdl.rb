#!/usr/bin/env ruby
# Export all RHDL DSL components to VHDL and Verilog

require_relative '../lib/rhdl'

# Determine output directories
script_dir = File.dirname(__FILE__)
project_root = File.expand_path('..', script_dir)
vhdl_dir = File.join(project_root, 'vhdl')
verilog_dir = File.join(project_root, 'verilog')

# Ensure output directories exist
require 'fileutils'
FileUtils.mkdir_p(vhdl_dir)
FileUtils.mkdir_p(verilog_dir)

puts "RHDL Component Exporter"
puts "=" * 50
puts

# Get all exportable components
components = RHDL::Exporter.list_components

if components.empty?
  puts "No exportable components found."
  exit 0
end

puts "Found #{components.size} exportable component(s):"
puts

# Export each component
exported_count = 0
components.each do |info|
  component = info[:class]
  name = info[:name]

  begin
    # Export to VHDL
    vhdl_file = File.join(vhdl_dir, "#{name}.vhd")
    vhdl_content = component.to_vhdl
    File.write(vhdl_file, vhdl_content)

    # Export to Verilog
    verilog_file = File.join(verilog_dir, "#{name}.v")
    verilog_content = component.to_verilog
    File.write(verilog_file, verilog_content)

    puts "  [OK] #{component.name}"
    puts "       -> #{vhdl_file}"
    puts "       -> #{verilog_file}"
    exported_count += 1
  rescue => e
    puts "  [ERROR] #{component.name}: #{e.message}"
  end
end

puts
puts "=" * 50
puts "Exported #{exported_count}/#{components.size} components"
puts "VHDL files:    #{vhdl_dir}"
puts "Verilog files: #{verilog_dir}"
