# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SPARC64 LSU qctl1 request wiring' do
  let(:source) do
    File.read(
      File.expand_path(
        '../../../../../../../examples/sparc64/import/T1-CPU/lsu/lsu_qctl1.rb',
        __dir__
      )
    )
  end

  it 'does not hardwire the PCX request and atom outputs to zero' do
    aggregate_failures do
      expect(source).to include('spc_pcx_req_pq <= rq_stgpq_q')
      expect(source).to include('spc_pcx_atom_pq <= ff_spc_pcx_atom_pq_q')
      expect(source).to include('self.send(:UZfix_spc_pcx_atom_pq_buf1__z__bridge) <= ff_spc_pcx_atom_pq_q')
      expect(source).to include('self.send(:UZsize_spc_pcx_req_pq0_buf2__z__bridge) <= self.send(:UZsize_spc_pcx_req_pq0_buf2__a__bridge)')
      expect(source).not_to include('spc_pcx_req_pq <= lit(0, width: 5)')
      expect(source).not_to include('spc_pcx_atom_pq <= lit(0, width: 1)')
      expect(source).not_to include('self.send(:UZfix_spc_pcx_req_pq0_buf1__z__bridge) <= lit(0, width: 1)')
      expect(source).not_to include('self.send(:UZsize_spc_pcx_req_pq0_buf2__z__bridge) <= lit(0, width: 1)')
    end
  end
end
