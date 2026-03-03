# frozen_string_literal: true

class Tlb < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: tlb

  def self._import_decl_kinds
    {
      __VdfgRegularize_h69d40e7c_0_0: :logic,
      __VdfgRegularize_h69d40e7c_0_1: :logic,
      __VdfgRegularize_h69d40e7c_0_10: :logic,
      __VdfgRegularize_h69d40e7c_0_11: :logic,
      __VdfgRegularize_h69d40e7c_0_12: :logic,
      __VdfgRegularize_h69d40e7c_0_13: :logic,
      __VdfgRegularize_h69d40e7c_0_14: :logic,
      __VdfgRegularize_h69d40e7c_0_15: :logic,
      __VdfgRegularize_h69d40e7c_0_16: :logic,
      __VdfgRegularize_h69d40e7c_0_17: :logic,
      __VdfgRegularize_h69d40e7c_0_18: :logic,
      __VdfgRegularize_h69d40e7c_0_19: :logic,
      __VdfgRegularize_h69d40e7c_0_2: :logic,
      __VdfgRegularize_h69d40e7c_0_20: :logic,
      __VdfgRegularize_h69d40e7c_0_21: :logic,
      __VdfgRegularize_h69d40e7c_0_22: :logic,
      __VdfgRegularize_h69d40e7c_0_23: :logic,
      __VdfgRegularize_h69d40e7c_0_24: :logic,
      __VdfgRegularize_h69d40e7c_0_25: :logic,
      __VdfgRegularize_h69d40e7c_0_26: :logic,
      __VdfgRegularize_h69d40e7c_0_27: :logic,
      __VdfgRegularize_h69d40e7c_0_28: :logic,
      __VdfgRegularize_h69d40e7c_0_29: :logic,
      __VdfgRegularize_h69d40e7c_0_3: :logic,
      __VdfgRegularize_h69d40e7c_0_30: :logic,
      __VdfgRegularize_h69d40e7c_0_31: :logic,
      __VdfgRegularize_h69d40e7c_0_32: :logic,
      __VdfgRegularize_h69d40e7c_0_33: :logic,
      __VdfgRegularize_h69d40e7c_0_34: :logic,
      __VdfgRegularize_h69d40e7c_0_35: :logic,
      __VdfgRegularize_h69d40e7c_0_36: :logic,
      __VdfgRegularize_h69d40e7c_0_37: :logic,
      __VdfgRegularize_h69d40e7c_0_38: :logic,
      __VdfgRegularize_h69d40e7c_0_39: :logic,
      __VdfgRegularize_h69d40e7c_0_4: :logic,
      __VdfgRegularize_h69d40e7c_0_40: :logic,
      __VdfgRegularize_h69d40e7c_0_41: :logic,
      __VdfgRegularize_h69d40e7c_0_42: :logic,
      __VdfgRegularize_h69d40e7c_0_43: :logic,
      __VdfgRegularize_h69d40e7c_0_44: :logic,
      __VdfgRegularize_h69d40e7c_0_45: :logic,
      __VdfgRegularize_h69d40e7c_0_46: :logic,
      __VdfgRegularize_h69d40e7c_0_47: :logic,
      __VdfgRegularize_h69d40e7c_0_48: :logic,
      __VdfgRegularize_h69d40e7c_0_49: :logic,
      __VdfgRegularize_h69d40e7c_0_5: :logic,
      __VdfgRegularize_h69d40e7c_0_50: :logic,
      __VdfgRegularize_h69d40e7c_0_51: :logic,
      __VdfgRegularize_h69d40e7c_0_52: :logic,
      __VdfgRegularize_h69d40e7c_0_53: :logic,
      __VdfgRegularize_h69d40e7c_0_54: :logic,
      __VdfgRegularize_h69d40e7c_0_55: :logic,
      __VdfgRegularize_h69d40e7c_0_56: :logic,
      __VdfgRegularize_h69d40e7c_0_57: :logic,
      __VdfgRegularize_h69d40e7c_0_58: :logic,
      __VdfgRegularize_h69d40e7c_0_59: :logic,
      __VdfgRegularize_h69d40e7c_0_6: :logic,
      __VdfgRegularize_h69d40e7c_0_60: :logic,
      __VdfgRegularize_h69d40e7c_0_61: :logic,
      __VdfgRegularize_h69d40e7c_0_62: :logic,
      __VdfgRegularize_h69d40e7c_0_63: :logic,
      __VdfgRegularize_h69d40e7c_0_64: :logic,
      __VdfgRegularize_h69d40e7c_0_65: :logic,
      __VdfgRegularize_h69d40e7c_0_66: :logic,
      __VdfgRegularize_h69d40e7c_0_67: :logic,
      __VdfgRegularize_h69d40e7c_0_68: :logic,
      __VdfgRegularize_h69d40e7c_0_69: :logic,
      __VdfgRegularize_h69d40e7c_0_7: :logic,
      __VdfgRegularize_h69d40e7c_0_70: :logic,
      __VdfgRegularize_h69d40e7c_0_71: :logic,
      __VdfgRegularize_h69d40e7c_0_72: :logic,
      __VdfgRegularize_h69d40e7c_0_73: :logic,
      __VdfgRegularize_h69d40e7c_0_74: :logic,
      __VdfgRegularize_h69d40e7c_0_75: :logic,
      __VdfgRegularize_h69d40e7c_0_76: :logic,
      __VdfgRegularize_h69d40e7c_0_77: :logic,
      __VdfgRegularize_h69d40e7c_0_78: :logic,
      __VdfgRegularize_h69d40e7c_0_79: :logic,
      __VdfgRegularize_h69d40e7c_0_8: :logic,
      __VdfgRegularize_h69d40e7c_0_80: :logic,
      __VdfgRegularize_h69d40e7c_0_81: :logic,
      __VdfgRegularize_h69d40e7c_0_82: :logic,
      __VdfgRegularize_h69d40e7c_0_83: :logic,
      __VdfgRegularize_h69d40e7c_0_84: :logic,
      __VdfgRegularize_h69d40e7c_0_85: :logic,
      __VdfgRegularize_h69d40e7c_0_86: :logic,
      __VdfgRegularize_h69d40e7c_0_87: :logic,
      __VdfgRegularize_h69d40e7c_0_88: :logic,
      __VdfgRegularize_h69d40e7c_0_89: :logic,
      __VdfgRegularize_h69d40e7c_0_9: :logic,
      __VdfgRegularize_h69d40e7c_0_90: :logic,
      __VdfgRegularize_h69d40e7c_0_91: :logic,
      __VdfgRegularize_h69d40e7c_0_92: :logic,
      __VdfgRegularize_h69d40e7c_0_93: :logic,
      _unused_ok: :wire,
      check_pf: :reg,
      check_pf_to_reg: :wire,
      code_pf: :reg,
      code_pf_to_reg: :wire,
      cond_0: :wire,
      cond_10: :wire,
      cond_15: :wire,
      cond_17: :wire,
      cond_18: :wire,
      cond_19: :wire,
      cond_2: :wire,
      cond_20: :wire,
      cond_21: :wire,
      cond_22: :wire,
      cond_23: :wire,
      cond_25: :wire,
      cond_26: :wire,
      cond_27: :wire,
      cond_28: :wire,
      cond_29: :wire,
      cond_3: :wire,
      cond_30: :wire,
      cond_31: :wire,
      cond_33: :wire,
      cond_34: :wire,
      cond_36: :wire,
      cond_37: :wire,
      cond_38: :wire,
      cond_39: :wire,
      cond_4: :wire,
      cond_41: :wire,
      cond_42: :wire,
      cond_5: :wire,
      cond_6: :wire,
      cond_7: :wire,
      cond_9: :wire,
      current_type: :reg,
      current_type_to_reg: :wire,
      linear: :reg,
      linear_to_reg: :wire,
      memtype_cache_disable: :wire,
      memtype_write_transparent: :wire,
      pde: :reg,
      pde_to_reg: :wire,
      pr_reset_waiting: :reg,
      pte: :reg,
      pte_to_reg: :wire,
      read_ac: :reg,
      read_ac_to_reg: :wire,
      read_pf: :reg,
      read_pf_to_reg: :wire,
      rw: :reg,
      rw_entry: :wire,
      rw_to_reg: :wire,
      state: :reg,
      state_to_reg: :wire,
      su: :reg,
      su_entry: :wire,
      su_entry_before_pte: :wire,
      su_to_reg: :wire,
      tlb_check_pf_cr2_to_reg: :wire,
      tlb_check_pf_error_code_to_reg: :wire,
      tlb_code_pf_cr2_to_reg: :wire,
      tlb_code_pf_error_code_to_reg: :wire,
      tlb_read_pf_cr2_to_reg: :wire,
      tlb_read_pf_error_code_to_reg: :wire,
      tlb_write_pf_cr2_to_reg: :wire,
      tlb_write_pf_error_code_to_reg: :wire,
      tlbcheck_done_to_reg: :wire,
      tlbflushall_do_waiting: :reg,
      tlbregs_tlbflushall_do: :wire,
      tlbregs_write_combined_rw: :wire,
      tlbregs_write_combined_su: :wire,
      tlbregs_write_do: :wire,
      tlbregs_write_pcd: :wire,
      tlbregs_write_physical: :wire,
      tlbregs_write_pwt: :wire,
      translate_combined_rw: :wire,
      translate_combined_su: :wire,
      translate_do: :wire,
      translate_pcd: :wire,
      translate_physical: :wire,
      translate_pwt: :wire,
      translate_valid: :wire,
      wp: :reg,
      wp_to_reg: :wire,
      write_ac: :reg,
      write_ac_to_reg: :wire,
      write_double_linear: :reg,
      write_double_linear_to_reg: :wire,
      write_double_state: :reg,
      write_double_state_to_reg: :wire,
      write_pf: :reg,
      write_pf_to_reg: :wire
    }
  end

  # Parameters

  generic :STATE_IDLE, default: "5'h0"
  generic :STATE_CODE_CHECK, default: "5'h1"
  generic :STATE_LOAD_PDE, default: "5'h2"
  generic :STATE_LOAD_PTE_START, default: "5'h3"
  generic :STATE_LOAD_PTE, default: "5'h4"
  generic :STATE_LOAD_PTE_END, default: "5'h5"
  generic :STATE_SAVE_PDE, default: "5'h6"
  generic :STATE_SAVE_PTE_START, default: "5'h7"
  generic :STATE_SAVE_PTE, default: "5'h8"
  generic :STATE_CHECK_CHECK, default: "5'h9"
  generic :STATE_WRITE_CHECK, default: "5'ha"
  generic :STATE_WRITE_WAIT_START, default: "5'hb"
  generic :STATE_WRITE_WAIT, default: "5'hc"
  generic :STATE_WRITE_DOUBLE, default: "5'hd"
  generic :STATE_READ_CHECK, default: "5'he"
  generic :STATE_READ_WAIT_START, default: "5'hf"
  generic :STATE_READ_WAIT, default: "5'h10"
  generic :STATE_RETRY, default: "5'h11"
  generic :TYPE_CODE, default: "2'h0"
  generic :TYPE_CHECK, default: "2'h1"
  generic :TYPE_WRITE, default: "2'h2"
  generic :TYPE_READ, default: "2'h3"
  generic :WRITE_DOUBLE_NONE, default: "2'h0"
  generic :WRITE_DOUBLE_CHECK, default: "2'h1"
  generic :WRITE_DOUBLE_RESTART, default: "2'h2"

  # Ports

  input :clk
  input :rst_n
  input :pr_reset
  input :rd_reset
  input :exe_reset
  input :wr_reset
  input :cr0_pg
  input :cr0_wp
  input :cr0_am
  input :cr0_cd
  input :cr0_nw
  input :acflag
  input :cr3, width: 32
  input :pipeline_after_read_empty
  input :pipeline_after_prefetch_empty
  output :tlb_code_pf_cr2, width: 32
  output :tlb_code_pf_error_code, width: 16
  output :tlb_check_pf_cr2, width: 32
  output :tlb_check_pf_error_code, width: 16
  output :tlb_write_pf_cr2, width: 32
  output :tlb_write_pf_error_code, width: 16
  output :tlb_read_pf_cr2, width: 32
  output :tlb_read_pf_error_code, width: 16
  input :tlbflushsingle_do
  output :tlbflushsingle_done
  input :tlbflushsingle_address, width: 32
  input :tlbflushall_do
  input :tlbread_do
  output :tlbread_done
  output :tlbread_page_fault
  output :tlbread_ac_fault
  output :tlbread_retry
  input :tlbread_cpl, width: 2
  input :tlbread_address, width: 32
  input :tlbread_length, width: 4
  input :tlbread_length_full, width: 4
  input :tlbread_lock
  input :tlbread_rmw
  output :tlbread_data, width: 64
  input :tlbwrite_do
  output :tlbwrite_done
  output :tlbwrite_page_fault
  output :tlbwrite_ac_fault
  input :tlbwrite_cpl, width: 2
  input :tlbwrite_address, width: 32
  input :tlbwrite_length, width: 3
  input :tlbwrite_length_full, width: 3
  input :tlbwrite_lock
  input :tlbwrite_rmw
  input :tlbwrite_data, width: 32
  input :tlbcheck_do
  output :tlbcheck_done
  output :tlbcheck_page_fault
  input :tlbcheck_address, width: 32
  input :tlbcheck_rw
  output :dcacheread_do
  input :dcacheread_done
  output :dcacheread_length, width: 4
  output :dcacheread_cache_disable
  output :dcacheread_address, width: 32
  input :dcacheread_data, width: 64
  output :dcachewrite_do
  input :dcachewrite_done
  output :dcachewrite_length, width: 3
  output :dcachewrite_cache_disable
  output :dcachewrite_address, width: 32
  output :dcachewrite_write_through
  output :dcachewrite_data, width: 32
  input :tlbcoderequest_do
  input :tlbcoderequest_address, width: 32
  input :tlbcoderequest_su
  output :tlbcode_do
  output :tlbcode_linear, width: 32
  output :tlbcode_physical, width: 32
  output :tlbcode_cache_disable
  output :prefetchfifo_signal_pf_do

  # Signals

  signal :__VdfgRegularize_h69d40e7c_0_0
  signal :__VdfgRegularize_h69d40e7c_0_1
  signal :__VdfgRegularize_h69d40e7c_0_10
  signal :__VdfgRegularize_h69d40e7c_0_11
  signal :__VdfgRegularize_h69d40e7c_0_12
  signal :__VdfgRegularize_h69d40e7c_0_13
  signal :__VdfgRegularize_h69d40e7c_0_14
  signal :__VdfgRegularize_h69d40e7c_0_15
  signal :__VdfgRegularize_h69d40e7c_0_16
  signal :__VdfgRegularize_h69d40e7c_0_17
  signal :__VdfgRegularize_h69d40e7c_0_18
  signal :__VdfgRegularize_h69d40e7c_0_19
  signal :__VdfgRegularize_h69d40e7c_0_2
  signal :__VdfgRegularize_h69d40e7c_0_20
  signal :__VdfgRegularize_h69d40e7c_0_21
  signal :__VdfgRegularize_h69d40e7c_0_22
  signal :__VdfgRegularize_h69d40e7c_0_23
  signal :__VdfgRegularize_h69d40e7c_0_24
  signal :__VdfgRegularize_h69d40e7c_0_25
  signal :__VdfgRegularize_h69d40e7c_0_26
  signal :__VdfgRegularize_h69d40e7c_0_27
  signal :__VdfgRegularize_h69d40e7c_0_28
  signal :__VdfgRegularize_h69d40e7c_0_29
  signal :__VdfgRegularize_h69d40e7c_0_3
  signal :__VdfgRegularize_h69d40e7c_0_30
  signal :__VdfgRegularize_h69d40e7c_0_31
  signal :__VdfgRegularize_h69d40e7c_0_32
  signal :__VdfgRegularize_h69d40e7c_0_33
  signal :__VdfgRegularize_h69d40e7c_0_34
  signal :__VdfgRegularize_h69d40e7c_0_35
  signal :__VdfgRegularize_h69d40e7c_0_36
  signal :__VdfgRegularize_h69d40e7c_0_37
  signal :__VdfgRegularize_h69d40e7c_0_38
  signal :__VdfgRegularize_h69d40e7c_0_39
  signal :__VdfgRegularize_h69d40e7c_0_4
  signal :__VdfgRegularize_h69d40e7c_0_40
  signal :__VdfgRegularize_h69d40e7c_0_41
  signal :__VdfgRegularize_h69d40e7c_0_42
  signal :__VdfgRegularize_h69d40e7c_0_43
  signal :__VdfgRegularize_h69d40e7c_0_44
  signal :__VdfgRegularize_h69d40e7c_0_45
  signal :__VdfgRegularize_h69d40e7c_0_46, width: 16
  signal :__VdfgRegularize_h69d40e7c_0_47, width: 16
  signal :__VdfgRegularize_h69d40e7c_0_48, width: 16
  signal :__VdfgRegularize_h69d40e7c_0_49, width: 32
  signal :__VdfgRegularize_h69d40e7c_0_5
  signal :__VdfgRegularize_h69d40e7c_0_50, width: 32
  signal :__VdfgRegularize_h69d40e7c_0_51, width: 32
  signal :__VdfgRegularize_h69d40e7c_0_52
  signal :__VdfgRegularize_h69d40e7c_0_53
  signal :__VdfgRegularize_h69d40e7c_0_54
  signal :__VdfgRegularize_h69d40e7c_0_55
  signal :__VdfgRegularize_h69d40e7c_0_56
  signal :__VdfgRegularize_h69d40e7c_0_57
  signal :__VdfgRegularize_h69d40e7c_0_58, width: 14
  signal :__VdfgRegularize_h69d40e7c_0_59
  signal :__VdfgRegularize_h69d40e7c_0_6
  signal :__VdfgRegularize_h69d40e7c_0_60
  signal :__VdfgRegularize_h69d40e7c_0_61
  signal :__VdfgRegularize_h69d40e7c_0_62
  signal :__VdfgRegularize_h69d40e7c_0_63
  signal :__VdfgRegularize_h69d40e7c_0_64
  signal :__VdfgRegularize_h69d40e7c_0_65
  signal :__VdfgRegularize_h69d40e7c_0_66
  signal :__VdfgRegularize_h69d40e7c_0_67
  signal :__VdfgRegularize_h69d40e7c_0_68
  signal :__VdfgRegularize_h69d40e7c_0_69
  signal :__VdfgRegularize_h69d40e7c_0_7
  signal :__VdfgRegularize_h69d40e7c_0_70
  signal :__VdfgRegularize_h69d40e7c_0_71
  signal :__VdfgRegularize_h69d40e7c_0_72
  signal :__VdfgRegularize_h69d40e7c_0_73
  signal :__VdfgRegularize_h69d40e7c_0_74
  signal :__VdfgRegularize_h69d40e7c_0_75
  signal :__VdfgRegularize_h69d40e7c_0_76
  signal :__VdfgRegularize_h69d40e7c_0_77
  signal :__VdfgRegularize_h69d40e7c_0_78
  signal :__VdfgRegularize_h69d40e7c_0_79
  signal :__VdfgRegularize_h69d40e7c_0_8
  signal :__VdfgRegularize_h69d40e7c_0_80
  signal :__VdfgRegularize_h69d40e7c_0_81
  signal :__VdfgRegularize_h69d40e7c_0_82
  signal :__VdfgRegularize_h69d40e7c_0_83
  signal :__VdfgRegularize_h69d40e7c_0_84
  signal :__VdfgRegularize_h69d40e7c_0_85
  signal :__VdfgRegularize_h69d40e7c_0_86
  signal :__VdfgRegularize_h69d40e7c_0_87
  signal :__VdfgRegularize_h69d40e7c_0_88
  signal :__VdfgRegularize_h69d40e7c_0_89
  signal :__VdfgRegularize_h69d40e7c_0_9
  signal :__VdfgRegularize_h69d40e7c_0_90
  signal :__VdfgRegularize_h69d40e7c_0_91
  signal :__VdfgRegularize_h69d40e7c_0_92
  signal :__VdfgRegularize_h69d40e7c_0_93
  signal :_unused_ok
  signal :check_pf
  signal :check_pf_to_reg
  signal :code_pf
  signal :code_pf_to_reg
  signal :cond_0
  signal :cond_10
  signal :cond_15
  signal :cond_17
  signal :cond_18
  signal :cond_19
  signal :cond_2
  signal :cond_20
  signal :cond_21
  signal :cond_22
  signal :cond_23
  signal :cond_25
  signal :cond_26
  signal :cond_27
  signal :cond_28
  signal :cond_29
  signal :cond_3
  signal :cond_30
  signal :cond_31
  signal :cond_33
  signal :cond_34
  signal :cond_36
  signal :cond_37
  signal :cond_38
  signal :cond_39
  signal :cond_4
  signal :cond_41
  signal :cond_42
  signal :cond_5
  signal :cond_6
  signal :cond_7
  signal :cond_9
  signal :current_type, width: 2
  signal :current_type_to_reg, width: 2
  signal :linear, width: 32
  signal :linear_to_reg, width: 32
  signal :memtype_cache_disable
  signal :memtype_write_transparent
  signal :pde, width: 32
  signal :pde_to_reg, width: 32
  signal :pr_reset_waiting
  signal :pte, width: 32
  signal :pte_to_reg, width: 32
  signal :read_ac
  signal :read_ac_to_reg
  signal :read_pf
  signal :read_pf_to_reg
  signal :rw
  signal :rw_entry
  signal :rw_to_reg
  signal :state, width: 5
  signal :state_to_reg, width: 5
  signal :su
  signal :su_entry
  signal :su_entry_before_pte
  signal :su_to_reg
  signal :tlb_check_pf_cr2_to_reg, width: 32
  signal :tlb_check_pf_error_code_to_reg, width: 16
  signal :tlb_code_pf_cr2_to_reg, width: 32
  signal :tlb_code_pf_error_code_to_reg, width: 16
  signal :tlb_read_pf_cr2_to_reg, width: 32
  signal :tlb_read_pf_error_code_to_reg, width: 16
  signal :tlb_write_pf_cr2_to_reg, width: 32
  signal :tlb_write_pf_error_code_to_reg, width: 16
  signal :tlbcheck_done_to_reg
  signal :tlbflushall_do_waiting
  signal :tlbregs_tlbflushall_do
  signal :tlbregs_write_combined_rw
  signal :tlbregs_write_combined_su
  signal :tlbregs_write_do
  signal :tlbregs_write_pcd
  signal :tlbregs_write_physical, width: 32
  signal :tlbregs_write_pwt
  signal :translate_combined_rw
  signal :translate_combined_su
  signal :translate_do
  signal :translate_pcd
  signal :translate_physical, width: 32
  signal :translate_pwt
  signal :translate_valid
  signal :wp
  signal :wp_to_reg
  signal :write_ac
  signal :write_ac_to_reg
  signal :write_double_linear, width: 32
  signal :write_double_linear_to_reg, width: 32
  signal :write_double_state, width: 2
  signal :write_double_state_to_reg, width: 2
  signal :write_pf
  signal :write_pf_to_reg

  # Assignments

  assign :tlbread_data,
    sig(:dcacheread_data, width: 64)
  assign :tlbread_page_fault,
    sig(:read_pf, width: 1)
  assign :tlbread_ac_fault,
    sig(:read_ac, width: 1)
  assign :tlbwrite_page_fault,
    sig(:write_pf, width: 1)
  assign :tlbwrite_ac_fault,
    sig(:write_ac, width: 1)
  assign :tlbcheck_page_fault,
    sig(:check_pf, width: 1)
  assign :rw_entry,
    mux(
      sig(:tlbregs_write_do, width: 1),
      (
          sig(:pde, width: 32)[1] &
          sig(:pte, width: 32)[1]
      ),
      sig(:translate_combined_rw, width: 1)
    )
  assign :tlbregs_write_do,
    (
        lit(5, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :su_entry,
    mux(
      sig(:tlbregs_write_do, width: 1),
      (
          sig(:pde, width: 32)[2] &
          sig(:pte, width: 32)[2]
      ),
      sig(:translate_combined_su, width: 1)
    )
  assign :su_entry_before_pte,
    (
        sig(:pde, width: 32)[2] &
        sig(:dcacheread_data, width: 64)[2]
    )
  assign :tlbcode_linear,
    sig(:linear, width: 32)
  assign :cond_0,
    (
        lit(0, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_2,
    (
        sig(:tlbflushall_do, width: 1) |
        sig(:tlbflushall_do_waiting, width: 1)
    )
  assign :cond_3,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_1, width: 1) &
        (
            sig(:__VdfgRegularize_h69d40e7c_0_0, width: 1) &
            (
                sig(:acflag, width: 1) &
                (
                    sig(:cr0_am, width: 1) &
                    (
                        sig(:__VdfgRegularize_h69d40e7c_0_2, width: 1) &
                        (
                            (
                                (
                                    lit(2, width: 3, base: "h", signed: false) ==
                                    sig(:tlbwrite_length_full, width: 3)
                                ) &
                                sig(:tlbwrite_address, width: 32)[0]
                            ) |
                            (
                                (
                                    lit(4, width: 3, base: "h", signed: false) ==
                                    sig(:tlbwrite_length_full, width: 3)
                                ) &
                                (
                                    lit(0, width: 2, base: "h", signed: false) !=
                                    sig(:tlbwrite_address, width: 32)[1..0]
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_1,
    (
      ~sig(:write_ac, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_0,
    (
        (
          ~sig(:wr_reset, width: 1)
        ) &
        sig(:tlbwrite_do, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_2,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:tlbwrite_cpl, width: 2)
    )
  assign :cond_4,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_0, width: 1) &
        (
            (
              ~sig(:write_pf, width: 1)
            ) &
            sig(:__VdfgRegularize_h69d40e7c_0_1, width: 1)
        )
    )
  assign :cond_5,
    (
        (
          ~sig(:exe_reset, width: 1)
        ) &
        (
            (
              ~(
                  sig(:check_pf, width: 1) |
                  sig(:tlbcheck_done, width: 1)
              )
            ) &
            sig(:tlbcheck_do, width: 1)
        )
    )
  assign :cond_6,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_4, width: 1) &
        (
            sig(:__VdfgRegularize_h69d40e7c_0_3, width: 1) &
            (
                sig(:acflag, width: 1) &
                (
                    sig(:cr0_am, width: 1) &
                    (
                        sig(:__VdfgRegularize_h69d40e7c_0_5, width: 1) &
                        (
                            (
                                (
                                    lit(2, width: 4, base: "h", signed: false) ==
                                    sig(:tlbread_length_full, width: 4)
                                ) &
                                sig(:tlbread_address, width: 32)[0]
                            ) |
                            (
                                (
                                    lit(4, width: 4, base: "h", signed: false) ==
                                    sig(:tlbread_length_full, width: 4)
                                ) &
                                (
                                    lit(0, width: 2, base: "h", signed: false) !=
                                    sig(:tlbread_address, width: 32)[1..0]
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_4,
    (
      ~sig(:read_ac, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_3,
    (
        (
          ~sig(:rd_reset, width: 1)
        ) &
        sig(:tlbread_do, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_5,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:tlbread_cpl, width: 2)
    )
  assign :cond_7,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_3, width: 1) &
        (
            (
              ~sig(:read_pf, width: 1)
            ) &
            sig(:__VdfgRegularize_h69d40e7c_0_4, width: 1)
        )
    )
  assign :tlbcode_do,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_28, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_30, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_28,
    (
      ~sig(:cond_18, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_30,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_89, width: 1) &
        sig(:cond_17, width: 1)
    )
  assign :cond_9,
    (
        lit(13, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_10,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:write_double_state, width: 2)
    )
  assign :cond_15,
    (
        lit(14, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_17,
    (
        (
          ~sig(:cr0_pg, width: 1)
        ) |
        sig(:translate_valid, width: 1)
    )
  assign :cond_18,
    (
        sig(:cr0_pg, width: 1) &
        (
            (
                (
                  ~sig(:su_entry, width: 1)
                ) &
                sig(:su, width: 1)
            ) |
            (
                (
                  ~sig(:rw_entry, width: 1)
                ) &
                (
                    sig(:rw, width: 1) &
                    (
                        (
                            sig(:su, width: 1) &
                            sig(:su_entry, width: 1)
                        ) |
                        sig(:__VdfgRegularize_h69d40e7c_0_93, width: 1)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_93,
    (
        (
          ~sig(:su, width: 1)
        ) &
        sig(:wp, width: 1)
    )
  assign :cond_19,
    (
        lit(10, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_20,
    (
        sig(:translate_valid, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_7, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_7,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:write_double_state, width: 2)
    )
  assign :cond_21,
    (
        lit(9, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_22,
    (
        lit(1, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_23,
    (
        sig(:pr_reset, width: 1) |
        sig(:pr_reset_waiting, width: 1)
    )
  assign :cond_25,
    (
      ~sig(:dcacheread_data, width: 64)[0]
    )
  assign :cond_26,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_8, width: 1) &
        (
            sig(:__VdfgRegularize_h69d40e7c_0_6, width: 1) &
            (
              ~sig(:pr_reset_waiting, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_8,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:current_type, width: 2)
    )
  assign :__VdfgRegularize_h69d40e7c_0_6,
    (
      ~sig(:pr_reset, width: 1)
    )
  assign :cond_27,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:current_type, width: 2)
    )
  assign :cond_28,
    (
        lit(2, width: 2, base: "h", signed: false) ==
        sig(:current_type, width: 2)
    )
  assign :cond_29,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:current_type, width: 2)
    )
  assign :cond_30,
    (
        lit(3, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_31,
    (
        lit(17, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_33,
    (
        sig(:cond_25, width: 1) |
        (
            (
                (
                  ~sig(:su_entry_before_pte, width: 1)
                ) &
                sig(:su, width: 1)
            ) |
            (
                (
                  ~(
                      sig(:pde, width: 32)[1] &
                      sig(:dcacheread_data, width: 64)[1]
                  )
                ) &
                (
                    sig(:rw, width: 1) &
                    (
                        (
                            sig(:su, width: 1) &
                            sig(:su_entry_before_pte, width: 1)
                        ) |
                        sig(:__VdfgRegularize_h69d40e7c_0_93, width: 1)
                    )
                )
            )
        )
    )
  assign :cond_34,
    (
        (
            (
                (
                  ~sig(:pipeline_after_read_empty, width: 1)
                ) &
                sig(:cond_29, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_h69d40e7c_0_8, width: 1) &
                (
                    (
                      ~sig(:pipeline_after_prefetch_empty, width: 1)
                    ) |
                    sig(:pr_reset_waiting, width: 1)
                )
            )
        ) &
        (
            sig(:cond_36, width: 1) |
            (
                (
                  ~sig(:dcacheread_data, width: 64)[5]
                ) |
                (
                    (
                      ~sig(:dcacheread_data, width: 64)[6]
                    ) &
                    sig(:rw, width: 1)
                )
            )
        )
    )
  assign :cond_36,
    (
      ~sig(:pde, width: 32)[5]
    )
  assign :cond_37,
    (
        (
          ~sig(:pte, width: 32)[5]
        ) |
        sig(:__VdfgRegularize_h69d40e7c_0_9, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_9,
    (
        (
          ~sig(:pte, width: 32)[6]
        ) &
        sig(:rw, width: 1)
    )
  assign :cond_38,
    (
        sig(:cond_28, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_7, width: 1)
    )
  assign :cond_39,
    (
        lit(15, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_41,
    (
        lit(7, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :cond_42,
    (
        lit(11, width: 5, base: "h", signed: false) ==
        sig(:state, width: 5)
    )
  assign :current_type_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_92, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_91, width: 1),
        lit(2, width: 2, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_90, width: 1),
          lit(1, width: 2, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_88, width: 1),
            lit(0, width: 2, base: "h", signed: false),
            sig(:current_type, width: 2)
          )
        )
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_92,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_10, width: 1) &
        sig(:cond_15, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_91,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_10, width: 1) &
        sig(:cond_19, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_90,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_10, width: 1) &
        sig(:cond_21, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_88,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_10, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_89, width: 1)
    )
  assign :read_pf_to_reg,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_11, width: 1) &
        (
            sig(:__VdfgRegularize_h69d40e7c_0_13, width: 1) |
            (
                sig(:__VdfgRegularize_h69d40e7c_0_84, width: 1) |
                (
                    sig(:__VdfgRegularize_h69d40e7c_0_81, width: 1) |
                    sig(:read_pf, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_11,
    (
      ~sig(:cond_0, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_13,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_12, width: 1) &
        sig(:cond_18, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_84,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_85, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_80, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_81,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_82, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_80, width: 1)
    )
  assign :pde_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_14, width: 1),
      sig(:dcacheread_data, width: 64)[31..0],
      sig(:pde, width: 32)
    )
  assign :__VdfgRegularize_h69d40e7c_0_14,
    (
        (
            lit(2, width: 5, base: "h", signed: false) ==
            sig(:state, width: 5)
        ) &
        sig(:dcacheread_done, width: 1)
    )
  assign :write_pf_to_reg,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_11, width: 1) &
        (
            sig(:__VdfgRegularize_h69d40e7c_0_21, width: 1) |
            (
                sig(:__VdfgRegularize_h69d40e7c_0_22, width: 1) |
                (
                    sig(:__VdfgRegularize_h69d40e7c_0_23, width: 1) |
                    sig(:write_pf, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_21,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_20, width: 1) &
        sig(:cond_18, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_22,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_85, width: 1) &
        sig(:cond_28, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_23,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_82, width: 1) &
        sig(:cond_28, width: 1)
    )
  assign :state_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_24, width: 1),
      lit(10, width: 5, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_25, width: 1),
        lit(9, width: 5, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_26, width: 1),
          lit(14, width: 5, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_73, width: 1),
            lit(1, width: 5, base: "h", signed: false),
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_27, width: 1),
              lit(10, width: 5, base: "h", signed: false),
              mux(
                sig(:__VdfgRegularize_h69d40e7c_0_72, width: 1),
                lit(10, width: 5, base: "h", signed: false),
                mux(
                  sig(:tlbwrite_done, width: 1),
                  lit(0, width: 5, base: "h", signed: false),
                  mux(
                    sig(:tlbread_done, width: 1),
                    lit(0, width: 5, base: "h", signed: false),
                    mux(
                      sig(:__VdfgRegularize_h69d40e7c_0_13, width: 1),
                      lit(0, width: 5, base: "h", signed: false),
                      mux(
                        sig(:__VdfgRegularize_h69d40e7c_0_71, width: 1),
                        lit(16, width: 5, base: "h", signed: false),
                        mux(
                          sig(:__VdfgRegularize_h69d40e7c_0_92, width: 1),
                          lit(2, width: 5, base: "h", signed: false),
                          mux(
                            sig(:__VdfgRegularize_h69d40e7c_0_21, width: 1),
                            lit(0, width: 5, base: "h", signed: false),
                            mux(
                              (
                                  sig(:__VdfgRegularize_h69d40e7c_0_70, width: 1) &
                                  sig(:cond_20, width: 1)
                              ),
                              lit(13, width: 5, base: "h", signed: false),
                              mux(
                                sig(:__VdfgRegularize_h69d40e7c_0_69, width: 1),
                                lit(12, width: 5, base: "h", signed: false),
                                mux(
                                  sig(:__VdfgRegularize_h69d40e7c_0_91, width: 1),
                                  lit(2, width: 5, base: "h", signed: false),
                                  mux(
                                    sig(:__VdfgRegularize_h69d40e7c_0_29, width: 1),
                                    lit(0, width: 5, base: "h", signed: false),
                                    mux(
                                      sig(:__VdfgRegularize_h69d40e7c_0_90, width: 1),
                                      lit(2, width: 5, base: "h", signed: false),
                                      mux(
                                        (
                                            sig(:cond_22, width: 1) &
                                            sig(:cond_23, width: 1)
                                        ),
                                        lit(0, width: 5, base: "h", signed: false),
                                        mux(
                                          sig(:__VdfgRegularize_h69d40e7c_0_30, width: 1),
                                          lit(0, width: 5, base: "h", signed: false),
                                          mux(
                                            sig(:__VdfgRegularize_h69d40e7c_0_88, width: 1),
                                            lit(2, width: 5, base: "h", signed: false),
                                            mux(
                                              sig(:__VdfgRegularize_h69d40e7c_0_87, width: 1),
                                              lit(0, width: 5, base: "h", signed: false),
                                              mux(
                                                (
                                                    sig(:dcacheread_data, width: 64)[0] &
                                                    sig(:__VdfgRegularize_h69d40e7c_0_14, width: 1)
                                                ),
                                                lit(3, width: 5, base: "h", signed: false),
                                                mux(
                                                  sig(:cond_30, width: 1),
                                                  lit(4, width: 5, base: "h", signed: false),
                                                  mux(
                                                    sig(:cond_31, width: 1),
                                                    lit(0, width: 5, base: "h", signed: false),
                                                    mux(
                                                      sig(:__VdfgRegularize_h69d40e7c_0_19, width: 1),
                                                      lit(0, width: 5, base: "h", signed: false),
                                                      mux(
                                                        (
                                                            sig(:__VdfgRegularize_h69d40e7c_0_68, width: 1) &
                                                            sig(:cond_34, width: 1)
                                                        ),
                                                        lit(17, width: 5, base: "h", signed: false),
                                                        mux(
                                                          (
                                                              (
                                                                ~sig(:cond_34, width: 1)
                                                              ) &
                                                              sig(:__VdfgRegularize_h69d40e7c_0_68, width: 1)
                                                          ),
                                                          lit(5, width: 5, base: "h", signed: false),
                                                          mux(
                                                            sig(:__VdfgRegularize_h69d40e7c_0_67, width: 1),
                                                            lit(6, width: 5, base: "h", signed: false),
                                                            mux(
                                                              sig(:__VdfgRegularize_h69d40e7c_0_31, width: 1),
                                                              lit(8, width: 5, base: "h", signed: false),
                                                              mux(
                                                                (
                                                                    sig(:__VdfgRegularize_h69d40e7c_0_65, width: 1) &
                                                                    sig(:cond_38, width: 1)
                                                                ),
                                                                lit(13, width: 5, base: "h", signed: false),
                                                                mux(
                                                                  sig(:__VdfgRegularize_h69d40e7c_0_34, width: 1),
                                                                  lit(12, width: 5, base: "h", signed: false),
                                                                  mux(
                                                                    (
                                                                        sig(:__VdfgRegularize_h69d40e7c_0_63, width: 1) &
                                                                        sig(:cond_29, width: 1)
                                                                    ),
                                                                    lit(15, width: 5, base: "h", signed: false),
                                                                    mux(
                                                                      (
                                                                          sig(:__VdfgRegularize_h69d40e7c_0_35, width: 1) &
                                                                          sig(:__VdfgRegularize_h69d40e7c_0_63, width: 1)
                                                                      ),
                                                                      lit(0, width: 5, base: "h", signed: false),
                                                                      mux(
                                                                        sig(:cond_39, width: 1),
                                                                        lit(16, width: 5, base: "h", signed: false),
                                                                        mux(
                                                                          (
                                                                              sig(:__VdfgRegularize_h69d40e7c_0_36, width: 1) &
                                                                              sig(:cond_37, width: 1)
                                                                          ),
                                                                          lit(7, width: 5, base: "h", signed: false),
                                                                          mux(
                                                                            (
                                                                                sig(:__VdfgRegularize_h69d40e7c_0_62, width: 1) &
                                                                                sig(:cond_28, width: 1)
                                                                            ),
                                                                            lit(11, width: 5, base: "h", signed: false),
                                                                            mux(
                                                                              sig(:__VdfgRegularize_h69d40e7c_0_37, width: 1),
                                                                              lit(16, width: 5, base: "h", signed: false),
                                                                              mux(
                                                                                (
                                                                                    sig(:__VdfgRegularize_h69d40e7c_0_35, width: 1) &
                                                                                    sig(:__VdfgRegularize_h69d40e7c_0_61, width: 1)
                                                                                ),
                                                                                lit(0, width: 5, base: "h", signed: false),
                                                                                mux(
                                                                                  sig(:cond_41, width: 1),
                                                                                  lit(8, width: 5, base: "h", signed: false),
                                                                                  mux(
                                                                                    (
                                                                                        sig(:cond_42, width: 1) &
                                                                                        sig(:cond_38, width: 1)
                                                                                    ),
                                                                                    lit(13, width: 5, base: "h", signed: false),
                                                                                    mux(
                                                                                      sig(:__VdfgRegularize_h69d40e7c_0_60, width: 1),
                                                                                      lit(12, width: 5, base: "h", signed: false),
                                                                                      mux(
                                                                                        (
                                                                                            sig(:__VdfgRegularize_h69d40e7c_0_38, width: 1) &
                                                                                            sig(:cond_28, width: 1)
                                                                                        ),
                                                                                        lit(11, width: 5, base: "h", signed: false),
                                                                                        mux(
                                                                                          sig(:__VdfgRegularize_h69d40e7c_0_39, width: 1),
                                                                                          lit(16, width: 5, base: "h", signed: false),
                                                                                          mux(
                                                                                            (
                                                                                                sig(:__VdfgRegularize_h69d40e7c_0_35, width: 1) &
                                                                                                sig(:__VdfgRegularize_h69d40e7c_0_59, width: 1)
                                                                                            ),
                                                                                            lit(0, width: 5, base: "h", signed: false),
                                                                                            sig(:state, width: 5)
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
  assign :__VdfgRegularize_h69d40e7c_0_24,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_77, width: 1) &
        sig(:cond_4, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_25,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_76, width: 1) &
        sig(:cond_5, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_26,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_74, width: 1) &
        sig(:cond_7, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_73,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_74, width: 1) &
        (
            (
              ~sig(:cond_7, width: 1)
            ) &
            (
                sig(:__VdfgRegularize_h69d40e7c_0_6, width: 1) &
                (
                    (
                      ~(
                          sig(:code_pf, width: 1) |
                          sig(:tlbcode_do, width: 1)
                      )
                    ) &
                    sig(:tlbcoderequest_do, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_27,
    (
        sig(:cond_9, width: 1) &
        sig(:cond_10, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_72,
    (
        (
          ~sig(:cond_10, width: 1)
        ) &
        sig(:cond_9, width: 1)
    )
  assign :tlbwrite_done,
    (
        (
            lit(12, width: 5, base: "h", signed: false) ==
            sig(:state, width: 5)
        ) &
        sig(:dcachewrite_done, width: 1)
    )
  assign :tlbread_done,
    (
        (
            lit(16, width: 5, base: "h", signed: false) ==
            sig(:state, width: 5)
        ) &
        sig(:dcacheread_done, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_71,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_28, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_12, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_70,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_28, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_20, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_69,
    (
        (
          ~sig(:cond_20, width: 1)
        ) &
        sig(:__VdfgRegularize_h69d40e7c_0_70, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_29,
    (
        sig(:cond_21, width: 1) &
        sig(:cond_17, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_87,
    (
        sig(:cond_25, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_14, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_19,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_18, width: 1) &
        sig(:cond_33, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_68,
    (
        (
          ~sig(:cond_33, width: 1)
        ) &
        sig(:__VdfgRegularize_h69d40e7c_0_18, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_67,
    (
        sig(:cond_36, width: 1) &
        sig(:tlbregs_write_do, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_31,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_66, width: 1) &
        sig(:cond_37, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_65,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_32, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_66, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_34,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_64, width: 1) &
        sig(:cond_28, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_63,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_17, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_64, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_35,
    (
      ~sig(:cond_29, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_36,
    (
        (
            lit(6, width: 5, base: "h", signed: false) ==
            sig(:state, width: 5)
        ) &
        sig(:dcachewrite_done, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_62,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_32, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_36, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_37,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_61, width: 1) &
        sig(:cond_29, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_61,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_17, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_62, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_60,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_33, width: 1) &
        sig(:cond_42, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_38,
    (
        (
            lit(8, width: 5, base: "h", signed: false) ==
            sig(:state, width: 5)
        ) &
        sig(:dcachewrite_done, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_39,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_59, width: 1) &
        sig(:cond_29, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_59,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_17, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_38, width: 1)
    )
  assign :tlb_read_pf_cr2_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_13, width: 1),
      sig(:linear, width: 32),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_84, width: 1),
        sig(:linear, width: 32),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_81, width: 1),
          sig(:linear, width: 32),
          sig(:tlb_read_pf_cr2, width: 32)
        )
      )
    )
  assign :tlb_code_pf_cr2_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_40, width: 1),
      sig(:linear, width: 32),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_41, width: 1),
        sig(:linear, width: 32),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_42, width: 1),
          sig(:linear, width: 32),
          sig(:tlb_code_pf_cr2, width: 32)
        )
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_40,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_30, width: 1) &
        sig(:cond_18, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_41,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_87, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_42,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_19, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :check_pf_to_reg,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_43, width: 1) |
        (
            sig(:__VdfgRegularize_h69d40e7c_0_44, width: 1) |
            (
                sig(:__VdfgRegularize_h69d40e7c_0_45, width: 1) |
                sig(:check_pf, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_43,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_29, width: 1) &
        sig(:cond_18, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_44,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_86, width: 1) &
        sig(:cond_27, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_45,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_83, width: 1) &
        sig(:cond_27, width: 1)
    )
  assign :su_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_24, width: 1),
      sig(:__VdfgRegularize_h69d40e7c_0_2, width: 1),
      (
          (
            ~sig(:__VdfgRegularize_h69d40e7c_0_25, width: 1)
          ) &
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_26, width: 1),
            sig(:__VdfgRegularize_h69d40e7c_0_5, width: 1),
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_73, width: 1),
              sig(:tlbcoderequest_su, width: 1),
              sig(:su, width: 1)
            )
          )
      )
    )
  assign :tlb_check_pf_error_code_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_43, width: 1),
      sig(:__VdfgRegularize_h69d40e7c_0_46, width: 16),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_44, width: 1),
        sig(:__VdfgRegularize_h69d40e7c_0_47, width: 16),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_45, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_48, width: 16),
          sig(:tlb_check_pf_error_code, width: 16)
        )
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_46,
    sig(:__VdfgRegularize_h69d40e7c_0_58, width: 14).concat(
      sig(:rw, width: 1).concat(
        lit(1, width: 1, base: "h", signed: false)
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_47,
    sig(:__VdfgRegularize_h69d40e7c_0_58, width: 14).concat(
      sig(:rw, width: 1).concat(
        lit(0, width: 1, base: "h", signed: false)
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_48,
    sig(:__VdfgRegularize_h69d40e7c_0_58, width: 14).concat(
      sig(:rw, width: 1).concat(
        sig(:dcacheread_data, width: 64)[0]
      )
    )
  assign :tlb_write_pf_error_code_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_21, width: 1),
      sig(:__VdfgRegularize_h69d40e7c_0_46, width: 16),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_22, width: 1),
        sig(:__VdfgRegularize_h69d40e7c_0_47, width: 16),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_23, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_48, width: 16),
          sig(:tlb_write_pf_error_code, width: 16)
        )
      )
    )
  assign :write_double_linear_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_27, width: 1),
      sig(:linear, width: 32),
      sig(:write_double_linear, width: 32)
    )
  assign :linear_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_24, width: 1),
      sig(:tlbwrite_address, width: 32),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_25, width: 1),
        sig(:tlbcheck_address, width: 32),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_26, width: 1),
          sig(:tlbread_address, width: 32),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_73, width: 1),
            sig(:tlbcoderequest_address, width: 32),
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_27, width: 1),
              (
                  lit(4096, width: 32, base: "h", signed: false) +
                  sig(:linear, width: 32)[31..12].concat(
                  lit(0, width: 12, base: "h", signed: false)
                )
              ),
              mux(
                sig(:__VdfgRegularize_h69d40e7c_0_72, width: 1),
                sig(:write_double_linear, width: 32),
                sig(:linear, width: 32)
              )
            )
          )
        )
      )
    )
  assign :tlb_code_pf_error_code_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_40, width: 1),
      sig(:__VdfgRegularize_h69d40e7c_0_46, width: 16),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_41, width: 1),
        sig(:__VdfgRegularize_h69d40e7c_0_47, width: 16),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_42, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_48, width: 16),
          sig(:tlb_code_pf_error_code, width: 16)
        )
      )
    )
  assign :wp_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_24, width: 1),
      sig(:cr0_wp, width: 1),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_25, width: 1),
        sig(:cr0_wp, width: 1),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_26, width: 1),
          sig(:cr0_wp, width: 1),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_73, width: 1),
            sig(:cr0_wp, width: 1),
            sig(:wp, width: 1)
          )
        )
      )
    )
  assign :tlbcheck_done_to_reg,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_11, width: 1) &
        (
            (
                sig(:__VdfgRegularize_h69d40e7c_0_28, width: 1) &
                sig(:__VdfgRegularize_h69d40e7c_0_29, width: 1)
            ) |
            sig(:tlbcheck_done, width: 1)
        )
    )
  assign :tlb_write_pf_cr2_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_21, width: 1),
      sig(:linear, width: 32),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_22, width: 1),
        sig(:linear, width: 32),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_23, width: 1),
          sig(:linear, width: 32),
          sig(:tlb_write_pf_cr2, width: 32)
        )
      )
    )
  assign :read_ac_to_reg,
    (
        (
            sig(:__VdfgRegularize_h69d40e7c_0_75, width: 1) &
            sig(:cond_6, width: 1)
        ) |
        sig(:read_ac, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_75,
    (
        (
          ~sig(:cond_5, width: 1)
        ) &
        sig(:__VdfgRegularize_h69d40e7c_0_76, width: 1)
    )
  assign :pte_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_18, width: 1),
      sig(:dcacheread_data, width: 64)[31..0],
      sig(:pte, width: 32)
    )
  assign :__VdfgRegularize_h69d40e7c_0_18,
    (
        (
            lit(4, width: 5, base: "h", signed: false) ==
            sig(:state, width: 5)
        ) &
        sig(:dcacheread_done, width: 1)
    )
  assign :tlb_check_pf_cr2_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_43, width: 1),
      sig(:linear, width: 32),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_44, width: 1),
        sig(:linear, width: 32),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_45, width: 1),
          sig(:linear, width: 32),
          sig(:tlb_check_pf_cr2, width: 32)
        )
      )
    )
  assign :tlb_read_pf_error_code_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_13, width: 1),
      sig(:__VdfgRegularize_h69d40e7c_0_46, width: 16),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_84, width: 1),
        sig(:__VdfgRegularize_h69d40e7c_0_47, width: 16),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_81, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_48, width: 16),
          sig(:tlb_read_pf_error_code, width: 16)
        )
      )
    )
  assign :write_double_state_to_reg,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_24, width: 1),
      mux(
        (
            sig(:cr0_pg, width: 1) &
            (
                (
                    sig(:tlbwrite_length, width: 3) !=
                    sig(:tlbwrite_length_full, width: 3)
                ) &
                (
                    lit(4096, width: 13, base: "h", signed: false) <=
                    (
                        lit(0, width: 1, base: "d", signed: false).concat(
                          sig(:tlbwrite_address, width: 32)[11..0]
                        ) +
                        lit(0, width: 10, base: "d", signed: false).concat(
                        sig(:tlbwrite_length_full, width: 3)
                      )
                    )
                )
            )
        ),
        lit(1, width: 2, base: "h", signed: false),
        lit(0, width: 2, base: "h", signed: false)
      ),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_25, width: 1),
        lit(0, width: 2, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_26, width: 1),
          lit(0, width: 2, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_73, width: 1),
            lit(0, width: 2, base: "h", signed: false),
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_27, width: 1),
              lit(2, width: 2, base: "h", signed: false),
              mux(
                sig(:__VdfgRegularize_h69d40e7c_0_72, width: 1),
                lit(0, width: 2, base: "h", signed: false),
                sig(:write_double_state, width: 2)
              )
            )
          )
        )
      )
    )
  assign :write_ac_to_reg,
    (
        (
            sig(:__VdfgRegularize_h69d40e7c_0_78, width: 1) &
            sig(:cond_3, width: 1)
        ) |
        sig(:write_ac, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_78,
    (
        (
          ~sig(:cond_2, width: 1)
        ) &
        sig(:__VdfgRegularize_h69d40e7c_0_79, width: 1)
    )
  assign :tlbcode_physical,
    sig(:dcacheread_address, width: 32)
  assign :dcacheread_address,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_71, width: 1),
      sig(:translate_physical, width: 32),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_92, width: 1),
        sig(:__VdfgRegularize_h69d40e7c_0_50, width: 32),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_69, width: 1),
          sig(:translate_physical, width: 32),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_91, width: 1),
            sig(:__VdfgRegularize_h69d40e7c_0_50, width: 32),
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_90, width: 1),
              sig(:__VdfgRegularize_h69d40e7c_0_50, width: 32),
              mux(
                sig(:tlbcode_do, width: 1),
                sig(:translate_physical, width: 32),
                mux(
                  sig(:__VdfgRegularize_h69d40e7c_0_88, width: 1),
                  sig(:__VdfgRegularize_h69d40e7c_0_50, width: 32),
                  mux(
                    sig(:cond_30, width: 1),
                    sig(:__VdfgRegularize_h69d40e7c_0_51, width: 32),
                    mux(
                      sig(:__VdfgRegularize_h69d40e7c_0_67, width: 1),
                      sig(:__VdfgRegularize_h69d40e7c_0_50, width: 32),
                      mux(
                        sig(:__VdfgRegularize_h69d40e7c_0_31, width: 1),
                        sig(:__VdfgRegularize_h69d40e7c_0_51, width: 32),
                        mux(
                          sig(:__VdfgRegularize_h69d40e7c_0_34, width: 1),
                          sig(:tlbregs_write_physical, width: 32),
                          mux(
                            sig(:cond_39, width: 1),
                            sig(:tlbregs_write_physical, width: 32),
                            mux(
                              sig(:__VdfgRegularize_h69d40e7c_0_37, width: 1),
                              sig(:tlbregs_write_physical, width: 32),
                              mux(
                                sig(:cond_41, width: 1),
                                sig(:__VdfgRegularize_h69d40e7c_0_51, width: 32),
                                sig(:tlbregs_write_physical, width: 32)
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
  assign :rw_to_reg,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_24, width: 1) |
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_25, width: 1),
          sig(:tlbcheck_rw, width: 1),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_26, width: 1),
            sig(:tlbread_rmw, width: 1),
            (
                (
                  ~sig(:__VdfgRegularize_h69d40e7c_0_73, width: 1)
                ) &
                sig(:rw, width: 1)
            )
          )
        )
    )
  assign :code_pf_to_reg,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_40, width: 1) |
        (
            sig(:__VdfgRegularize_h69d40e7c_0_41, width: 1) |
            (
                sig(:__VdfgRegularize_h69d40e7c_0_42, width: 1) |
                sig(:code_pf, width: 1)
            )
        )
    )
  assign :dcachewrite_do,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_69, width: 1) |
        (
            sig(:__VdfgRegularize_h69d40e7c_0_67, width: 1) |
            (
                sig(:__VdfgRegularize_h69d40e7c_0_31, width: 1) |
                (
                    sig(:__VdfgRegularize_h69d40e7c_0_34, width: 1) |
                    (
                        sig(:cond_41, width: 1) |
                        sig(:__VdfgRegularize_h69d40e7c_0_60, width: 1)
                    )
                )
            )
        )
    )
  assign :dcacheread_length,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_71, width: 1),
      sig(:tlbread_length, width: 4),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_92, width: 1),
        lit(4, width: 4, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_91, width: 1),
          lit(4, width: 4, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_90, width: 1),
            lit(4, width: 4, base: "h", signed: false),
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_88, width: 1),
              lit(4, width: 4, base: "h", signed: false),
              mux(
                sig(:cond_30, width: 1),
                lit(4, width: 4, base: "h", signed: false),
                mux(
                  sig(:cond_39, width: 1),
                  sig(:tlbread_length, width: 4),
                  mux(
                    sig(:__VdfgRegularize_h69d40e7c_0_37, width: 1),
                    sig(:tlbread_length, width: 4),
                    mux(
                      sig(:__VdfgRegularize_h69d40e7c_0_39, width: 1),
                      sig(:tlbread_length, width: 4),
                      lit(0, width: 4, base: "h", signed: false)
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :tlbregs_tlbflushall_do,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_79, width: 1) &
        sig(:cond_2, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_79,
    (
        (
          ~sig(:tlbflushsingle_do, width: 1)
        ) &
        sig(:cond_0, width: 1)
    )
  assign :dcachewrite_length,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_69, width: 1),
      sig(:tlbwrite_length, width: 3),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_67, width: 1),
        lit(4, width: 3, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_31, width: 1),
          lit(4, width: 3, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_34, width: 1),
            sig(:tlbwrite_length, width: 3),
            mux(
              sig(:cond_41, width: 1),
              lit(4, width: 3, base: "h", signed: false),
              mux(
                sig(:__VdfgRegularize_h69d40e7c_0_60, width: 1),
                sig(:tlbwrite_length, width: 3),
                lit(0, width: 3, base: "h", signed: false)
              )
            )
          )
        )
      )
    )
  assign :tlbregs_write_combined_rw,
    (
        sig(:tlbregs_write_do, width: 1) &
        sig(:rw_entry, width: 1)
    )
  assign :tlbregs_write_pcd,
    (
        sig(:tlbregs_write_do, width: 1) &
        sig(:pte, width: 32)[4]
    )
  assign :tlbread_retry,
    (
        sig(:cond_31, width: 1) &
        sig(:cond_29, width: 1)
    )
  assign :dcachewrite_address,
    sig(:dcacheread_address, width: 32)
  assign :tlbregs_write_pwt,
    (
        sig(:tlbregs_write_do, width: 1) &
        sig(:pte, width: 32)[3]
    )
  assign :dcachewrite_data,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_69, width: 1),
      sig(:tlbwrite_data, width: 32),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_67, width: 1),
        (
            lit(32, width: 32, base: "h", signed: false) |
            sig(:pde, width: 32)
        ),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_31, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_49, width: 32),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_34, width: 1),
            sig(:tlbwrite_data, width: 32),
            mux(
              sig(:cond_41, width: 1),
              sig(:__VdfgRegularize_h69d40e7c_0_49, width: 32),
              sig(:tlbwrite_data, width: 32)
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_49,
    (
        lit(32, width: 32, base: "h", signed: false) |
        (
            sig(:pte, width: 32) |
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_9, width: 1),
              lit(64, width: 32, base: "h", signed: false),
              lit(0, width: 32, base: "h", signed: false)
            )
        )
    )
  assign :translate_do,
    (
        (
            sig(:cond_15, width: 1) |
            (
                sig(:cond_19, width: 1) |
                (
                    sig(:cond_21, width: 1) |
                    sig(:cond_22, width: 1)
                )
            )
        ) &
        sig(:cr0_pg, width: 1)
    )
  assign :tlbregs_write_physical,
    sig(:pte, width: 32)[31..12].concat(
      sig(:linear, width: 32)[11..0]
    )
  assign :tlbflushsingle_done,
    (
        sig(:cond_0, width: 1) &
        sig(:tlbflushsingle_do, width: 1)
    )
  assign :dcachewrite_write_through,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_69, width: 1),
      (
          sig(:cr0_nw, width: 1) |
          (
              sig(:memtype_write_transparent, width: 1) |
              sig(:translate_pwt, width: 1)
          )
      ),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_67, width: 1),
        (
            sig(:cr0_nw, width: 1) |
            (
                sig(:cr3, width: 32)[3] |
                sig(:memtype_write_transparent, width: 1)
            )
        ),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_31, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_57, width: 1),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_34, width: 1),
            sig(:__VdfgRegularize_h69d40e7c_0_56, width: 1),
            mux(
              sig(:cond_41, width: 1),
              sig(:__VdfgRegularize_h69d40e7c_0_57, width: 1),
              (
                  sig(:__VdfgRegularize_h69d40e7c_0_60, width: 1) &
                  sig(:__VdfgRegularize_h69d40e7c_0_56, width: 1)
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_57,
    (
        sig(:cr0_nw, width: 1) |
        (
            sig(:pde, width: 32)[3] |
            sig(:memtype_write_transparent, width: 1)
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_56,
    (
        sig(:cr0_nw, width: 1) |
        (
            sig(:pte, width: 32)[3] |
            sig(:memtype_write_transparent, width: 1)
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_50,
    sig(:cr3, width: 32)[31..12].concat(
      sig(:linear, width: 32)[31..22].concat(
        lit(0, width: 2, base: "h", signed: false)
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_51,
    sig(:pde, width: 32)[31..12].concat(
      sig(:linear, width: 32)[21..12].concat(
        lit(0, width: 2, base: "h", signed: false)
      )
    )
  assign :dcachewrite_cache_disable,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_69, width: 1),
      sig(:__VdfgRegularize_h69d40e7c_0_55, width: 1),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_67, width: 1),
        sig(:__VdfgRegularize_h69d40e7c_0_54, width: 1),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_31, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_53, width: 1),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_34, width: 1),
            sig(:__VdfgRegularize_h69d40e7c_0_52, width: 1),
            mux(
              sig(:cond_41, width: 1),
              sig(:__VdfgRegularize_h69d40e7c_0_53, width: 1),
              (
                  sig(:__VdfgRegularize_h69d40e7c_0_60, width: 1) &
                  sig(:__VdfgRegularize_h69d40e7c_0_52, width: 1)
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_55,
    (
        sig(:cr0_cd, width: 1) |
        (
            sig(:memtype_cache_disable, width: 1) |
            sig(:translate_pcd, width: 1)
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_54,
    (
        sig(:cr0_cd, width: 1) |
        (
            sig(:cr3, width: 32)[4] |
            sig(:memtype_cache_disable, width: 1)
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_53,
    (
        sig(:cr0_cd, width: 1) |
        (
            sig(:pde, width: 32)[4] |
            sig(:memtype_cache_disable, width: 1)
        )
    )
  assign :__VdfgRegularize_h69d40e7c_0_52,
    (
        sig(:cr0_cd, width: 1) |
        (
            sig(:pte, width: 32)[4] |
            sig(:memtype_cache_disable, width: 1)
        )
    )
  assign :tlbregs_write_combined_su,
    (
        sig(:tlbregs_write_do, width: 1) &
        sig(:su_entry, width: 1)
    )
  assign :dcacheread_do,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_71, width: 1) |
        (
            sig(:__VdfgRegularize_h69d40e7c_0_92, width: 1) |
            (
                sig(:__VdfgRegularize_h69d40e7c_0_91, width: 1) |
                (
                    sig(:__VdfgRegularize_h69d40e7c_0_90, width: 1) |
                    (
                        sig(:__VdfgRegularize_h69d40e7c_0_88, width: 1) |
                        (
                            sig(:cond_30, width: 1) |
                            (
                                sig(:cond_39, width: 1) |
                                (
                                    (
                                        sig(:__VdfgRegularize_h69d40e7c_0_61, width: 1) |
                                        sig(:__VdfgRegularize_h69d40e7c_0_59, width: 1)
                                    ) &
                                    sig(:cond_29, width: 1)
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :prefetchfifo_signal_pf_do,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_40, width: 1) |
        (
            (
                sig(:__VdfgRegularize_h69d40e7c_0_87, width: 1) |
                sig(:__VdfgRegularize_h69d40e7c_0_19, width: 1)
            ) &
            sig(:cond_26, width: 1)
        )
    )
  assign :dcacheread_cache_disable,
    mux(
      sig(:__VdfgRegularize_h69d40e7c_0_71, width: 1),
      sig(:__VdfgRegularize_h69d40e7c_0_55, width: 1),
      mux(
        sig(:__VdfgRegularize_h69d40e7c_0_92, width: 1),
        sig(:__VdfgRegularize_h69d40e7c_0_54, width: 1),
        mux(
          sig(:__VdfgRegularize_h69d40e7c_0_91, width: 1),
          sig(:__VdfgRegularize_h69d40e7c_0_54, width: 1),
          mux(
            sig(:__VdfgRegularize_h69d40e7c_0_90, width: 1),
            sig(:__VdfgRegularize_h69d40e7c_0_54, width: 1),
            mux(
              sig(:__VdfgRegularize_h69d40e7c_0_88, width: 1),
              sig(:__VdfgRegularize_h69d40e7c_0_54, width: 1),
              mux(
                sig(:cond_30, width: 1),
                sig(:__VdfgRegularize_h69d40e7c_0_53, width: 1),
                mux(
                  sig(:cond_39, width: 1),
                  sig(:__VdfgRegularize_h69d40e7c_0_52, width: 1),
                  mux(
                    sig(:__VdfgRegularize_h69d40e7c_0_37, width: 1),
                    sig(:__VdfgRegularize_h69d40e7c_0_52, width: 1),
                    (
                        sig(:__VdfgRegularize_h69d40e7c_0_39, width: 1) &
                        sig(:__VdfgRegularize_h69d40e7c_0_52, width: 1)
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h69d40e7c_0_10,
    (
      ~sig(:cond_17, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_12,
    (
        sig(:cond_15, width: 1) &
        sig(:cond_17, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_15,
    (
      ~sig(:cond_26, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_16,
    (
      ~sig(:cond_27, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_17,
    (
      ~sig(:cond_28, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_20,
    (
        sig(:cond_19, width: 1) &
        sig(:cond_17, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_85,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_16, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_86, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_82,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_16, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_83, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_77,
    (
        (
          ~sig(:cond_3, width: 1)
        ) &
        sig(:__VdfgRegularize_h69d40e7c_0_78, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_76,
    (
        (
          ~sig(:cond_4, width: 1)
        ) &
        sig(:__VdfgRegularize_h69d40e7c_0_77, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_74,
    (
        (
          ~sig(:cond_6, width: 1)
        ) &
        sig(:__VdfgRegularize_h69d40e7c_0_75, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_89,
    (
        (
          ~sig(:cond_23, width: 1)
        ) &
        sig(:cond_22, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_66,
    (
        sig(:pde, width: 32)[5] &
        sig(:tlbregs_write_do, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_32,
    (
      ~sig(:cond_37, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_33,
    (
      ~sig(:cond_38, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_64,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_33, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_65, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_86,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_15, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_87, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_83,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_15, width: 1) &
        sig(:__VdfgRegularize_h69d40e7c_0_19, width: 1)
    )
  assign :__VdfgRegularize_h69d40e7c_0_58,
    sig(:su, width: 1)
  assign :__VdfgRegularize_h69d40e7c_0_80,
    (
        sig(:__VdfgRegularize_h69d40e7c_0_17, width: 1) &
        sig(:cond_29, width: 1)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :code_pf,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:pr_reset, width: 1)
              ) &
              sig(:code_pf_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :check_pf,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:exe_reset, width: 1)
              ) &
              sig(:check_pf_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_3,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :read_pf,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:rd_reset, width: 1)
              ) &
              sig(:read_pf_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :read_ac,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:rd_reset, width: 1)
              ) &
              sig(:read_ac_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_5,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :write_pf,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:wr_reset, width: 1)
              ) &
              sig(:write_pf_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_6,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :write_ac,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:wr_reset, width: 1)
              ) &
              sig(:write_ac_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_7,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:pr_reset, width: 1) & (lit(0, width: 5, base: "h", signed: false) != sig(:state, width: 5)))) do
        assign(
          :pr_reset_waiting,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block((lit(0, width: 5, base: "h", signed: false) == sig(:state, width: 5))) do
          assign(
            :pr_reset_waiting,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :pr_reset_waiting,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt((sig(:tlbflushall_do, width: 1) & (lit(0, width: 5, base: "h", signed: false) != sig(:state, width: 5)))) do
        assign(
          :tlbflushall_do_waiting,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:tlbregs_tlbflushall_do, width: 1)) do
          assign(
            :tlbflushall_do_waiting,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :tlbflushall_do_waiting,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_8,
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

  process :initial_block_9,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :tlbcode_cache_disable,
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :sequential_posedge_clk_9,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :current_type,
      mux(
        sig(:rst_n, width: 1),
        sig(:current_type_to_reg, width: 2),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_10,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :pde,
      mux(
        sig(:rst_n, width: 1),
        sig(:pde_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_11,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :state,
      mux(
        sig(:rst_n, width: 1),
        sig(:state_to_reg, width: 5),
        lit(0, width: 5, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_12,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_read_pf_cr2,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_read_pf_cr2_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_13,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_code_pf_cr2,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_code_pf_cr2_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_14,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :su,
      (
          sig(:rst_n, width: 1) &
          sig(:su_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_15,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_check_pf_error_code,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_check_pf_error_code_to_reg, width: 16),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_16,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_write_pf_error_code,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_write_pf_error_code_to_reg, width: 16),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_17,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :write_double_linear,
      mux(
        sig(:rst_n, width: 1),
        sig(:write_double_linear_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_18,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :linear,
      mux(
        sig(:rst_n, width: 1),
        sig(:linear_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_19,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_code_pf_error_code,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_code_pf_error_code_to_reg, width: 16),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_20,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :wp,
      (
          sig(:rst_n, width: 1) &
          sig(:wp_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_21,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlbcheck_done,
      (
          sig(:rst_n, width: 1) &
          sig(:tlbcheck_done_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_22,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_write_pf_cr2,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_write_pf_cr2_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_23,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :pte,
      mux(
        sig(:rst_n, width: 1),
        sig(:pte_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_24,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_check_pf_cr2,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_check_pf_cr2_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_25,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tlb_read_pf_error_code,
      mux(
        sig(:rst_n, width: 1),
        sig(:tlb_read_pf_error_code_to_reg, width: 16),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_26,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :write_double_state,
      mux(
        sig(:rst_n, width: 1),
        sig(:write_double_state_to_reg, width: 2),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_27,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :rw,
      (
          sig(:rst_n, width: 1) &
          sig(:rw_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  # Instances

  instance :tlb_memtype_inst, "tlb_memtype",
    ports: {
      physical: :dcacheread_address,
      cache_disable: :memtype_cache_disable,
      write_transparent: :memtype_write_transparent
    }
  instance :tlb_regs_inst, "tlb_regs",
    ports: {
      tlbflushsingle_do: :tlbflushsingle_done,
      tlbflushall_do: :tlbregs_tlbflushall_do,
      tlbregs_write_linear: :linear,
      translate_linear: :linear
    }

end
