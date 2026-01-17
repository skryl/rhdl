module HdlToolchain
  module_function

  def which(cmd)
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
      exe = File.join(path, cmd)
      return exe if File.executable?(exe) && !File.directory?(exe)
    end
    nil
  end

  def iverilog_available?
    which("iverilog") && which("vvp")
  end

  def ghdl_available?
    which("ghdl")
  end

  def yosys_available?
    !!which("yosys")
  end
end
