require_relative 'lib/rhdl/version'

Gem::Specification.new do |spec|
  spec.name          = "rhdl"
  spec.version       = RHDL::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = "Ruby Hardware Description Language - A Ruby DSL for hardware design"
  spec.description   = "RHDL allows you to design hardware using Ruby's flexible syntax and export to VHDL. " \
                      "It provides a comfortable environment for Ruby developers to create hardware designs " \
                      "with all the power of Ruby's metaprogramming capabilities."
  spec.homepage      = "https://github.com/username/rhdl"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[lib/**/*.rb cpu/**/*.rb [A-Z]*.md [A-Z]*.txt])

  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "parslet", "~> 2.0"
  spec.add_dependency "activesupport", "~> 7.0"
end
