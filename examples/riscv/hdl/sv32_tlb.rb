# 4-entry direct-mapped Sv32 TLB
# Tags on {satp root PPN, VPN} and caches translated PPN plus permission bits.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module RISCV
      class Sv32Tlb < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst

        input :lookup_en
        input :lookup_vpn, width: 20
        input :lookup_root_ppn, width: 20
        output :hit
        output :ppn, width: 20
        output :perm_r
        output :perm_w
        output :perm_x
        output :perm_u

        input :fill_en
        input :fill_vpn, width: 20
        input :fill_root_ppn, width: 20
        input :fill_ppn, width: 20
        input :fill_perm_r
        input :fill_perm_w
        input :fill_perm_x
        input :fill_perm_u

        input :flush

        # Internal state is modeled as sequential outputs (4 direct-mapped entries).
        output :state_valid0
        output :state_valid1
        output :state_valid2
        output :state_valid3
        output :state_vpn0, width: 20
        output :state_vpn1, width: 20
        output :state_vpn2, width: 20
        output :state_vpn3, width: 20
        output :state_root_ppn0, width: 20
        output :state_root_ppn1, width: 20
        output :state_root_ppn2, width: 20
        output :state_root_ppn3, width: 20
        output :state_ppn0, width: 20
        output :state_ppn1, width: 20
        output :state_ppn2, width: 20
        output :state_ppn3, width: 20
        output :state_perm_r0
        output :state_perm_r1
        output :state_perm_r2
        output :state_perm_r3
        output :state_perm_w0
        output :state_perm_w1
        output :state_perm_w2
        output :state_perm_w3
        output :state_perm_x0
        output :state_perm_x1
        output :state_perm_x2
        output :state_perm_x3
        output :state_perm_u0
        output :state_perm_u1
        output :state_perm_u2
        output :state_perm_u3

        sequential clock: :clk, reset: :rst, reset_values: {
          state_valid0: 0, state_valid1: 0, state_valid2: 0, state_valid3: 0,
          state_vpn0: 0, state_vpn1: 0, state_vpn2: 0, state_vpn3: 0,
          state_root_ppn0: 0, state_root_ppn1: 0, state_root_ppn2: 0, state_root_ppn3: 0,
          state_ppn0: 0, state_ppn1: 0, state_ppn2: 0, state_ppn3: 0,
          state_perm_r0: 0, state_perm_r1: 0, state_perm_r2: 0, state_perm_r3: 0,
          state_perm_w0: 0, state_perm_w1: 0, state_perm_w2: 0, state_perm_w3: 0,
          state_perm_x0: 0, state_perm_x1: 0, state_perm_x2: 0, state_perm_x3: 0,
          state_perm_u0: 0, state_perm_u1: 0, state_perm_u2: 0, state_perm_u3: 0
        } do
          fill_idx = fill_vpn[1..0]
          fill_e0 = fill_en & (fill_idx == lit(0, width: 2))
          fill_e1 = fill_en & (fill_idx == lit(1, width: 2))
          fill_e2 = fill_en & (fill_idx == lit(2, width: 2))
          fill_e3 = fill_en & (fill_idx == lit(3, width: 2))

          state_valid0 <= mux(flush, lit(0, width: 1), mux(fill_e0, lit(1, width: 1), state_valid0))
          state_valid1 <= mux(flush, lit(0, width: 1), mux(fill_e1, lit(1, width: 1), state_valid1))
          state_valid2 <= mux(flush, lit(0, width: 1), mux(fill_e2, lit(1, width: 1), state_valid2))
          state_valid3 <= mux(flush, lit(0, width: 1), mux(fill_e3, lit(1, width: 1), state_valid3))

          state_vpn0 <= mux(fill_e0, fill_vpn, state_vpn0)
          state_vpn1 <= mux(fill_e1, fill_vpn, state_vpn1)
          state_vpn2 <= mux(fill_e2, fill_vpn, state_vpn2)
          state_vpn3 <= mux(fill_e3, fill_vpn, state_vpn3)

          state_root_ppn0 <= mux(fill_e0, fill_root_ppn, state_root_ppn0)
          state_root_ppn1 <= mux(fill_e1, fill_root_ppn, state_root_ppn1)
          state_root_ppn2 <= mux(fill_e2, fill_root_ppn, state_root_ppn2)
          state_root_ppn3 <= mux(fill_e3, fill_root_ppn, state_root_ppn3)

          state_ppn0 <= mux(fill_e0, fill_ppn, state_ppn0)
          state_ppn1 <= mux(fill_e1, fill_ppn, state_ppn1)
          state_ppn2 <= mux(fill_e2, fill_ppn, state_ppn2)
          state_ppn3 <= mux(fill_e3, fill_ppn, state_ppn3)

          state_perm_r0 <= mux(fill_e0, fill_perm_r, state_perm_r0)
          state_perm_r1 <= mux(fill_e1, fill_perm_r, state_perm_r1)
          state_perm_r2 <= mux(fill_e2, fill_perm_r, state_perm_r2)
          state_perm_r3 <= mux(fill_e3, fill_perm_r, state_perm_r3)

          state_perm_w0 <= mux(fill_e0, fill_perm_w, state_perm_w0)
          state_perm_w1 <= mux(fill_e1, fill_perm_w, state_perm_w1)
          state_perm_w2 <= mux(fill_e2, fill_perm_w, state_perm_w2)
          state_perm_w3 <= mux(fill_e3, fill_perm_w, state_perm_w3)

          state_perm_x0 <= mux(fill_e0, fill_perm_x, state_perm_x0)
          state_perm_x1 <= mux(fill_e1, fill_perm_x, state_perm_x1)
          state_perm_x2 <= mux(fill_e2, fill_perm_x, state_perm_x2)
          state_perm_x3 <= mux(fill_e3, fill_perm_x, state_perm_x3)

          state_perm_u0 <= mux(fill_e0, fill_perm_u, state_perm_u0)
          state_perm_u1 <= mux(fill_e1, fill_perm_u, state_perm_u1)
          state_perm_u2 <= mux(fill_e2, fill_perm_u, state_perm_u2)
          state_perm_u3 <= mux(fill_e3, fill_perm_u, state_perm_u3)
        end

        behavior do
          lookup_idx = lookup_vpn[1..0]
          sel_valid = local(:sel_valid,
                            mux(lookup_idx == lit(0, width: 2), state_valid0,
                                mux(lookup_idx == lit(1, width: 2), state_valid1,
                                    mux(lookup_idx == lit(2, width: 2), state_valid2, state_valid3))),
                            width: 1)
          sel_vpn = local(:sel_vpn,
                          mux(lookup_idx == lit(0, width: 2), state_vpn0,
                              mux(lookup_idx == lit(1, width: 2), state_vpn1,
                                  mux(lookup_idx == lit(2, width: 2), state_vpn2, state_vpn3))),
                          width: 20)
          sel_root = local(:sel_root,
                           mux(lookup_idx == lit(0, width: 2), state_root_ppn0,
                               mux(lookup_idx == lit(1, width: 2), state_root_ppn1,
                                   mux(lookup_idx == lit(2, width: 2), state_root_ppn2, state_root_ppn3))),
                           width: 20)
          sel_ppn = local(:sel_ppn,
                          mux(lookup_idx == lit(0, width: 2), state_ppn0,
                              mux(lookup_idx == lit(1, width: 2), state_ppn1,
                                  mux(lookup_idx == lit(2, width: 2), state_ppn2, state_ppn3))),
                          width: 20)
          sel_perm_r = local(:sel_perm_r,
                             mux(lookup_idx == lit(0, width: 2), state_perm_r0,
                                 mux(lookup_idx == lit(1, width: 2), state_perm_r1,
                                     mux(lookup_idx == lit(2, width: 2), state_perm_r2, state_perm_r3))),
                             width: 1)
          sel_perm_w = local(:sel_perm_w,
                             mux(lookup_idx == lit(0, width: 2), state_perm_w0,
                                 mux(lookup_idx == lit(1, width: 2), state_perm_w1,
                                     mux(lookup_idx == lit(2, width: 2), state_perm_w2, state_perm_w3))),
                             width: 1)
          sel_perm_x = local(:sel_perm_x,
                             mux(lookup_idx == lit(0, width: 2), state_perm_x0,
                                 mux(lookup_idx == lit(1, width: 2), state_perm_x1,
                                     mux(lookup_idx == lit(2, width: 2), state_perm_x2, state_perm_x3))),
                             width: 1)
          sel_perm_u = local(:sel_perm_u,
                             mux(lookup_idx == lit(0, width: 2), state_perm_u0,
                                 mux(lookup_idx == lit(1, width: 2), state_perm_u1,
                                     mux(lookup_idx == lit(2, width: 2), state_perm_u2, state_perm_u3))),
                             width: 1)
          entry_match = local(:entry_match,
                              sel_valid & lookup_en &
                              (sel_vpn == lookup_vpn) &
                              (sel_root == lookup_root_ppn),
                              width: 1)
          hit <= entry_match
          ppn <= mux(entry_match, sel_ppn, lit(0, width: 20))
          perm_r <= mux(entry_match, sel_perm_r, lit(0, width: 1))
          perm_w <= mux(entry_match, sel_perm_w, lit(0, width: 1))
          perm_x <= mux(entry_match, sel_perm_x, lit(0, width: 1))
          perm_u <= mux(entry_match, sel_perm_u, lit(0, width: 1))
        end
      end
    end
  end
end
