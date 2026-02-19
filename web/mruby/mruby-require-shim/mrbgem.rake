MRuby::Gem::Specification.new('mruby-require-shim') do |spec|
  spec.license = 'MIT'
  spec.author = 'RHDL'
  spec.summary = 'Pure Ruby require/require_relative shim for Emscripten builds'

  spec.add_dependency 'mruby-io'
  spec.add_dependency 'mruby-eval'
end
