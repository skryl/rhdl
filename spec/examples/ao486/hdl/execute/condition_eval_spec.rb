require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/execute/condition_eval'

RSpec.describe RHDL::Examples::AO486::ConditionEval do
  let(:cond) { RHDL::Examples::AO486::ConditionEval.new }

  def eval_cond(c, index, of: 0, cf: 0, zf: 0, sf: 0, pf: 0)
    c.set_input(:condition_index, index)
    c.set_input(:oflag, of)
    c.set_input(:cflag, cf)
    c.set_input(:zflag, zf)
    c.set_input(:sflag, sf)
    c.set_input(:pflag, pf)
    c.propagate
    c.get_output(:condition_met)
  end

  describe 'all 16 conditions' do
    # O (0): oflag
    it('O: true when OF=1')  { expect(eval_cond(cond, 0, of: 1)).to eq(1) }
    it('O: false when OF=0') { expect(eval_cond(cond, 0, of: 0)).to eq(0) }

    # NO (1): ~oflag
    it('NO: true when OF=0')  { expect(eval_cond(cond, 1, of: 0)).to eq(1) }
    it('NO: false when OF=1') { expect(eval_cond(cond, 1, of: 1)).to eq(0) }

    # B/C (2): cflag
    it('B: true when CF=1')  { expect(eval_cond(cond, 2, cf: 1)).to eq(1) }
    it('B: false when CF=0') { expect(eval_cond(cond, 2, cf: 0)).to eq(0) }

    # NB/NC (3): ~cflag
    it('NB: true when CF=0')  { expect(eval_cond(cond, 3, cf: 0)).to eq(1) }
    it('NB: false when CF=1') { expect(eval_cond(cond, 3, cf: 1)).to eq(0) }

    # Z/E (4): zflag
    it('Z: true when ZF=1')  { expect(eval_cond(cond, 4, zf: 1)).to eq(1) }
    it('Z: false when ZF=0') { expect(eval_cond(cond, 4, zf: 0)).to eq(0) }

    # NZ/NE (5): ~zflag
    it('NZ: true when ZF=0')  { expect(eval_cond(cond, 5, zf: 0)).to eq(1) }
    it('NZ: false when ZF=1') { expect(eval_cond(cond, 5, zf: 1)).to eq(0) }

    # BE/NA (6): cflag | zflag
    it('BE: true when CF=1')         { expect(eval_cond(cond, 6, cf: 1)).to eq(1) }
    it('BE: true when ZF=1')         { expect(eval_cond(cond, 6, zf: 1)).to eq(1) }
    it('BE: false when CF=0, ZF=0')  { expect(eval_cond(cond, 6, cf: 0, zf: 0)).to eq(0) }

    # NBE/A (7): ~cflag & ~zflag
    it('A: true when CF=0, ZF=0')  { expect(eval_cond(cond, 7, cf: 0, zf: 0)).to eq(1) }
    it('A: false when CF=1')       { expect(eval_cond(cond, 7, cf: 1)).to eq(0) }

    # S (8): sflag
    it('S: true when SF=1')  { expect(eval_cond(cond, 8, sf: 1)).to eq(1) }
    it('S: false when SF=0') { expect(eval_cond(cond, 8, sf: 0)).to eq(0) }

    # NS (9): ~sflag
    it('NS: true when SF=0')  { expect(eval_cond(cond, 9, sf: 0)).to eq(1) }
    it('NS: false when SF=1') { expect(eval_cond(cond, 9, sf: 1)).to eq(0) }

    # P/PE (10): pflag
    it('P: true when PF=1')  { expect(eval_cond(cond, 10, pf: 1)).to eq(1) }
    it('P: false when PF=0') { expect(eval_cond(cond, 10, pf: 0)).to eq(0) }

    # NP/PO (11): ~pflag
    it('NP: true when PF=0')  { expect(eval_cond(cond, 11, pf: 0)).to eq(1) }
    it('NP: false when PF=1') { expect(eval_cond(cond, 11, pf: 1)).to eq(0) }

    # L/NGE (12): sflag ^ oflag
    it('L: true when SF=1, OF=0')   { expect(eval_cond(cond, 12, sf: 1, of: 0)).to eq(1) }
    it('L: true when SF=0, OF=1')   { expect(eval_cond(cond, 12, sf: 0, of: 1)).to eq(1) }
    it('L: false when SF=1, OF=1')  { expect(eval_cond(cond, 12, sf: 1, of: 1)).to eq(0) }

    # NL/GE (13): ~(sflag ^ oflag)
    it('GE: true when SF=OF')     { expect(eval_cond(cond, 13, sf: 1, of: 1)).to eq(1) }
    it('GE: false when SF!=OF')   { expect(eval_cond(cond, 13, sf: 1, of: 0)).to eq(0) }

    # LE/NG (14): (sflag ^ oflag) | zflag
    it('LE: true when ZF=1')        { expect(eval_cond(cond, 14, zf: 1)).to eq(1) }
    it('LE: true when SF!=OF')      { expect(eval_cond(cond, 14, sf: 1, of: 0)).to eq(1) }
    it('LE: false when SF=OF, ZF=0') { expect(eval_cond(cond, 14, sf: 0, of: 0, zf: 0)).to eq(0) }

    # NLE/G (15): ~((sflag ^ oflag) | zflag)
    it('G: true when SF=OF, ZF=0') { expect(eval_cond(cond, 15, sf: 1, of: 1, zf: 0)).to eq(1) }
    it('G: false when ZF=1')       { expect(eval_cond(cond, 15, sf: 1, of: 1, zf: 1)).to eq(0) }
  end
end
