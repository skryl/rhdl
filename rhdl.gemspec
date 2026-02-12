# frozen_string_literal: true

require_relative "lib/rhdl/version"

Gem::Specification.new do |spec|
  spec.name          = "rhdl"
  spec.version       = RHDL::VERSION
  spec.authors       = ["Alex Skryl"]
  spec.email         = ["rut216@gmail.com"]

  spec.summary       = "Ruby Hardware Description Language - A Ruby DSL for hardware design"
  spec.description   = <<~DESC
    RHDL (Ruby Hardware Description Language) is a Domain Specific Language for designing
    hardware using Ruby's syntax. It provides gate-level HDL simulation with signal propagation,
    MOS 6502 and custom 8-bit CPU implementations, HDL export to Verilog, interactive terminal
    GUI for debugging, and diagram generation (SVG, PNG, DOT formats).
  DESC
  spec.homepage      = "https://github.com/skryl/rhdl"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "docs/**/*", "examples/**/*", "exe/*", "LICENSE", "README.md", "CHANGELOG.md"].reject do |f|
      File.directory?(f) || f.start_with?(".")
    end
  end

  spec.bindir = "exe"
  spec.executables = ["rhdl"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "base64"

  # Development dependencies (for those developing the gem itself)
  spec.add_development_dependency "benchmark-ips", "~> 2.12"
  spec.add_development_dependency "irb"
  spec.add_development_dependency "parallel_tests", "~> 4.0"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webrick"
end
