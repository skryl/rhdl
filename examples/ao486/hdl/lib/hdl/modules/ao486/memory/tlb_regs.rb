# frozen_string_literal: true

class TlbRegs < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: tlb_regs

  def self._import_decl_kinds
    {
      __VdfgRegularize_hd7f60667_0_0: :logic,
      __VdfgRegularize_hd7f60667_0_1: :logic,
      __VdfgRegularize_hd7f60667_0_10: :logic,
      __VdfgRegularize_hd7f60667_0_11: :logic,
      __VdfgRegularize_hd7f60667_0_12: :logic,
      __VdfgRegularize_hd7f60667_0_13: :logic,
      __VdfgRegularize_hd7f60667_0_14: :logic,
      __VdfgRegularize_hd7f60667_0_15: :logic,
      __VdfgRegularize_hd7f60667_0_16: :logic,
      __VdfgRegularize_hd7f60667_0_17: :logic,
      __VdfgRegularize_hd7f60667_0_18: :logic,
      __VdfgRegularize_hd7f60667_0_19: :logic,
      __VdfgRegularize_hd7f60667_0_2: :logic,
      __VdfgRegularize_hd7f60667_0_20: :logic,
      __VdfgRegularize_hd7f60667_0_21: :logic,
      __VdfgRegularize_hd7f60667_0_22: :logic,
      __VdfgRegularize_hd7f60667_0_23: :logic,
      __VdfgRegularize_hd7f60667_0_24: :logic,
      __VdfgRegularize_hd7f60667_0_25: :logic,
      __VdfgRegularize_hd7f60667_0_26: :logic,
      __VdfgRegularize_hd7f60667_0_27: :logic,
      __VdfgRegularize_hd7f60667_0_28: :logic,
      __VdfgRegularize_hd7f60667_0_29: :logic,
      __VdfgRegularize_hd7f60667_0_3: :logic,
      __VdfgRegularize_hd7f60667_0_4: :logic,
      __VdfgRegularize_hd7f60667_0_5: :logic,
      __VdfgRegularize_hd7f60667_0_6: :logic,
      __VdfgRegularize_hd7f60667_0_7: :logic,
      __VdfgRegularize_hd7f60667_0_8: :logic,
      __VdfgRegularize_hd7f60667_0_9: :logic,
      _unused_ok: :wire,
      full: :wire,
      plru: :reg,
      selected: :wire,
      tlb0: :reg,
      tlb0_ena: :wire,
      tlb0_sel: :wire,
      tlb0_tlbflush: :wire,
      tlb0_write: :wire,
      tlb1: :reg,
      tlb10: :reg,
      tlb10_ena: :wire,
      tlb10_sel: :wire,
      tlb10_tlbflush: :wire,
      tlb10_write: :wire,
      tlb11: :reg,
      tlb11_ena: :wire,
      tlb11_sel: :wire,
      tlb11_tlbflush: :wire,
      tlb11_write: :wire,
      tlb12: :reg,
      tlb12_ena: :wire,
      tlb12_sel: :wire,
      tlb12_tlbflush: :wire,
      tlb12_write: :wire,
      tlb13: :reg,
      tlb13_ena: :wire,
      tlb13_sel: :wire,
      tlb13_tlbflush: :wire,
      tlb13_write: :wire,
      tlb14: :reg,
      tlb14_ena: :wire,
      tlb14_sel: :wire,
      tlb14_tlbflush: :wire,
      tlb14_write: :wire,
      tlb15: :reg,
      tlb15_ena: :wire,
      tlb15_sel: :wire,
      tlb15_tlbflush: :wire,
      tlb15_write: :wire,
      tlb16: :reg,
      tlb16_ena: :wire,
      tlb16_sel: :wire,
      tlb16_tlbflush: :wire,
      tlb16_write: :wire,
      tlb17: :reg,
      tlb17_ena: :wire,
      tlb17_sel: :wire,
      tlb17_tlbflush: :wire,
      tlb17_write: :wire,
      tlb18: :reg,
      tlb18_ena: :wire,
      tlb18_sel: :wire,
      tlb18_tlbflush: :wire,
      tlb18_write: :wire,
      tlb19: :reg,
      tlb19_ena: :wire,
      tlb19_sel: :wire,
      tlb19_tlbflush: :wire,
      tlb19_write: :wire,
      tlb1_ena: :wire,
      tlb1_sel: :wire,
      tlb1_tlbflush: :wire,
      tlb1_write: :wire,
      tlb2: :reg,
      tlb20: :reg,
      tlb20_ena: :wire,
      tlb20_sel: :wire,
      tlb20_tlbflush: :wire,
      tlb20_write: :wire,
      tlb21: :reg,
      tlb21_ena: :wire,
      tlb21_sel: :wire,
      tlb21_tlbflush: :wire,
      tlb21_write: :wire,
      tlb22: :reg,
      tlb22_ena: :wire,
      tlb22_sel: :wire,
      tlb22_tlbflush: :wire,
      tlb22_write: :wire,
      tlb23: :reg,
      tlb23_ena: :wire,
      tlb23_sel: :wire,
      tlb23_tlbflush: :wire,
      tlb23_write: :wire,
      tlb24: :reg,
      tlb24_ena: :wire,
      tlb24_sel: :wire,
      tlb24_tlbflush: :wire,
      tlb24_write: :wire,
      tlb25: :reg,
      tlb25_ena: :wire,
      tlb25_sel: :wire,
      tlb25_tlbflush: :wire,
      tlb25_write: :wire,
      tlb26: :reg,
      tlb26_ena: :wire,
      tlb26_sel: :wire,
      tlb26_tlbflush: :wire,
      tlb26_write: :wire,
      tlb27: :reg,
      tlb27_ena: :wire,
      tlb27_sel: :wire,
      tlb27_tlbflush: :wire,
      tlb27_write: :wire,
      tlb28: :reg,
      tlb28_ena: :wire,
      tlb28_sel: :wire,
      tlb28_tlbflush: :wire,
      tlb28_write: :wire,
      tlb29: :reg,
      tlb29_ena: :wire,
      tlb29_sel: :wire,
      tlb29_tlbflush: :wire,
      tlb29_write: :wire,
      tlb2_ena: :wire,
      tlb2_sel: :wire,
      tlb2_tlbflush: :wire,
      tlb2_write: :wire,
      tlb3: :reg,
      tlb30: :reg,
      tlb30_ena: :wire,
      tlb30_sel: :wire,
      tlb30_tlbflush: :wire,
      tlb30_write: :wire,
      tlb31: :reg,
      tlb31_ena: :wire,
      tlb31_sel: :wire,
      tlb31_tlbflush: :wire,
      tlb31_write: :wire,
      tlb3_ena: :wire,
      tlb3_sel: :wire,
      tlb3_tlbflush: :wire,
      tlb3_write: :wire,
      tlb4: :reg,
      tlb4_ena: :wire,
      tlb4_sel: :wire,
      tlb4_tlbflush: :wire,
      tlb4_write: :wire,
      tlb5: :reg,
      tlb5_ena: :wire,
      tlb5_sel: :wire,
      tlb5_tlbflush: :wire,
      tlb5_write: :wire,
      tlb6: :reg,
      tlb6_ena: :wire,
      tlb6_sel: :wire,
      tlb6_tlbflush: :wire,
      tlb6_write: :wire,
      tlb7: :reg,
      tlb7_ena: :wire,
      tlb7_sel: :wire,
      tlb7_tlbflush: :wire,
      tlb7_write: :wire,
      tlb8: :reg,
      tlb8_ena: :wire,
      tlb8_sel: :wire,
      tlb8_tlbflush: :wire,
      tlb8_write: :wire,
      tlb9: :reg,
      tlb9_ena: :wire,
      tlb9_sel: :wire,
      tlb9_tlbflush: :wire,
      tlb9_write: :wire,
      translate_valid_but_not_dirty: :wire,
      write_data: :wire
    }
  end

  # Parameters

  generic :TLB31_MASK, default: "31'h40004045"
  generic :TLB31_VALUE, default: "31'h0"
  generic :TLB30_MASK, default: "31'h40004045"
  generic :TLB30_VALUE, default: "31'h40000000"
  generic :TLB29_MASK, default: "31'h20004045"
  generic :TLB29_VALUE, default: "31'h4000"
  generic :TLB28_MASK, default: "31'h20004045"
  generic :TLB28_VALUE, default: "31'h20004000"
  generic :TLB27_MASK, default: "31'h10002045"
  generic :TLB27_VALUE, default: "31'h40"
  generic :TLB26_MASK, default: "31'h10002045"
  generic :TLB26_VALUE, default: "31'h10000040"
  generic :TLB25_MASK, default: "31'h8002045"
  generic :TLB25_VALUE, default: "31'h2040"
  generic :TLB24_MASK, default: "31'h8002045"
  generic :TLB24_VALUE, default: "31'h8002040"
  generic :TLB23_MASK, default: "31'h4001025"
  generic :TLB23_VALUE, default: "31'h4"
  generic :TLB22_MASK, default: "31'h4001025"
  generic :TLB22_VALUE, default: "31'h4000004"
  generic :TLB21_MASK, default: "31'h2001025"
  generic :TLB21_VALUE, default: "31'h1004"
  generic :TLB20_MASK, default: "31'h2001025"
  generic :TLB20_VALUE, default: "31'h2001004"
  generic :TLB19_MASK, default: "31'h1000825"
  generic :TLB19_VALUE, default: "31'h24"
  generic :TLB18_MASK, default: "31'h1000825"
  generic :TLB18_VALUE, default: "31'h1000024"
  generic :TLB17_MASK, default: "31'h800825"
  generic :TLB17_VALUE, default: "31'h824"
  generic :TLB16_MASK, default: "31'h800825"
  generic :TLB16_VALUE, default: "31'h800824"
  generic :TLB15_MASK, default: "31'h400413"
  generic :TLB15_VALUE, default: "31'h1"
  generic :TLB14_MASK, default: "31'h400413"
  generic :TLB14_VALUE, default: "31'h400001"
  generic :TLB13_MASK, default: "31'h200413"
  generic :TLB13_VALUE, default: "31'h401"
  generic :TLB12_MASK, default: "31'h200413"
  generic :TLB12_VALUE, default: "31'h200401"
  generic :TLB11_MASK, default: "31'h100213"
  generic :TLB11_VALUE, default: "31'h11"
  generic :TLB10_MASK, default: "31'h100213"
  generic :TLB10_VALUE, default: "31'h100011"
  generic :TLB9_MASK, default: "31'h80213"
  generic :TLB9_VALUE, default: "31'h211"
  generic :TLB8_MASK, default: "31'h80213"
  generic :TLB8_VALUE, default: "31'h80211"
  generic :TLB7_MASK, default: "31'h4010b"
  generic :TLB7_VALUE, default: "31'h3"
  generic :TLB6_MASK, default: "31'h4010b"
  generic :TLB6_VALUE, default: "31'h40003"
  generic :TLB5_MASK, default: "31'h2010b"
  generic :TLB5_VALUE, default: "31'h103"
  generic :TLB4_MASK, default: "31'h2010b"
  generic :TLB4_VALUE, default: "31'h20103"
  generic :TLB3_MASK, default: "31'h1008b"
  generic :TLB3_VALUE, default: "31'hb"
  generic :TLB2_MASK, default: "31'h1008b"
  generic :TLB2_VALUE, default: "31'h1000b"
  generic :TLB1_MASK, default: "31'h808b"
  generic :TLB1_VALUE, default: "31'h8b"
  generic :TLB0_MASK, default: "31'h808b"
  generic :TLB0_VALUE, default: "31'h808b"

  # Ports

  input :clk
  input :rst_n
  input :tlbflushsingle_do
  input :tlbflushsingle_address, width: 32
  input :tlbflushall_do
  input :rw
  input :tlbregs_write_do
  input :tlbregs_write_linear, width: 32
  input :tlbregs_write_physical, width: 32
  input :tlbregs_write_pwt
  input :tlbregs_write_pcd
  input :tlbregs_write_combined_rw
  input :tlbregs_write_combined_su
  input :translate_do
  input :translate_linear, width: 32
  output :translate_valid
  output :translate_physical, width: 32
  output :translate_pwt
  output :translate_pcd
  output :translate_combined_rw
  output :translate_combined_su

  # Signals

  signal :__VdfgRegularize_hd7f60667_0_0
  signal :__VdfgRegularize_hd7f60667_0_1
  signal :__VdfgRegularize_hd7f60667_0_10
  signal :__VdfgRegularize_hd7f60667_0_11
  signal :__VdfgRegularize_hd7f60667_0_12
  signal :__VdfgRegularize_hd7f60667_0_13
  signal :__VdfgRegularize_hd7f60667_0_14
  signal :__VdfgRegularize_hd7f60667_0_15
  signal :__VdfgRegularize_hd7f60667_0_16
  signal :__VdfgRegularize_hd7f60667_0_17
  signal :__VdfgRegularize_hd7f60667_0_18
  signal :__VdfgRegularize_hd7f60667_0_19
  signal :__VdfgRegularize_hd7f60667_0_2
  signal :__VdfgRegularize_hd7f60667_0_20
  signal :__VdfgRegularize_hd7f60667_0_21
  signal :__VdfgRegularize_hd7f60667_0_22
  signal :__VdfgRegularize_hd7f60667_0_23
  signal :__VdfgRegularize_hd7f60667_0_24
  signal :__VdfgRegularize_hd7f60667_0_25
  signal :__VdfgRegularize_hd7f60667_0_26
  signal :__VdfgRegularize_hd7f60667_0_27
  signal :__VdfgRegularize_hd7f60667_0_28
  signal :__VdfgRegularize_hd7f60667_0_29
  signal :__VdfgRegularize_hd7f60667_0_3
  signal :__VdfgRegularize_hd7f60667_0_4
  signal :__VdfgRegularize_hd7f60667_0_5
  signal :__VdfgRegularize_hd7f60667_0_6
  signal :__VdfgRegularize_hd7f60667_0_7
  signal :__VdfgRegularize_hd7f60667_0_8
  signal :__VdfgRegularize_hd7f60667_0_9
  signal :_unused_ok
  signal :full
  signal :plru, width: 31
  signal :selected, width: 46
  signal :tlb0, width: 46
  signal :tlb0_ena
  signal :tlb0_sel
  signal :tlb0_tlbflush
  signal :tlb0_write
  signal :tlb1, width: 46
  signal :tlb10, width: 46
  signal :tlb10_ena
  signal :tlb10_sel
  signal :tlb10_tlbflush
  signal :tlb10_write
  signal :tlb11, width: 46
  signal :tlb11_ena
  signal :tlb11_sel
  signal :tlb11_tlbflush
  signal :tlb11_write
  signal :tlb12, width: 46
  signal :tlb12_ena
  signal :tlb12_sel
  signal :tlb12_tlbflush
  signal :tlb12_write
  signal :tlb13, width: 46
  signal :tlb13_ena
  signal :tlb13_sel
  signal :tlb13_tlbflush
  signal :tlb13_write
  signal :tlb14, width: 46
  signal :tlb14_ena
  signal :tlb14_sel
  signal :tlb14_tlbflush
  signal :tlb14_write
  signal :tlb15, width: 46
  signal :tlb15_ena
  signal :tlb15_sel
  signal :tlb15_tlbflush
  signal :tlb15_write
  signal :tlb16, width: 46
  signal :tlb16_ena
  signal :tlb16_sel
  signal :tlb16_tlbflush
  signal :tlb16_write
  signal :tlb17, width: 46
  signal :tlb17_ena
  signal :tlb17_sel
  signal :tlb17_tlbflush
  signal :tlb17_write
  signal :tlb18, width: 46
  signal :tlb18_ena
  signal :tlb18_sel
  signal :tlb18_tlbflush
  signal :tlb18_write
  signal :tlb19, width: 46
  signal :tlb19_ena
  signal :tlb19_sel
  signal :tlb19_tlbflush
  signal :tlb19_write
  signal :tlb1_ena
  signal :tlb1_sel
  signal :tlb1_tlbflush
  signal :tlb1_write
  signal :tlb2, width: 46
  signal :tlb20, width: 46
  signal :tlb20_ena
  signal :tlb20_sel
  signal :tlb20_tlbflush
  signal :tlb20_write
  signal :tlb21, width: 46
  signal :tlb21_ena
  signal :tlb21_sel
  signal :tlb21_tlbflush
  signal :tlb21_write
  signal :tlb22, width: 46
  signal :tlb22_ena
  signal :tlb22_sel
  signal :tlb22_tlbflush
  signal :tlb22_write
  signal :tlb23, width: 46
  signal :tlb23_ena
  signal :tlb23_sel
  signal :tlb23_tlbflush
  signal :tlb23_write
  signal :tlb24, width: 46
  signal :tlb24_ena
  signal :tlb24_sel
  signal :tlb24_tlbflush
  signal :tlb24_write
  signal :tlb25, width: 46
  signal :tlb25_ena
  signal :tlb25_sel
  signal :tlb25_tlbflush
  signal :tlb25_write
  signal :tlb26, width: 46
  signal :tlb26_ena
  signal :tlb26_sel
  signal :tlb26_tlbflush
  signal :tlb26_write
  signal :tlb27, width: 46
  signal :tlb27_ena
  signal :tlb27_sel
  signal :tlb27_tlbflush
  signal :tlb27_write
  signal :tlb28, width: 46
  signal :tlb28_ena
  signal :tlb28_sel
  signal :tlb28_tlbflush
  signal :tlb28_write
  signal :tlb29, width: 46
  signal :tlb29_ena
  signal :tlb29_sel
  signal :tlb29_tlbflush
  signal :tlb29_write
  signal :tlb2_ena
  signal :tlb2_sel
  signal :tlb2_tlbflush
  signal :tlb2_write
  signal :tlb3, width: 46
  signal :tlb30, width: 46
  signal :tlb30_ena
  signal :tlb30_sel
  signal :tlb30_tlbflush
  signal :tlb30_write
  signal :tlb31, width: 46
  signal :tlb31_ena
  signal :tlb31_sel
  signal :tlb31_tlbflush
  signal :tlb31_write
  signal :tlb3_ena
  signal :tlb3_sel
  signal :tlb3_tlbflush
  signal :tlb3_write
  signal :tlb4, width: 46
  signal :tlb4_ena
  signal :tlb4_sel
  signal :tlb4_tlbflush
  signal :tlb4_write
  signal :tlb5, width: 46
  signal :tlb5_ena
  signal :tlb5_sel
  signal :tlb5_tlbflush
  signal :tlb5_write
  signal :tlb6, width: 46
  signal :tlb6_ena
  signal :tlb6_sel
  signal :tlb6_tlbflush
  signal :tlb6_write
  signal :tlb7, width: 46
  signal :tlb7_ena
  signal :tlb7_sel
  signal :tlb7_tlbflush
  signal :tlb7_write
  signal :tlb8, width: 46
  signal :tlb8_ena
  signal :tlb8_sel
  signal :tlb8_tlbflush
  signal :tlb8_write
  signal :tlb9, width: 46
  signal :tlb9_ena
  signal :tlb9_sel
  signal :tlb9_tlbflush
  signal :tlb9_write
  signal :translate_valid_but_not_dirty
  signal :write_data, width: 46

  # Assignments

  assign :translate_valid_but_not_dirty,
    (
        sig(:selected, width: 46)[42] &
        (
            (
              ~sig(:selected, width: 46)[45]
            ) &
            sig(:rw, width: 1)
        )
    )
  assign :selected,
    mux(
      sig(:tlb0_sel, width: 1),
      sig(:tlb0, width: 46),
      mux(
        sig(:tlb1_sel, width: 1),
        sig(:tlb1, width: 46),
        mux(
          sig(:tlb2_sel, width: 1),
          sig(:tlb2, width: 46),
          mux(
            sig(:tlb3_sel, width: 1),
            sig(:tlb3, width: 46),
            mux(
              sig(:tlb4_sel, width: 1),
              sig(:tlb4, width: 46),
              mux(
                sig(:tlb5_sel, width: 1),
                sig(:tlb5, width: 46),
                mux(
                  sig(:tlb6_sel, width: 1),
                  sig(:tlb6, width: 46),
                  mux(
                    sig(:tlb7_sel, width: 1),
                    sig(:tlb7, width: 46),
                    mux(
                      sig(:tlb8_sel, width: 1),
                      sig(:tlb8, width: 46),
                      mux(
                        sig(:tlb9_sel, width: 1),
                        sig(:tlb9, width: 46),
                        mux(
                          sig(:tlb10_sel, width: 1),
                          sig(:tlb10, width: 46),
                          mux(
                            sig(:tlb11_sel, width: 1),
                            sig(:tlb11, width: 46),
                            mux(
                              sig(:tlb12_sel, width: 1),
                              sig(:tlb12, width: 46),
                              mux(
                                sig(:tlb13_sel, width: 1),
                                sig(:tlb13, width: 46),
                                mux(
                                  sig(:tlb14_sel, width: 1),
                                  sig(:tlb14, width: 46),
                                  mux(
                                    sig(:tlb15_sel, width: 1),
                                    sig(:tlb15, width: 46),
                                    mux(
                                      sig(:tlb16_sel, width: 1),
                                      sig(:tlb16, width: 46),
                                      mux(
                                        sig(:tlb17_sel, width: 1),
                                        sig(:tlb17, width: 46),
                                        mux(
                                          sig(:tlb18_sel, width: 1),
                                          sig(:tlb18, width: 46),
                                          mux(
                                            sig(:tlb19_sel, width: 1),
                                            sig(:tlb19, width: 46),
                                            mux(
                                              sig(:tlb20_sel, width: 1),
                                              sig(:tlb20, width: 46),
                                              mux(
                                                sig(:tlb21_sel, width: 1),
                                                sig(:tlb21, width: 46),
                                                mux(
                                                  sig(:tlb22_sel, width: 1),
                                                  sig(:tlb22, width: 46),
                                                  mux(
                                                    sig(:tlb23_sel, width: 1),
                                                    sig(:tlb23, width: 46),
                                                    mux(
                                                      sig(:tlb24_sel, width: 1),
                                                      sig(:tlb24, width: 46),
                                                      mux(
                                                        sig(:tlb25_sel, width: 1),
                                                        sig(:tlb25, width: 46),
                                                        mux(
                                                          sig(:tlb26_sel, width: 1),
                                                          sig(:tlb26, width: 46),
                                                          mux(
                                                            sig(:tlb27_sel, width: 1),
                                                            sig(:tlb27, width: 46),
                                                            mux(
                                                              sig(:tlb28_sel, width: 1),
                                                              sig(:tlb28, width: 46),
                                                              mux(
                                                                sig(:tlb29_sel, width: 1),
                                                                sig(:tlb29, width: 46),
                                                                mux(
                                                                  sig(:tlb30_sel, width: 1),
                                                                  sig(:tlb30, width: 46),
                                                                  mux(
                                                                    sig(:tlb31_sel, width: 1),
                                                                    sig(:tlb31, width: 46),
                                                                    lit(0, width: 46, base: "h", signed: false)
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :tlb0_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb0, width: 46)[19..0]
            ) &
            sig(:tlb1_ena, width: 1)
        )
    )
  assign :tlb1_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb1, width: 46)[19..0]
            ) &
            sig(:tlb1, width: 46)[42]
        )
    )
  assign :tlb2_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb2, width: 46)[19..0]
            ) &
            sig(:tlb2, width: 46)[42]
        )
    )
  assign :tlb3_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb3, width: 46)[19..0]
            ) &
            sig(:tlb3, width: 46)[42]
        )
    )
  assign :tlb4_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb4, width: 46)[19..0]
            ) &
            sig(:tlb4, width: 46)[42]
        )
    )
  assign :tlb5_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb5, width: 46)[19..0]
            ) &
            sig(:tlb5, width: 46)[42]
        )
    )
  assign :tlb6_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb6, width: 46)[19..0]
            ) &
            sig(:tlb6, width: 46)[42]
        )
    )
  assign :tlb7_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb7, width: 46)[19..0]
            ) &
            sig(:tlb7, width: 46)[42]
        )
    )
  assign :tlb8_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb8, width: 46)[19..0]
            ) &
            sig(:tlb8, width: 46)[42]
        )
    )
  assign :tlb9_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb9, width: 46)[19..0]
            ) &
            sig(:tlb9, width: 46)[42]
        )
    )
  assign :tlb10_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb10, width: 46)[19..0]
            ) &
            sig(:tlb10, width: 46)[42]
        )
    )
  assign :tlb11_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb11, width: 46)[19..0]
            ) &
            sig(:tlb11, width: 46)[42]
        )
    )
  assign :tlb12_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb12, width: 46)[19..0]
            ) &
            sig(:tlb12, width: 46)[42]
        )
    )
  assign :tlb13_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb13, width: 46)[19..0]
            ) &
            sig(:tlb13, width: 46)[42]
        )
    )
  assign :tlb14_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb14, width: 46)[19..0]
            ) &
            sig(:tlb14, width: 46)[42]
        )
    )
  assign :tlb15_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb15, width: 46)[19..0]
            ) &
            sig(:tlb15, width: 46)[42]
        )
    )
  assign :tlb16_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb16, width: 46)[19..0]
            ) &
            sig(:tlb16, width: 46)[42]
        )
    )
  assign :tlb17_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb17, width: 46)[19..0]
            ) &
            sig(:tlb17, width: 46)[42]
        )
    )
  assign :tlb18_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb18, width: 46)[19..0]
            ) &
            sig(:tlb18, width: 46)[42]
        )
    )
  assign :tlb19_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb19, width: 46)[19..0]
            ) &
            sig(:tlb19, width: 46)[42]
        )
    )
  assign :tlb20_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb20, width: 46)[19..0]
            ) &
            sig(:tlb20, width: 46)[42]
        )
    )
  assign :tlb21_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb21, width: 46)[19..0]
            ) &
            sig(:tlb21, width: 46)[42]
        )
    )
  assign :tlb22_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb22, width: 46)[19..0]
            ) &
            sig(:tlb22, width: 46)[42]
        )
    )
  assign :tlb23_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb23, width: 46)[19..0]
            ) &
            sig(:tlb23, width: 46)[42]
        )
    )
  assign :tlb24_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb24, width: 46)[19..0]
            ) &
            sig(:tlb24, width: 46)[42]
        )
    )
  assign :tlb25_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb25, width: 46)[19..0]
            ) &
            sig(:tlb25, width: 46)[42]
        )
    )
  assign :tlb26_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb26, width: 46)[19..0]
            ) &
            sig(:tlb26, width: 46)[42]
        )
    )
  assign :tlb27_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb27, width: 46)[19..0]
            ) &
            sig(:tlb27, width: 46)[42]
        )
    )
  assign :tlb28_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb28, width: 46)[19..0]
            ) &
            sig(:tlb28, width: 46)[42]
        )
    )
  assign :tlb29_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb29, width: 46)[19..0]
            ) &
            sig(:tlb29, width: 46)[42]
        )
    )
  assign :tlb30_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb30, width: 46)[19..0]
            ) &
            sig(:tlb30, width: 46)[42]
        )
    )
  assign :tlb31_sel,
    (
        sig(:translate_do, width: 1) &
        (
            (
                sig(:translate_linear, width: 32)[31..12] ==
                sig(:tlb31, width: 46)[19..0]
            ) &
            sig(:tlb31, width: 46)[42]
        )
    )
  assign :translate_valid,
    (
        sig(:selected, width: 46)[42] &
        (
            (
              ~sig(:rw, width: 1)
            ) |
            sig(:selected, width: 46)[45]
        )
    )
  assign :translate_physical,
    mux(
      sig(:translate_valid, width: 1),
      sig(:selected, width: 46)[39..20].concat(
        sig(:translate_linear, width: 32)[11..0]
      ),
      sig(:translate_linear, width: 32)
    )
  assign :translate_pwt,
    sig(:selected, width: 46)[40]
  assign :translate_pcd,
    sig(:selected, width: 46)[41]
  assign :translate_combined_rw,
    sig(:selected, width: 46)[43]
  assign :translate_combined_su,
    sig(:selected, width: 46)[44]
  assign :tlb1_ena,
    sig(:tlb0, width: 46)[42]
  assign :tlb2_ena,
    (
        sig(:tlb1_ena, width: 1) &
        sig(:tlb1, width: 46)[42]
    )
  assign :tlb3_ena,
    (
        sig(:tlb2_ena, width: 1) &
        sig(:tlb2, width: 46)[42]
    )
  assign :tlb4_ena,
    (
        sig(:tlb3_ena, width: 1) &
        sig(:tlb3, width: 46)[42]
    )
  assign :tlb5_ena,
    (
        sig(:tlb4_ena, width: 1) &
        sig(:tlb4, width: 46)[42]
    )
  assign :tlb6_ena,
    (
        sig(:tlb5_ena, width: 1) &
        sig(:tlb5, width: 46)[42]
    )
  assign :tlb7_ena,
    (
        sig(:tlb6_ena, width: 1) &
        sig(:tlb6, width: 46)[42]
    )
  assign :tlb8_ena,
    (
        sig(:tlb7_ena, width: 1) &
        sig(:tlb7, width: 46)[42]
    )
  assign :tlb9_ena,
    (
        sig(:tlb8_ena, width: 1) &
        sig(:tlb8, width: 46)[42]
    )
  assign :tlb10_ena,
    (
        sig(:tlb9_ena, width: 1) &
        sig(:tlb9, width: 46)[42]
    )
  assign :tlb11_ena,
    (
        sig(:tlb10_ena, width: 1) &
        sig(:tlb10, width: 46)[42]
    )
  assign :tlb12_ena,
    (
        sig(:tlb11_ena, width: 1) &
        sig(:tlb11, width: 46)[42]
    )
  assign :tlb13_ena,
    (
        sig(:tlb12_ena, width: 1) &
        sig(:tlb12, width: 46)[42]
    )
  assign :tlb14_ena,
    (
        sig(:tlb13_ena, width: 1) &
        sig(:tlb13, width: 46)[42]
    )
  assign :tlb15_ena,
    (
        sig(:tlb14_ena, width: 1) &
        sig(:tlb14, width: 46)[42]
    )
  assign :tlb16_ena,
    (
        sig(:tlb15_ena, width: 1) &
        sig(:tlb15, width: 46)[42]
    )
  assign :tlb17_ena,
    (
        sig(:tlb16_ena, width: 1) &
        sig(:tlb16, width: 46)[42]
    )
  assign :tlb18_ena,
    (
        sig(:tlb17_ena, width: 1) &
        sig(:tlb17, width: 46)[42]
    )
  assign :tlb19_ena,
    (
        sig(:tlb18_ena, width: 1) &
        sig(:tlb18, width: 46)[42]
    )
  assign :tlb20_ena,
    (
        sig(:tlb19_ena, width: 1) &
        sig(:tlb19, width: 46)[42]
    )
  assign :tlb21_ena,
    (
        sig(:tlb20_ena, width: 1) &
        sig(:tlb20, width: 46)[42]
    )
  assign :tlb22_ena,
    (
        sig(:tlb21_ena, width: 1) &
        sig(:tlb21, width: 46)[42]
    )
  assign :tlb23_ena,
    (
        sig(:tlb22_ena, width: 1) &
        sig(:tlb22, width: 46)[42]
    )
  assign :tlb24_ena,
    (
        sig(:tlb23_ena, width: 1) &
        sig(:tlb23, width: 46)[42]
    )
  assign :tlb25_ena,
    (
        sig(:tlb24_ena, width: 1) &
        sig(:tlb24, width: 46)[42]
    )
  assign :tlb26_ena,
    (
        sig(:tlb25_ena, width: 1) &
        sig(:tlb25, width: 46)[42]
    )
  assign :tlb27_ena,
    (
        sig(:tlb26_ena, width: 1) &
        sig(:tlb26, width: 46)[42]
    )
  assign :tlb28_ena,
    (
        sig(:tlb27_ena, width: 1) &
        sig(:tlb27, width: 46)[42]
    )
  assign :tlb29_ena,
    (
        sig(:tlb28_ena, width: 1) &
        sig(:tlb28, width: 46)[42]
    )
  assign :tlb30_ena,
    (
        sig(:tlb29_ena, width: 1) &
        sig(:tlb29, width: 46)[42]
    )
  assign :tlb31_ena,
    (
        sig(:tlb30_ena, width: 1) &
        sig(:tlb30, width: 46)[42]
    )
  assign :full,
    (
        sig(:tlb31_ena, width: 1) &
        sig(:tlb31, width: 46)[42]
    )
  assign :tlb0_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
              ~sig(:tlb1_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[15]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_26, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_26,
    (
        (
          ~sig(:plru, width: 31)[7]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_27, width: 1)
    )
  assign :tlb1_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb1, width: 46)[42]
                ) &
                sig(:tlb1_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_26, width: 1) &
                sig(:plru, width: 31)[15]
            )
        )
    )
  assign :tlb2_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb2, width: 46)[42]
                ) &
                sig(:tlb2_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[16]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_0, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_0,
    (
        sig(:__VdfgRegularize_hd7f60667_0_27, width: 1) &
        sig(:plru, width: 31)[7]
    )
  assign :tlb3_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb3, width: 46)[42]
                ) &
                sig(:tlb3_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_0, width: 1) &
                sig(:plru, width: 31)[16]
            )
        )
    )
  assign :tlb4_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb4, width: 46)[42]
                ) &
                sig(:tlb4_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[17]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_25, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_25,
    (
        (
          ~sig(:plru, width: 31)[8]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_1, width: 1)
    )
  assign :tlb5_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb5, width: 46)[42]
                ) &
                sig(:tlb5_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_25, width: 1) &
                sig(:plru, width: 31)[17]
            )
        )
    )
  assign :tlb6_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb6, width: 46)[42]
                ) &
                sig(:tlb6_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[18]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_2, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_2,
    (
        sig(:__VdfgRegularize_hd7f60667_0_1, width: 1) &
        sig(:plru, width: 31)[8]
    )
  assign :tlb7_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb7, width: 46)[42]
                ) &
                sig(:tlb7_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_2, width: 1) &
                sig(:plru, width: 31)[18]
            )
        )
    )
  assign :tlb8_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb8, width: 46)[42]
                ) &
                sig(:tlb8_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[19]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_23, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_23,
    (
        (
          ~sig(:plru, width: 31)[9]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_24, width: 1)
    )
  assign :tlb9_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb9, width: 46)[42]
                ) &
                sig(:tlb9_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_23, width: 1) &
                sig(:plru, width: 31)[19]
            )
        )
    )
  assign :tlb10_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb10, width: 46)[42]
                ) &
                sig(:tlb10_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[20]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_4, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_4,
    (
        sig(:__VdfgRegularize_hd7f60667_0_24, width: 1) &
        sig(:plru, width: 31)[9]
    )
  assign :tlb11_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb11, width: 46)[42]
                ) &
                sig(:tlb11_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_4, width: 1) &
                sig(:plru, width: 31)[20]
            )
        )
    )
  assign :tlb12_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb12, width: 46)[42]
                ) &
                sig(:tlb12_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[21]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_22, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_22,
    (
        (
          ~sig(:plru, width: 31)[10]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_5, width: 1)
    )
  assign :tlb13_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb13, width: 46)[42]
                ) &
                sig(:tlb13_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_22, width: 1) &
                sig(:plru, width: 31)[21]
            )
        )
    )
  assign :tlb14_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb14, width: 46)[42]
                ) &
                sig(:tlb14_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[22]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_6, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_6,
    (
        sig(:__VdfgRegularize_hd7f60667_0_5, width: 1) &
        sig(:plru, width: 31)[10]
    )
  assign :tlb15_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb15, width: 46)[42]
                ) &
                sig(:tlb15_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_6, width: 1) &
                sig(:plru, width: 31)[22]
            )
        )
    )
  assign :tlb16_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb16, width: 46)[42]
                ) &
                sig(:tlb16_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[23]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_19, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_19,
    (
        (
          ~sig(:plru, width: 31)[11]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_20, width: 1)
    )
  assign :tlb17_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb17, width: 46)[42]
                ) &
                sig(:tlb17_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_19, width: 1) &
                sig(:plru, width: 31)[23]
            )
        )
    )
  assign :tlb18_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb18, width: 46)[42]
                ) &
                sig(:tlb18_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[24]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_8, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_8,
    (
        sig(:__VdfgRegularize_hd7f60667_0_20, width: 1) &
        sig(:plru, width: 31)[11]
    )
  assign :tlb19_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb19, width: 46)[42]
                ) &
                sig(:tlb19_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_8, width: 1) &
                sig(:plru, width: 31)[24]
            )
        )
    )
  assign :tlb20_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb20, width: 46)[42]
                ) &
                sig(:tlb20_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[25]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_18, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_18,
    (
        (
          ~sig(:plru, width: 31)[12]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_9, width: 1)
    )
  assign :tlb21_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb21, width: 46)[42]
                ) &
                sig(:tlb21_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_18, width: 1) &
                sig(:plru, width: 31)[25]
            )
        )
    )
  assign :tlb22_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb22, width: 46)[42]
                ) &
                sig(:tlb22_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[26]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_10, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_10,
    (
        sig(:__VdfgRegularize_hd7f60667_0_9, width: 1) &
        sig(:plru, width: 31)[12]
    )
  assign :tlb23_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb23, width: 46)[42]
                ) &
                sig(:tlb23_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_10, width: 1) &
                sig(:plru, width: 31)[26]
            )
        )
    )
  assign :tlb24_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb24, width: 46)[42]
                ) &
                sig(:tlb24_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[27]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_16, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_16,
    (
        (
          ~sig(:plru, width: 31)[13]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_17, width: 1)
    )
  assign :tlb25_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb25, width: 46)[42]
                ) &
                sig(:tlb25_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_16, width: 1) &
                sig(:plru, width: 31)[27]
            )
        )
    )
  assign :tlb26_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb26, width: 46)[42]
                ) &
                sig(:tlb26_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[28]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_12, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_12,
    (
        sig(:__VdfgRegularize_hd7f60667_0_17, width: 1) &
        sig(:plru, width: 31)[13]
    )
  assign :tlb27_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb27, width: 46)[42]
                ) &
                sig(:tlb27_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_12, width: 1) &
                sig(:plru, width: 31)[28]
            )
        )
    )
  assign :tlb28_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb28, width: 46)[42]
                ) &
                sig(:tlb28_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[29]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_15, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_15,
    (
        (
          ~sig(:plru, width: 31)[14]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_13, width: 1)
    )
  assign :tlb29_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb29, width: 46)[42]
                ) &
                sig(:tlb29_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_15, width: 1) &
                sig(:plru, width: 31)[29]
            )
        )
    )
  assign :tlb30_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb30, width: 46)[42]
                ) &
                sig(:tlb30_ena, width: 1)
            ) |
            (
                (
                  ~sig(:plru, width: 31)[30]
                ) &
                sig(:__VdfgRegularize_hd7f60667_0_14, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd7f60667_0_14,
    (
        sig(:__VdfgRegularize_hd7f60667_0_13, width: 1) &
        sig(:plru, width: 31)[14]
    )
  assign :tlb31_write,
    (
        sig(:tlbregs_write_do, width: 1) &
        (
            (
                (
                  ~sig(:tlb31, width: 46)[42]
                ) &
                sig(:tlb31_ena, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_hd7f60667_0_14, width: 1) &
                sig(:plru, width: 31)[30]
            )
        )
    )
  assign :tlb0_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb0, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb0_sel, width: 1)
        )
    )
  assign :tlb1_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb1, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb1_sel, width: 1)
        )
    )
  assign :tlb2_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb2, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb2_sel, width: 1)
        )
    )
  assign :tlb3_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb3, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb3_sel, width: 1)
        )
    )
  assign :tlb4_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb4, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb4_sel, width: 1)
        )
    )
  assign :tlb5_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb5, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb5_sel, width: 1)
        )
    )
  assign :tlb6_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb6, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb6_sel, width: 1)
        )
    )
  assign :tlb7_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb7, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb7_sel, width: 1)
        )
    )
  assign :tlb8_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb8, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb8_sel, width: 1)
        )
    )
  assign :tlb9_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb9, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb9_sel, width: 1)
        )
    )
  assign :tlb10_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb10, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb10_sel, width: 1)
        )
    )
  assign :tlb11_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb11, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb11_sel, width: 1)
        )
    )
  assign :tlb12_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb12, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb12_sel, width: 1)
        )
    )
  assign :tlb13_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb13, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb13_sel, width: 1)
        )
    )
  assign :tlb14_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb14, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb14_sel, width: 1)
        )
    )
  assign :tlb15_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb15, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb15_sel, width: 1)
        )
    )
  assign :tlb16_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb16, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb16_sel, width: 1)
        )
    )
  assign :tlb17_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb17, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb17_sel, width: 1)
        )
    )
  assign :tlb18_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb18, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb18_sel, width: 1)
        )
    )
  assign :tlb19_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb19, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb19_sel, width: 1)
        )
    )
  assign :tlb20_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb20, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb20_sel, width: 1)
        )
    )
  assign :tlb21_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb21, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb21_sel, width: 1)
        )
    )
  assign :tlb22_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb22, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb22_sel, width: 1)
        )
    )
  assign :tlb23_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb23, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb23_sel, width: 1)
        )
    )
  assign :tlb24_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb24, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb24_sel, width: 1)
        )
    )
  assign :tlb25_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb25, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb25_sel, width: 1)
        )
    )
  assign :tlb26_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb26, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb26_sel, width: 1)
        )
    )
  assign :tlb27_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb27, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb27_sel, width: 1)
        )
    )
  assign :tlb28_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb28, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb28_sel, width: 1)
        )
    )
  assign :tlb29_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb29, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb29_sel, width: 1)
        )
    )
  assign :tlb30_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb30, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb30_sel, width: 1)
        )
    )
  assign :tlb31_tlbflush,
    (
        (
            sig(:tlbflushsingle_do, width: 1) &
            (
                sig(:tlbflushsingle_address, width: 32)[31..12] ==
                sig(:tlb31, width: 46)[19..0]
            )
        ) |
        (
            sig(:translate_valid_but_not_dirty, width: 1) &
            sig(:tlb31_sel, width: 1)
        )
    )
  assign :write_data,
    sig(:rw, width: 1).concat(
      sig(:tlbregs_write_combined_su, width: 1).concat(
        sig(:tlbregs_write_combined_rw, width: 1).concat(
          lit(1, width: 1, base: "h", signed: false).concat(
            sig(:tlbregs_write_pcd, width: 1).concat(
              sig(:tlbregs_write_pwt, width: 1).concat(
                sig(:tlbregs_write_physical, width: 32)[31..12].concat(
                  sig(:tlbregs_write_linear, width: 32)[31..12]
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hd7f60667_0_27,
    (
        (
          ~sig(:plru, width: 31)[3]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_28, width: 1)
    )
  assign :__VdfgRegularize_hd7f60667_0_1,
    (
        sig(:__VdfgRegularize_hd7f60667_0_28, width: 1) &
        sig(:plru, width: 31)[3]
    )
  assign :__VdfgRegularize_hd7f60667_0_28,
    (
        (
          ~sig(:plru, width: 31)[1]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_29, width: 1)
    )
  assign :__VdfgRegularize_hd7f60667_0_3,
    (
        sig(:__VdfgRegularize_hd7f60667_0_29, width: 1) &
        sig(:plru, width: 31)[1]
    )
  assign :__VdfgRegularize_hd7f60667_0_29,
    (
        (
          ~sig(:plru, width: 31)[0]
        ) &
        sig(:full, width: 1)
    )
  assign :__VdfgRegularize_hd7f60667_0_24,
    (
        (
          ~sig(:plru, width: 31)[4]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_3, width: 1)
    )
  assign :__VdfgRegularize_hd7f60667_0_5,
    (
        sig(:__VdfgRegularize_hd7f60667_0_3, width: 1) &
        sig(:plru, width: 31)[4]
    )
  assign :__VdfgRegularize_hd7f60667_0_7,
    (
        sig(:full, width: 1) &
        sig(:plru, width: 31)[0]
    )
  assign :__VdfgRegularize_hd7f60667_0_20,
    (
        (
          ~sig(:plru, width: 31)[5]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_21, width: 1)
    )
  assign :__VdfgRegularize_hd7f60667_0_9,
    (
        sig(:__VdfgRegularize_hd7f60667_0_21, width: 1) &
        sig(:plru, width: 31)[5]
    )
  assign :__VdfgRegularize_hd7f60667_0_21,
    (
        (
          ~sig(:plru, width: 31)[2]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_7, width: 1)
    )
  assign :__VdfgRegularize_hd7f60667_0_11,
    (
        sig(:__VdfgRegularize_hd7f60667_0_7, width: 1) &
        sig(:plru, width: 31)[2]
    )
  assign :__VdfgRegularize_hd7f60667_0_17,
    (
        (
          ~sig(:plru, width: 31)[6]
        ) &
        sig(:__VdfgRegularize_hd7f60667_0_11, width: 1)
    )
  assign :__VdfgRegularize_hd7f60667_0_13,
    (
        sig(:__VdfgRegularize_hd7f60667_0_11, width: 1) &
        sig(:plru, width: 31)[6]
    )

  # Processes

  process :initial_block_0,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :tlb0_ena,
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:tlbflushall_do, width: 1)) do
        assign(
          :plru,
          lit(0, width: 31, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((sig(:tlb0_write, width: 1) | sig(:tlb0_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(32907, width: 31, base: "h", signed: false) |
                (
                    lit(2147450740, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb1_write, width: 1) | sig(:tlb1_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(139, width: 31, base: "h", signed: false) |
                (
                    lit(2147450740, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb2_write, width: 1) | sig(:tlb2_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(65547, width: 31, base: "h", signed: false) |
                (
                    lit(2147417972, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb3_write, width: 1) | sig(:tlb3_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(11, width: 31, base: "h", signed: false) |
                (
                    lit(2147417972, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb4_write, width: 1) | sig(:tlb4_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(131331, width: 31, base: "h", signed: false) |
                (
                    lit(2147352308, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb5_write, width: 1) | sig(:tlb5_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(259, width: 31, base: "h", signed: false) |
                (
                    lit(2147352308, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb6_write, width: 1) | sig(:tlb6_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(262147, width: 31, base: "h", signed: false) |
                (
                    lit(2147221236, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb7_write, width: 1) | sig(:tlb7_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(3, width: 31, base: "h", signed: false) |
                (
                    lit(2147221236, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb8_write, width: 1) | sig(:tlb8_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(524817, width: 31, base: "h", signed: false) |
                (
                    lit(2146958828, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb9_write, width: 1) | sig(:tlb9_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(529, width: 31, base: "h", signed: false) |
                (
                    lit(2146958828, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb10_write, width: 1) | sig(:tlb10_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(1048593, width: 31, base: "h", signed: false) |
                (
                    lit(2146434540, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb11_write, width: 1) | sig(:tlb11_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(17, width: 31, base: "h", signed: false) |
                (
                    lit(2146434540, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb12_write, width: 1) | sig(:tlb12_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(2098177, width: 31, base: "h", signed: false) |
                (
                    lit(2145385452, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb13_write, width: 1) | sig(:tlb13_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(1025, width: 31, base: "h", signed: false) |
                (
                    lit(2145385452, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb14_write, width: 1) | sig(:tlb14_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(4194305, width: 31, base: "h", signed: false) |
                (
                    lit(2143288300, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb15_write, width: 1) | sig(:tlb15_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(1, width: 31, base: "h", signed: false) |
                (
                    lit(2143288300, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb16_write, width: 1) | sig(:tlb16_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(8390692, width: 31, base: "h", signed: false) |
                (
                    lit(2139092954, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb17_write, width: 1) | sig(:tlb17_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(2084, width: 31, base: "h", signed: false) |
                (
                    lit(2139092954, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb18_write, width: 1) | sig(:tlb18_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(16777252, width: 31, base: "h", signed: false) |
                (
                    lit(2130704346, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb19_write, width: 1) | sig(:tlb19_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(36, width: 31, base: "h", signed: false) |
                (
                    lit(2130704346, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb20_write, width: 1) | sig(:tlb20_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(33558532, width: 31, base: "h", signed: false) |
                (
                    lit(2113925082, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb21_write, width: 1) | sig(:tlb21_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(4100, width: 31, base: "h", signed: false) |
                (
                    lit(2113925082, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb22_write, width: 1) | sig(:tlb22_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(67108868, width: 31, base: "h", signed: false) |
                (
                    lit(2080370650, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb23_write, width: 1) | sig(:tlb23_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(4, width: 31, base: "h", signed: false) |
                (
                    lit(2080370650, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb24_write, width: 1) | sig(:tlb24_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(134225984, width: 31, base: "h", signed: false) |
                (
                    lit(2013257658, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb25_write, width: 1) | sig(:tlb25_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(8256, width: 31, base: "h", signed: false) |
                (
                    lit(2013257658, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb26_write, width: 1) | sig(:tlb26_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(268435520, width: 31, base: "h", signed: false) |
                (
                    lit(1879039930, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb27_write, width: 1) | sig(:tlb27_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(64, width: 31, base: "h", signed: false) |
                (
                    lit(1879039930, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb28_write, width: 1) | sig(:tlb28_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(536887296, width: 31, base: "h", signed: false) |
                (
                    lit(1610596282, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb29_write, width: 1) | sig(:tlb29_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(16384, width: 31, base: "h", signed: false) |
                (
                    lit(1610596282, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb30_write, width: 1) | sig(:tlb30_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(1073741824, width: 31, base: "h", signed: false) |
                (
                    lit(1073725370, width: 31, base: "h", signed: false) &
                    sig(:plru, width: 31)
                )
            ),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:tlb31_write, width: 1) | sig(:tlb31_sel, width: 1))) do
          assign(
            :plru,
            (
                lit(1073725370, width: 31, base: "h", signed: false) &
                sig(:plru, width: 31)
            ),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :plru,
          lit(0, width: 31, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb0_tlbflush, width: 1))) do
        assign(
          :tlb0,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb0_write, width: 1)) do
          assign(
            :tlb0,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb0,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_3,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb1_tlbflush, width: 1))) do
        assign(
          :tlb1,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb1_write, width: 1)) do
          assign(
            :tlb1,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb1,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb2_tlbflush, width: 1))) do
        assign(
          :tlb2,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb2_write, width: 1)) do
          assign(
            :tlb2,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb2,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_5,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb3_tlbflush, width: 1))) do
        assign(
          :tlb3,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb3_write, width: 1)) do
          assign(
            :tlb3,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb3,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_6,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb4_tlbflush, width: 1))) do
        assign(
          :tlb4,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb4_write, width: 1)) do
          assign(
            :tlb4,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb4,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_7,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb5_tlbflush, width: 1))) do
        assign(
          :tlb5,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb5_write, width: 1)) do
          assign(
            :tlb5,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb5,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_8,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb6_tlbflush, width: 1))) do
        assign(
          :tlb6,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb6_write, width: 1)) do
          assign(
            :tlb6,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb6,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_9,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb7_tlbflush, width: 1))) do
        assign(
          :tlb7,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb7_write, width: 1)) do
          assign(
            :tlb7,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb7,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_10,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb8_tlbflush, width: 1))) do
        assign(
          :tlb8,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb8_write, width: 1)) do
          assign(
            :tlb8,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb8,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_11,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb9_tlbflush, width: 1))) do
        assign(
          :tlb9,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb9_write, width: 1)) do
          assign(
            :tlb9,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb9,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_12,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb10_tlbflush, width: 1))) do
        assign(
          :tlb10,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb10_write, width: 1)) do
          assign(
            :tlb10,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb10,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_13,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb11_tlbflush, width: 1))) do
        assign(
          :tlb11,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb11_write, width: 1)) do
          assign(
            :tlb11,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb11,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_14,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb12_tlbflush, width: 1))) do
        assign(
          :tlb12,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb12_write, width: 1)) do
          assign(
            :tlb12,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb12,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_15,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb13_tlbflush, width: 1))) do
        assign(
          :tlb13,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb13_write, width: 1)) do
          assign(
            :tlb13,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb13,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_16,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb14_tlbflush, width: 1))) do
        assign(
          :tlb14,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb14_write, width: 1)) do
          assign(
            :tlb14,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb14,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_17,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb15_tlbflush, width: 1))) do
        assign(
          :tlb15,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb15_write, width: 1)) do
          assign(
            :tlb15,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb15,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_18,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb16_tlbflush, width: 1))) do
        assign(
          :tlb16,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb16_write, width: 1)) do
          assign(
            :tlb16,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb16,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_19,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb17_tlbflush, width: 1))) do
        assign(
          :tlb17,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb17_write, width: 1)) do
          assign(
            :tlb17,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb17,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_20,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb18_tlbflush, width: 1))) do
        assign(
          :tlb18,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb18_write, width: 1)) do
          assign(
            :tlb18,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb18,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_21,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb19_tlbflush, width: 1))) do
        assign(
          :tlb19,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb19_write, width: 1)) do
          assign(
            :tlb19,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb19,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_22,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb20_tlbflush, width: 1))) do
        assign(
          :tlb20,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb20_write, width: 1)) do
          assign(
            :tlb20,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb20,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_23,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb21_tlbflush, width: 1))) do
        assign(
          :tlb21,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb21_write, width: 1)) do
          assign(
            :tlb21,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb21,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_24,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb22_tlbflush, width: 1))) do
        assign(
          :tlb22,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb22_write, width: 1)) do
          assign(
            :tlb22,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb22,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_25,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb23_tlbflush, width: 1))) do
        assign(
          :tlb23,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb23_write, width: 1)) do
          assign(
            :tlb23,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb23,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_26,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb24_tlbflush, width: 1))) do
        assign(
          :tlb24,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb24_write, width: 1)) do
          assign(
            :tlb24,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb24,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_27,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb25_tlbflush, width: 1))) do
        assign(
          :tlb25,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb25_write, width: 1)) do
          assign(
            :tlb25,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb25,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_28,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb26_tlbflush, width: 1))) do
        assign(
          :tlb26,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb26_write, width: 1)) do
          assign(
            :tlb26,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb26,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_29,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb27_tlbflush, width: 1))) do
        assign(
          :tlb27,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb27_write, width: 1)) do
          assign(
            :tlb27,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb27,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_30,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb28_tlbflush, width: 1))) do
        assign(
          :tlb28,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb28_write, width: 1)) do
          assign(
            :tlb28,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb28,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_31,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb29_tlbflush, width: 1))) do
        assign(
          :tlb29,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb29_write, width: 1)) do
          assign(
            :tlb29,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb29,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_32,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb30_tlbflush, width: 1))) do
        assign(
          :tlb30,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb30_write, width: 1)) do
          assign(
            :tlb30,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb30,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_33,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:tlbflushall_do, width: 1) | sig(:tlb31_tlbflush, width: 1))) do
        assign(
          :tlb31,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlb31_write, width: 1)) do
          assign(
            :tlb31,
            sig(:write_data, width: 46),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlb31,
          lit(0, width: 46, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_34,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :_unused_ok,
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

end
