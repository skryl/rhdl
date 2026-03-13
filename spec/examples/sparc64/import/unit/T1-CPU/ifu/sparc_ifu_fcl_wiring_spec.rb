# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SPARC64 IFU fcl primitive wiring' do
  let(:source) do
    File.read(
      File.expand_path(
        '../../../../../../../examples/sparc64/import/T1-CPU/ifu/sparc_ifu_fcl.rb',
        __dir__
      )
    )
  end

  it 'does not leave the fetch-control primitive chain hardwired to zero' do
    aggregate_failures do
      expect(source).to include('self.send(:UZsize_swbuf__z__bridge) <= dtu_fcl_ntr_s')
      expect(source).to include('self.send(:UZsize_tmne30__a__bridge) <= self.send(:UZsize_tmne10__z__bridge)')
      expect(source).to include('self.send(:UZsize_bcinv__a__bridge) <= self.send(:UZsize_bcmux__z__bridge)')
      expect(source).to include('self.send(:UZfix_ntfmux0__d0__bridge) <= self.send(:UZsize_tfncr0__z__bridge)')
      expect(source).to include('self.send(:UZsize_ntfin_buf0__a__bridge) <= self.send(:UZfix_ntfmux0__z__bridge)')
      expect(source).not_to include('self.send(:UZsize_swbuf__z__bridge) <= lit(0, width: 1)')
      expect(source).not_to include('self.send(:UZsize_bcmux__z__bridge) <= lit(0, width: 1)')
      expect(source).not_to include('self.send(:UZfix_ntfmux0__z__bridge) <= lit(0, width: 1)')
    end
  end
end
