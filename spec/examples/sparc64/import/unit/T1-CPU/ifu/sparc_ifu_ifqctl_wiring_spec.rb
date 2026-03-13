# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SPARC64 IFU ifqctl primitive wiring' do
  let(:source) do
    File.read(
      File.expand_path(
        '../../../../../../../examples/sparc64/import/T1-CPU/ifu/sparc_ifu_ifqctl.rb',
        __dir__
      )
    )
  end

  it 'does not hardwire primitive-output bridge wires to zero' do
    aggregate_failures do
      expect(source).to include('self.send(:UZsize_ftid_bf0__z__bridge) <= (self.send(:UZsize_ftid_bf0__a__bridge) ^ lit(1, width: 1))')
      expect(source).to include('self.send(:UZsize_ftid_bf1__z__bridge) <= (self.send(:UZsize_ftid_bf1__a__bridge) ^ lit(1, width: 1))')
      expect(source).to include('self.send(:UZsize_acc_n2__z__bridge) <= ((self.send(:UZsize_acc_n2__a__bridge) & self.send(:UZsize_acc_n2__b__bridge)) ^ lit(1, width: 1))')
      expect(source).not_to include('self.send(:UZsize_ftid_bf0__z__bridge) <= lit(0, width: 1)')
      expect(source).not_to include('self.send(:UZsize_ftid_bf1__z__bridge) <= lit(0, width: 1)')
      expect(source).not_to include('self.send(:UZsize_acc_n2__z__bridge) <= lit(0, width: 1)')
    end
  end
end
