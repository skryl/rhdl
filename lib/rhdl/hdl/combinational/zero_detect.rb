# HDL Combinational Logic Components
# Zero Detector

module RHDL
  module HDL
    # Zero Detector
    class ZeroDetect < SimComponent
      parameter :width, default: 8

      input :a, width: :width
      output :zero

      behavior do
        w = port_width(:a)
        zero <= (a == lit(0, width: w))
      end
    end
  end
end
