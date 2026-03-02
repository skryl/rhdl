# frozen_string_literal: true

class WriteCommands < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: write_commands

  def self._import_decl_kinds
    {
      __VdfgBinToOneHot_Pre_h3ef411c2_0_0: :logic,
      __VdfgBinToOneHot_Tab_h3ef411c2_0_0: :logic,
      __VdfgRegularize_hcdb8a1dc_0_0: :logic,
      __VdfgRegularize_hcdb8a1dc_0_1: :logic,
      __VdfgRegularize_hcdb8a1dc_0_10: :logic,
      __VdfgRegularize_hcdb8a1dc_0_100: :logic,
      __VdfgRegularize_hcdb8a1dc_0_101: :logic,
      __VdfgRegularize_hcdb8a1dc_0_102: :logic,
      __VdfgRegularize_hcdb8a1dc_0_103: :logic,
      __VdfgRegularize_hcdb8a1dc_0_104: :logic,
      __VdfgRegularize_hcdb8a1dc_0_105: :logic,
      __VdfgRegularize_hcdb8a1dc_0_106: :logic,
      __VdfgRegularize_hcdb8a1dc_0_107: :logic,
      __VdfgRegularize_hcdb8a1dc_0_108: :logic,
      __VdfgRegularize_hcdb8a1dc_0_109: :logic,
      __VdfgRegularize_hcdb8a1dc_0_11: :logic,
      __VdfgRegularize_hcdb8a1dc_0_110: :logic,
      __VdfgRegularize_hcdb8a1dc_0_111: :logic,
      __VdfgRegularize_hcdb8a1dc_0_112: :logic,
      __VdfgRegularize_hcdb8a1dc_0_113: :logic,
      __VdfgRegularize_hcdb8a1dc_0_114: :logic,
      __VdfgRegularize_hcdb8a1dc_0_115: :logic,
      __VdfgRegularize_hcdb8a1dc_0_116: :logic,
      __VdfgRegularize_hcdb8a1dc_0_117: :logic,
      __VdfgRegularize_hcdb8a1dc_0_118: :logic,
      __VdfgRegularize_hcdb8a1dc_0_119: :logic,
      __VdfgRegularize_hcdb8a1dc_0_12: :logic,
      __VdfgRegularize_hcdb8a1dc_0_120: :logic,
      __VdfgRegularize_hcdb8a1dc_0_121: :logic,
      __VdfgRegularize_hcdb8a1dc_0_122: :logic,
      __VdfgRegularize_hcdb8a1dc_0_123: :logic,
      __VdfgRegularize_hcdb8a1dc_0_124: :logic,
      __VdfgRegularize_hcdb8a1dc_0_125: :logic,
      __VdfgRegularize_hcdb8a1dc_0_126: :logic,
      __VdfgRegularize_hcdb8a1dc_0_127: :logic,
      __VdfgRegularize_hcdb8a1dc_0_128: :logic,
      __VdfgRegularize_hcdb8a1dc_0_129: :logic,
      __VdfgRegularize_hcdb8a1dc_0_13: :logic,
      __VdfgRegularize_hcdb8a1dc_0_130: :logic,
      __VdfgRegularize_hcdb8a1dc_0_131: :logic,
      __VdfgRegularize_hcdb8a1dc_0_132: :logic,
      __VdfgRegularize_hcdb8a1dc_0_133: :logic,
      __VdfgRegularize_hcdb8a1dc_0_134: :logic,
      __VdfgRegularize_hcdb8a1dc_0_135: :logic,
      __VdfgRegularize_hcdb8a1dc_0_136: :logic,
      __VdfgRegularize_hcdb8a1dc_0_137: :logic,
      __VdfgRegularize_hcdb8a1dc_0_138: :logic,
      __VdfgRegularize_hcdb8a1dc_0_139: :logic,
      __VdfgRegularize_hcdb8a1dc_0_14: :logic,
      __VdfgRegularize_hcdb8a1dc_0_140: :logic,
      __VdfgRegularize_hcdb8a1dc_0_141: :logic,
      __VdfgRegularize_hcdb8a1dc_0_142: :logic,
      __VdfgRegularize_hcdb8a1dc_0_143: :logic,
      __VdfgRegularize_hcdb8a1dc_0_144: :logic,
      __VdfgRegularize_hcdb8a1dc_0_145: :logic,
      __VdfgRegularize_hcdb8a1dc_0_146: :logic,
      __VdfgRegularize_hcdb8a1dc_0_147: :logic,
      __VdfgRegularize_hcdb8a1dc_0_148: :logic,
      __VdfgRegularize_hcdb8a1dc_0_149: :logic,
      __VdfgRegularize_hcdb8a1dc_0_15: :logic,
      __VdfgRegularize_hcdb8a1dc_0_150: :logic,
      __VdfgRegularize_hcdb8a1dc_0_151: :logic,
      __VdfgRegularize_hcdb8a1dc_0_152: :logic,
      __VdfgRegularize_hcdb8a1dc_0_153: :logic,
      __VdfgRegularize_hcdb8a1dc_0_154: :logic,
      __VdfgRegularize_hcdb8a1dc_0_155: :logic,
      __VdfgRegularize_hcdb8a1dc_0_156: :logic,
      __VdfgRegularize_hcdb8a1dc_0_157: :logic,
      __VdfgRegularize_hcdb8a1dc_0_158: :logic,
      __VdfgRegularize_hcdb8a1dc_0_159: :logic,
      __VdfgRegularize_hcdb8a1dc_0_16: :logic,
      __VdfgRegularize_hcdb8a1dc_0_160: :logic,
      __VdfgRegularize_hcdb8a1dc_0_161: :logic,
      __VdfgRegularize_hcdb8a1dc_0_162: :logic,
      __VdfgRegularize_hcdb8a1dc_0_163: :logic,
      __VdfgRegularize_hcdb8a1dc_0_164: :logic,
      __VdfgRegularize_hcdb8a1dc_0_165: :logic,
      __VdfgRegularize_hcdb8a1dc_0_166: :logic,
      __VdfgRegularize_hcdb8a1dc_0_167: :logic,
      __VdfgRegularize_hcdb8a1dc_0_168: :logic,
      __VdfgRegularize_hcdb8a1dc_0_169: :logic,
      __VdfgRegularize_hcdb8a1dc_0_17: :logic,
      __VdfgRegularize_hcdb8a1dc_0_170: :logic,
      __VdfgRegularize_hcdb8a1dc_0_171: :logic,
      __VdfgRegularize_hcdb8a1dc_0_172: :logic,
      __VdfgRegularize_hcdb8a1dc_0_18: :logic,
      __VdfgRegularize_hcdb8a1dc_0_19: :logic,
      __VdfgRegularize_hcdb8a1dc_0_2: :logic,
      __VdfgRegularize_hcdb8a1dc_0_20: :logic,
      __VdfgRegularize_hcdb8a1dc_0_21: :logic,
      __VdfgRegularize_hcdb8a1dc_0_22: :logic,
      __VdfgRegularize_hcdb8a1dc_0_23: :logic,
      __VdfgRegularize_hcdb8a1dc_0_24: :logic,
      __VdfgRegularize_hcdb8a1dc_0_25: :logic,
      __VdfgRegularize_hcdb8a1dc_0_26: :logic,
      __VdfgRegularize_hcdb8a1dc_0_27: :logic,
      __VdfgRegularize_hcdb8a1dc_0_28: :logic,
      __VdfgRegularize_hcdb8a1dc_0_29: :logic,
      __VdfgRegularize_hcdb8a1dc_0_3: :logic,
      __VdfgRegularize_hcdb8a1dc_0_30: :logic,
      __VdfgRegularize_hcdb8a1dc_0_31: :logic,
      __VdfgRegularize_hcdb8a1dc_0_32: :logic,
      __VdfgRegularize_hcdb8a1dc_0_33: :logic,
      __VdfgRegularize_hcdb8a1dc_0_34: :logic,
      __VdfgRegularize_hcdb8a1dc_0_35: :logic,
      __VdfgRegularize_hcdb8a1dc_0_36: :logic,
      __VdfgRegularize_hcdb8a1dc_0_37: :logic,
      __VdfgRegularize_hcdb8a1dc_0_38: :logic,
      __VdfgRegularize_hcdb8a1dc_0_39: :logic,
      __VdfgRegularize_hcdb8a1dc_0_4: :logic,
      __VdfgRegularize_hcdb8a1dc_0_40: :logic,
      __VdfgRegularize_hcdb8a1dc_0_41: :logic,
      __VdfgRegularize_hcdb8a1dc_0_42: :logic,
      __VdfgRegularize_hcdb8a1dc_0_43: :logic,
      __VdfgRegularize_hcdb8a1dc_0_44: :logic,
      __VdfgRegularize_hcdb8a1dc_0_45: :logic,
      __VdfgRegularize_hcdb8a1dc_0_46: :logic,
      __VdfgRegularize_hcdb8a1dc_0_47: :logic,
      __VdfgRegularize_hcdb8a1dc_0_48: :logic,
      __VdfgRegularize_hcdb8a1dc_0_49: :logic,
      __VdfgRegularize_hcdb8a1dc_0_5: :logic,
      __VdfgRegularize_hcdb8a1dc_0_50: :logic,
      __VdfgRegularize_hcdb8a1dc_0_51: :logic,
      __VdfgRegularize_hcdb8a1dc_0_52: :logic,
      __VdfgRegularize_hcdb8a1dc_0_53: :logic,
      __VdfgRegularize_hcdb8a1dc_0_54: :logic,
      __VdfgRegularize_hcdb8a1dc_0_55: :logic,
      __VdfgRegularize_hcdb8a1dc_0_56: :logic,
      __VdfgRegularize_hcdb8a1dc_0_57: :logic,
      __VdfgRegularize_hcdb8a1dc_0_58: :logic,
      __VdfgRegularize_hcdb8a1dc_0_59: :logic,
      __VdfgRegularize_hcdb8a1dc_0_6: :logic,
      __VdfgRegularize_hcdb8a1dc_0_60: :logic,
      __VdfgRegularize_hcdb8a1dc_0_61: :logic,
      __VdfgRegularize_hcdb8a1dc_0_62: :logic,
      __VdfgRegularize_hcdb8a1dc_0_63: :logic,
      __VdfgRegularize_hcdb8a1dc_0_64: :logic,
      __VdfgRegularize_hcdb8a1dc_0_65: :logic,
      __VdfgRegularize_hcdb8a1dc_0_66: :logic,
      __VdfgRegularize_hcdb8a1dc_0_67: :logic,
      __VdfgRegularize_hcdb8a1dc_0_68: :logic,
      __VdfgRegularize_hcdb8a1dc_0_69: :logic,
      __VdfgRegularize_hcdb8a1dc_0_7: :logic,
      __VdfgRegularize_hcdb8a1dc_0_70: :logic,
      __VdfgRegularize_hcdb8a1dc_0_71: :logic,
      __VdfgRegularize_hcdb8a1dc_0_72: :logic,
      __VdfgRegularize_hcdb8a1dc_0_73: :logic,
      __VdfgRegularize_hcdb8a1dc_0_74: :logic,
      __VdfgRegularize_hcdb8a1dc_0_75: :logic,
      __VdfgRegularize_hcdb8a1dc_0_76: :logic,
      __VdfgRegularize_hcdb8a1dc_0_77: :logic,
      __VdfgRegularize_hcdb8a1dc_0_78: :logic,
      __VdfgRegularize_hcdb8a1dc_0_79: :logic,
      __VdfgRegularize_hcdb8a1dc_0_8: :logic,
      __VdfgRegularize_hcdb8a1dc_0_80: :logic,
      __VdfgRegularize_hcdb8a1dc_0_81: :logic,
      __VdfgRegularize_hcdb8a1dc_0_82: :logic,
      __VdfgRegularize_hcdb8a1dc_0_83: :logic,
      __VdfgRegularize_hcdb8a1dc_0_84: :logic,
      __VdfgRegularize_hcdb8a1dc_0_85: :logic,
      __VdfgRegularize_hcdb8a1dc_0_86: :logic,
      __VdfgRegularize_hcdb8a1dc_0_87: :logic,
      __VdfgRegularize_hcdb8a1dc_0_88: :logic,
      __VdfgRegularize_hcdb8a1dc_0_89: :logic,
      __VdfgRegularize_hcdb8a1dc_0_9: :logic,
      __VdfgRegularize_hcdb8a1dc_0_90: :logic,
      __VdfgRegularize_hcdb8a1dc_0_91: :logic,
      __VdfgRegularize_hcdb8a1dc_0_92: :logic,
      __VdfgRegularize_hcdb8a1dc_0_93: :logic,
      __VdfgRegularize_hcdb8a1dc_0_94: :logic,
      __VdfgRegularize_hcdb8a1dc_0_95: :logic,
      __VdfgRegularize_hcdb8a1dc_0_96: :logic,
      __VdfgRegularize_hcdb8a1dc_0_97: :logic,
      __VdfgRegularize_hcdb8a1dc_0_98: :logic,
      __VdfgRegularize_hcdb8a1dc_0_99: :logic,
      __VdfgRegularize_hcdb8a1dc_1_0: :logic,
      _unused_ok: :wire,
      aflag_arith: :wire,
      cflag_arith: :wire,
      cond_0: :wire,
      cond_1: :wire,
      cond_10: :wire,
      cond_100: :wire,
      cond_101: :wire,
      cond_102: :wire,
      cond_103: :wire,
      cond_104: :wire,
      cond_105: :wire,
      cond_107: :wire,
      cond_109: :wire,
      cond_11: :wire,
      cond_110: :wire,
      cond_111: :wire,
      cond_112: :wire,
      cond_113: :wire,
      cond_114: :wire,
      cond_117: :wire,
      cond_118: :wire,
      cond_119: :wire,
      cond_12: :wire,
      cond_120: :wire,
      cond_121: :wire,
      cond_122: :wire,
      cond_123: :wire,
      cond_124: :wire,
      cond_125: :wire,
      cond_128: :wire,
      cond_129: :wire,
      cond_130: :wire,
      cond_131: :wire,
      cond_132: :wire,
      cond_133: :wire,
      cond_135: :wire,
      cond_136: :wire,
      cond_139: :wire,
      cond_14: :wire,
      cond_141: :wire,
      cond_142: :wire,
      cond_143: :wire,
      cond_145: :wire,
      cond_146: :wire,
      cond_147: :wire,
      cond_149: :wire,
      cond_15: :wire,
      cond_152: :wire,
      cond_155: :wire,
      cond_156: :wire,
      cond_158: :wire,
      cond_160: :wire,
      cond_162: :wire,
      cond_164: :wire,
      cond_167: :wire,
      cond_168: :wire,
      cond_169: :wire,
      cond_171: :wire,
      cond_174: :wire,
      cond_175: :wire,
      cond_176: :wire,
      cond_177: :wire,
      cond_178: :wire,
      cond_179: :wire,
      cond_18: :wire,
      cond_180: :wire,
      cond_181: :wire,
      cond_189: :wire,
      cond_19: :wire,
      cond_192: :wire,
      cond_193: :wire,
      cond_196: :wire,
      cond_197: :wire,
      cond_198: :wire,
      cond_199: :wire,
      cond_20: :wire,
      cond_200: :wire,
      cond_201: :wire,
      cond_202: :wire,
      cond_204: :wire,
      cond_21: :wire,
      cond_210: :wire,
      cond_212: :wire,
      cond_214: :wire,
      cond_215: :wire,
      cond_216: :wire,
      cond_22: :wire,
      cond_220: :wire,
      cond_223: :wire,
      cond_225: :wire,
      cond_227: :wire,
      cond_23: :wire,
      cond_230: :wire,
      cond_231: :wire,
      cond_232: :wire,
      cond_234: :wire,
      cond_235: :wire,
      cond_238: :wire,
      cond_24: :wire,
      cond_242: :wire,
      cond_244: :wire,
      cond_247: :wire,
      cond_248: :wire,
      cond_249: :wire,
      cond_250: :wire,
      cond_253: :wire,
      cond_254: :wire,
      cond_255: :wire,
      cond_258: :wire,
      cond_260: :wire,
      cond_261: :wire,
      cond_263: :wire,
      cond_264: :wire,
      cond_265: :wire,
      cond_266: :wire,
      cond_272: :wire,
      cond_273: :wire,
      cond_274: :wire,
      cond_32: :wire,
      cond_33: :wire,
      cond_34: :wire,
      cond_35: :wire,
      cond_36: :wire,
      cond_37: :wire,
      cond_38: :wire,
      cond_42: :wire,
      cond_44: :wire,
      cond_5: :wire,
      cond_51: :wire,
      cond_54: :wire,
      cond_55: :wire,
      cond_57: :wire,
      cond_60: :wire,
      cond_62: :wire,
      cond_63: :wire,
      cond_65: :wire,
      cond_66: :wire,
      cond_67: :wire,
      cond_7: :wire,
      cond_70: :wire,
      cond_73: :wire,
      cond_75: :wire,
      cond_76: :wire,
      cond_78: :wire,
      cond_8: :wire,
      cond_80: :wire,
      cond_81: :wire,
      cond_82: :wire,
      cond_87: :wire,
      cond_88: :wire,
      cond_89: :wire,
      cond_9: :wire,
      cond_90: :wire,
      cond_91: :wire,
      cond_93: :wire,
      cond_96: :wire,
      cond_97: :wire,
      cond_98: :wire,
      oflag_arith: :wire,
      pflag_result: :wire,
      sflag_result: :wire,
      task_cs: :wire,
      task_ds: :wire,
      task_eflags: :wire,
      task_es: :wire,
      task_fs: :wire,
      task_gs: :wire,
      task_ldtr: :wire,
      task_ss: :wire,
      task_trap: :wire,
      w_sub_arith: :wire,
      wr_IRET_to_v86_cs: :wire,
      wr_IRET_to_v86_ds: :wire,
      wr_IRET_to_v86_fs: :wire,
      wr_ecx_minus_1: :wire,
      wr_task_rpl_to_reg: :wire,
      wr_task_switch_linear: :wire,
      wr_task_switch_linear_next: :wire,
      wr_task_switch_linear_reg: :reg
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :real_mode
  input :v8086_mode
  input :protected_mode
  input :cpl, width: 2
  input :tr_base, width: 32
  input :eip, width: 32
  input :io_allow_check_needed
  input :exc_push_error
  input :exc_eip, width: 32
  input :glob_descriptor, width: 64
  input :glob_desc_base, width: 32
  input :glob_param_1, width: 32
  input :glob_param_2, width: 32
  input :glob_param_3, width: 32
  input :glob_param_4, width: 32
  input :glob_param_5, width: 32
  input :wr_ready
  input :wr_decoder, width: 16
  input :wr_cmd, width: 7
  input :wr_cmdex, width: 4
  input :wr_is_8bit
  input :wr_address_16bit
  input :wr_operand_16bit
  input :wr_operand_32bit
  input :wr_mult_overflow
  input :wr_arith_index, width: 4
  input :wr_modregrm_mod, width: 2
  input :wr_modregrm_reg, width: 3
  input :wr_modregrm_rm, width: 3
  input :wr_dst_is_memory
  input :wr_dst_is_reg
  input :wr_dst_is_rm
  input :wr_dst_is_implicit_reg
  input :wr_dst_is_edx_eax
  input :wr_dst_is_eax
  input :wr_arith_add_carry
  input :wr_arith_adc_carry
  input :wr_arith_sbb_carry
  input :wr_arith_sub_carry
  input :result, width: 32
  input :result2, width: 32
  input :wr_src, width: 32
  input :wr_dst, width: 32
  input :result_signals, width: 5
  input :result_push, width: 32
  input :exe_buffer, width: 32
  input :exe_buffer_shifted, width: 464
  output :wr_glob_param_1_set
  output :wr_glob_param_1_value, width: 32
  output :wr_glob_param_3_set
  output :wr_glob_param_3_value, width: 32
  output :wr_glob_param_4_set
  output :wr_glob_param_4_value, width: 32
  output :wr_debug_trap_clear
  output :wr_debug_task_trigger
  output :wr_int
  output :wr_int_soft_int
  output :wr_int_soft_int_ib
  output :wr_int_vector, width: 8
  output :wr_exception_external_set
  output :wr_exception_finished
  output :wr_inhibit_interrupts
  output :wr_inhibit_interrupts_and_debug
  input :write_for_wr_ready
  output :write_rmw_virtual
  output :write_virtual
  output :write_rmw_system_dword
  output :write_system_word
  output :write_system_dword
  output :write_system_busy_tss
  output :write_system_touch
  output :write_length_word
  output :write_length_dword
  output :wr_system_dword, width: 32
  output :wr_system_linear, width: 32
  output :write_regrm
  output :write_eax
  output :wr_regrm_word
  output :wr_regrm_dword
  output :wr_not_finished
  output :wr_hlt_in_progress
  output :wr_string_in_progress
  output :wr_waiting
  output :wr_req_reset_pr
  output :wr_req_reset_dec
  output :wr_req_reset_micro
  output :wr_req_reset_rd
  output :wr_req_reset_exe
  output :wr_zflag_result
  output :wr_task_rpl, width: 2
  output :wr_one_cycle_wait
  output :write_stack_virtual
  output :write_new_stack_virtual
  output :wr_push_length_word
  output :wr_push_length_dword
  input :wr_stack_esp, width: 32
  input :wr_new_stack_esp, width: 32
  output :wr_push_ss_fault_check
  input :wr_push_ss_fault
  output :wr_new_push_ss_fault_check
  input :wr_new_push_ss_fault
  output :wr_error_code, width: 16
  output :wr_make_esp_speculative
  output :wr_make_esp_commit
  input :wr_string_ignore
  input :wr_prefix_group_1_rep, width: 2
  input :wr_string_zf_finish
  input :wr_string_es_fault
  input :wr_string_finish
  input :wr_esi_final, width: 32
  input :wr_edi_final, width: 32
  input :wr_ecx_final, width: 32
  output :wr_string_gp_fault_check
  output :write_string_es_virtual
  output :write_io
  input :write_io_for_wr_ready
  output :wr_seg_sel, width: 16
  output :wr_seg_cache_valid
  output :wr_seg_rpl, width: 2
  output :wr_seg_cache_mask, width: 64
  output :write_seg_cache
  output :write_seg_sel
  output :write_seg_cache_valid
  output :write_seg_rpl
  output :wr_validate_seg_regs
  output :tlbflushall_do
  output :eax_to_reg, width: 32
  output :ebx_to_reg, width: 32
  output :ecx_to_reg, width: 32
  output :edx_to_reg, width: 32
  output :esi_to_reg, width: 32
  output :edi_to_reg, width: 32
  output :ebp_to_reg, width: 32
  output :esp_to_reg, width: 32
  output :cr0_pe_to_reg
  output :cr0_mp_to_reg
  output :cr0_em_to_reg
  output :cr0_ts_to_reg
  output :cr0_ne_to_reg
  output :cr0_wp_to_reg
  output :cr0_am_to_reg
  output :cr0_nw_to_reg
  output :cr0_cd_to_reg
  output :cr0_pg_to_reg
  output :cr2_to_reg, width: 32
  output :cr3_to_reg, width: 32
  output :cflag_to_reg
  output :pflag_to_reg
  output :aflag_to_reg
  output :zflag_to_reg
  output :sflag_to_reg
  output :oflag_to_reg
  output :tflag_to_reg
  output :iflag_to_reg
  output :dflag_to_reg
  output :iopl_to_reg, width: 2
  output :ntflag_to_reg
  output :rflag_to_reg
  output :vmflag_to_reg
  output :acflag_to_reg
  output :idflag_to_reg
  output :gdtr_base_to_reg, width: 32
  output :gdtr_limit_to_reg, width: 16
  output :idtr_base_to_reg, width: 32
  output :idtr_limit_to_reg, width: 16
  output :dr0_to_reg, width: 32
  output :dr1_to_reg, width: 32
  output :dr2_to_reg, width: 32
  output :dr3_to_reg, width: 32
  output :dr6_breakpoints_to_reg, width: 4
  output :dr6_b12_to_reg
  output :dr6_bd_to_reg
  output :dr6_bs_to_reg
  output :dr6_bt_to_reg
  output :dr7_to_reg, width: 32
  output :es_to_reg, width: 16
  output :ds_to_reg, width: 16
  output :ss_to_reg, width: 16
  output :fs_to_reg, width: 16
  output :gs_to_reg, width: 16
  output :cs_to_reg, width: 16
  output :ldtr_to_reg, width: 16
  output :tr_to_reg, width: 16
  output :es_cache_to_reg, width: 64
  output :ds_cache_to_reg, width: 64
  output :ss_cache_to_reg, width: 64
  output :fs_cache_to_reg, width: 64
  output :gs_cache_to_reg, width: 64
  output :cs_cache_to_reg, width: 64
  output :ldtr_cache_to_reg, width: 64
  output :tr_cache_to_reg, width: 64
  output :es_cache_valid_to_reg
  output :ds_cache_valid_to_reg
  output :ss_cache_valid_to_reg
  output :fs_cache_valid_to_reg
  output :gs_cache_valid_to_reg
  output :cs_cache_valid_to_reg
  output :ldtr_cache_valid_to_reg
  output :es_rpl_to_reg, width: 2
  output :ds_rpl_to_reg, width: 2
  output :ss_rpl_to_reg, width: 2
  output :fs_rpl_to_reg, width: 2
  output :gs_rpl_to_reg, width: 2
  output :cs_rpl_to_reg, width: 2
  output :ldtr_rpl_to_reg, width: 2
  output :tr_rpl_to_reg, width: 2
  input :eax, width: 32
  input :ebx, width: 32
  input :ecx, width: 32
  input :edx, width: 32
  input :esi, width: 32
  input :edi, width: 32
  input :ebp, width: 32
  input :esp, width: 32
  input :cr0_pe
  input :cr0_mp
  input :cr0_em
  input :cr0_ts
  input :cr0_ne
  input :cr0_wp
  input :cr0_am
  input :cr0_nw
  input :cr0_cd
  input :cr0_pg
  input :cr2, width: 32
  input :cr3, width: 32
  input :cflag
  input :pflag
  input :aflag
  input :zflag
  input :sflag
  input :oflag
  input :tflag
  input :iflag
  input :dflag
  input :iopl, width: 2
  input :ntflag
  input :rflag
  input :vmflag
  input :acflag
  input :idflag
  input :gdtr_base, width: 32
  input :gdtr_limit, width: 16
  input :idtr_base, width: 32
  input :idtr_limit, width: 16
  input :dr0, width: 32
  input :dr1, width: 32
  input :dr2, width: 32
  input :dr3, width: 32
  input :dr6_breakpoints, width: 4
  input :dr6_b12
  input :dr6_bd
  input :dr6_bs
  input :dr6_bt
  input :dr7, width: 32
  input :es, width: 16
  input :ds, width: 16
  input :ss, width: 16
  input :fs, width: 16
  input :gs, width: 16
  input :cs, width: 16
  input :ldtr, width: 16
  input :tr, width: 16
  input :es_cache, width: 64
  input :ds_cache, width: 64
  input :ss_cache, width: 64
  input :fs_cache, width: 64
  input :gs_cache, width: 64
  input :cs_cache, width: 64
  input :ldtr_cache, width: 64
  input :tr_cache, width: 64
  input :es_cache_valid
  input :ds_cache_valid
  input :ss_cache_valid
  input :fs_cache_valid
  input :gs_cache_valid
  input :cs_cache_valid
  input :ldtr_cache_valid
  input :es_rpl, width: 2
  input :ds_rpl, width: 2
  input :ss_rpl, width: 2
  input :fs_rpl, width: 2
  input :gs_rpl, width: 2
  input :cs_rpl, width: 2
  input :ldtr_rpl, width: 2
  input :tr_rpl, width: 2

  # Signals

  signal :__VdfgBinToOneHot_Pre_h3ef411c2_0_0, width: 7
  signal :__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 116
  signal :__VdfgRegularize_hcdb8a1dc_0_0
  signal :__VdfgRegularize_hcdb8a1dc_0_1
  signal :__VdfgRegularize_hcdb8a1dc_0_10
  signal :__VdfgRegularize_hcdb8a1dc_0_100
  signal :__VdfgRegularize_hcdb8a1dc_0_101
  signal :__VdfgRegularize_hcdb8a1dc_0_102
  signal :__VdfgRegularize_hcdb8a1dc_0_103
  signal :__VdfgRegularize_hcdb8a1dc_0_104
  signal :__VdfgRegularize_hcdb8a1dc_0_105
  signal :__VdfgRegularize_hcdb8a1dc_0_106
  signal :__VdfgRegularize_hcdb8a1dc_0_107
  signal :__VdfgRegularize_hcdb8a1dc_0_108
  signal :__VdfgRegularize_hcdb8a1dc_0_109
  signal :__VdfgRegularize_hcdb8a1dc_0_11
  signal :__VdfgRegularize_hcdb8a1dc_0_110
  signal :__VdfgRegularize_hcdb8a1dc_0_111
  signal :__VdfgRegularize_hcdb8a1dc_0_112
  signal :__VdfgRegularize_hcdb8a1dc_0_113
  signal :__VdfgRegularize_hcdb8a1dc_0_114
  signal :__VdfgRegularize_hcdb8a1dc_0_115
  signal :__VdfgRegularize_hcdb8a1dc_0_116
  signal :__VdfgRegularize_hcdb8a1dc_0_117
  signal :__VdfgRegularize_hcdb8a1dc_0_118
  signal :__VdfgRegularize_hcdb8a1dc_0_119
  signal :__VdfgRegularize_hcdb8a1dc_0_12
  signal :__VdfgRegularize_hcdb8a1dc_0_120
  signal :__VdfgRegularize_hcdb8a1dc_0_121, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_122, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_123, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_124, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_125, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_126
  signal :__VdfgRegularize_hcdb8a1dc_0_127
  signal :__VdfgRegularize_hcdb8a1dc_0_128
  signal :__VdfgRegularize_hcdb8a1dc_0_129
  signal :__VdfgRegularize_hcdb8a1dc_0_13
  signal :__VdfgRegularize_hcdb8a1dc_0_130
  signal :__VdfgRegularize_hcdb8a1dc_0_131, width: 16
  signal :__VdfgRegularize_hcdb8a1dc_0_132
  signal :__VdfgRegularize_hcdb8a1dc_0_133
  signal :__VdfgRegularize_hcdb8a1dc_0_134
  signal :__VdfgRegularize_hcdb8a1dc_0_135
  signal :__VdfgRegularize_hcdb8a1dc_0_136
  signal :__VdfgRegularize_hcdb8a1dc_0_137
  signal :__VdfgRegularize_hcdb8a1dc_0_138
  signal :__VdfgRegularize_hcdb8a1dc_0_139
  signal :__VdfgRegularize_hcdb8a1dc_0_14
  signal :__VdfgRegularize_hcdb8a1dc_0_140
  signal :__VdfgRegularize_hcdb8a1dc_0_141
  signal :__VdfgRegularize_hcdb8a1dc_0_142
  signal :__VdfgRegularize_hcdb8a1dc_0_143
  signal :__VdfgRegularize_hcdb8a1dc_0_144
  signal :__VdfgRegularize_hcdb8a1dc_0_145
  signal :__VdfgRegularize_hcdb8a1dc_0_146
  signal :__VdfgRegularize_hcdb8a1dc_0_147
  signal :__VdfgRegularize_hcdb8a1dc_0_148
  signal :__VdfgRegularize_hcdb8a1dc_0_149
  signal :__VdfgRegularize_hcdb8a1dc_0_15
  signal :__VdfgRegularize_hcdb8a1dc_0_150
  signal :__VdfgRegularize_hcdb8a1dc_0_151
  signal :__VdfgRegularize_hcdb8a1dc_0_152
  signal :__VdfgRegularize_hcdb8a1dc_0_153
  signal :__VdfgRegularize_hcdb8a1dc_0_154
  signal :__VdfgRegularize_hcdb8a1dc_0_155
  signal :__VdfgRegularize_hcdb8a1dc_0_156
  signal :__VdfgRegularize_hcdb8a1dc_0_157
  signal :__VdfgRegularize_hcdb8a1dc_0_158
  signal :__VdfgRegularize_hcdb8a1dc_0_159
  signal :__VdfgRegularize_hcdb8a1dc_0_16
  signal :__VdfgRegularize_hcdb8a1dc_0_160
  signal :__VdfgRegularize_hcdb8a1dc_0_161
  signal :__VdfgRegularize_hcdb8a1dc_0_162
  signal :__VdfgRegularize_hcdb8a1dc_0_163
  signal :__VdfgRegularize_hcdb8a1dc_0_164
  signal :__VdfgRegularize_hcdb8a1dc_0_165
  signal :__VdfgRegularize_hcdb8a1dc_0_166
  signal :__VdfgRegularize_hcdb8a1dc_0_167
  signal :__VdfgRegularize_hcdb8a1dc_0_168
  signal :__VdfgRegularize_hcdb8a1dc_0_169
  signal :__VdfgRegularize_hcdb8a1dc_0_17
  signal :__VdfgRegularize_hcdb8a1dc_0_170
  signal :__VdfgRegularize_hcdb8a1dc_0_171
  signal :__VdfgRegularize_hcdb8a1dc_0_172
  signal :__VdfgRegularize_hcdb8a1dc_0_18
  signal :__VdfgRegularize_hcdb8a1dc_0_19
  signal :__VdfgRegularize_hcdb8a1dc_0_2
  signal :__VdfgRegularize_hcdb8a1dc_0_20
  signal :__VdfgRegularize_hcdb8a1dc_0_21
  signal :__VdfgRegularize_hcdb8a1dc_0_22
  signal :__VdfgRegularize_hcdb8a1dc_0_23
  signal :__VdfgRegularize_hcdb8a1dc_0_24
  signal :__VdfgRegularize_hcdb8a1dc_0_25
  signal :__VdfgRegularize_hcdb8a1dc_0_26
  signal :__VdfgRegularize_hcdb8a1dc_0_27
  signal :__VdfgRegularize_hcdb8a1dc_0_28
  signal :__VdfgRegularize_hcdb8a1dc_0_29
  signal :__VdfgRegularize_hcdb8a1dc_0_3
  signal :__VdfgRegularize_hcdb8a1dc_0_30, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_31
  signal :__VdfgRegularize_hcdb8a1dc_0_32
  signal :__VdfgRegularize_hcdb8a1dc_0_33
  signal :__VdfgRegularize_hcdb8a1dc_0_34
  signal :__VdfgRegularize_hcdb8a1dc_0_35
  signal :__VdfgRegularize_hcdb8a1dc_0_36
  signal :__VdfgRegularize_hcdb8a1dc_0_37
  signal :__VdfgRegularize_hcdb8a1dc_0_38
  signal :__VdfgRegularize_hcdb8a1dc_0_39
  signal :__VdfgRegularize_hcdb8a1dc_0_4
  signal :__VdfgRegularize_hcdb8a1dc_0_40
  signal :__VdfgRegularize_hcdb8a1dc_0_41
  signal :__VdfgRegularize_hcdb8a1dc_0_42
  signal :__VdfgRegularize_hcdb8a1dc_0_43
  signal :__VdfgRegularize_hcdb8a1dc_0_44
  signal :__VdfgRegularize_hcdb8a1dc_0_45
  signal :__VdfgRegularize_hcdb8a1dc_0_46
  signal :__VdfgRegularize_hcdb8a1dc_0_47
  signal :__VdfgRegularize_hcdb8a1dc_0_48
  signal :__VdfgRegularize_hcdb8a1dc_0_49
  signal :__VdfgRegularize_hcdb8a1dc_0_5
  signal :__VdfgRegularize_hcdb8a1dc_0_50
  signal :__VdfgRegularize_hcdb8a1dc_0_51
  signal :__VdfgRegularize_hcdb8a1dc_0_52
  signal :__VdfgRegularize_hcdb8a1dc_0_53
  signal :__VdfgRegularize_hcdb8a1dc_0_54
  signal :__VdfgRegularize_hcdb8a1dc_0_55
  signal :__VdfgRegularize_hcdb8a1dc_0_56
  signal :__VdfgRegularize_hcdb8a1dc_0_57
  signal :__VdfgRegularize_hcdb8a1dc_0_58
  signal :__VdfgRegularize_hcdb8a1dc_0_59
  signal :__VdfgRegularize_hcdb8a1dc_0_6
  signal :__VdfgRegularize_hcdb8a1dc_0_60
  signal :__VdfgRegularize_hcdb8a1dc_0_61, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_62
  signal :__VdfgRegularize_hcdb8a1dc_0_63, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_64, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_65, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_66, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_67
  signal :__VdfgRegularize_hcdb8a1dc_0_68
  signal :__VdfgRegularize_hcdb8a1dc_0_69
  signal :__VdfgRegularize_hcdb8a1dc_0_7
  signal :__VdfgRegularize_hcdb8a1dc_0_70, width: 16
  signal :__VdfgRegularize_hcdb8a1dc_0_71
  signal :__VdfgRegularize_hcdb8a1dc_0_72
  signal :__VdfgRegularize_hcdb8a1dc_0_73, width: 32
  signal :__VdfgRegularize_hcdb8a1dc_0_74
  signal :__VdfgRegularize_hcdb8a1dc_0_75
  signal :__VdfgRegularize_hcdb8a1dc_0_76
  signal :__VdfgRegularize_hcdb8a1dc_0_77
  signal :__VdfgRegularize_hcdb8a1dc_0_78
  signal :__VdfgRegularize_hcdb8a1dc_0_79
  signal :__VdfgRegularize_hcdb8a1dc_0_8
  signal :__VdfgRegularize_hcdb8a1dc_0_80
  signal :__VdfgRegularize_hcdb8a1dc_0_81
  signal :__VdfgRegularize_hcdb8a1dc_0_82
  signal :__VdfgRegularize_hcdb8a1dc_0_83
  signal :__VdfgRegularize_hcdb8a1dc_0_84
  signal :__VdfgRegularize_hcdb8a1dc_0_85
  signal :__VdfgRegularize_hcdb8a1dc_0_86
  signal :__VdfgRegularize_hcdb8a1dc_0_87
  signal :__VdfgRegularize_hcdb8a1dc_0_88
  signal :__VdfgRegularize_hcdb8a1dc_0_89
  signal :__VdfgRegularize_hcdb8a1dc_0_9
  signal :__VdfgRegularize_hcdb8a1dc_0_90
  signal :__VdfgRegularize_hcdb8a1dc_0_91
  signal :__VdfgRegularize_hcdb8a1dc_0_92
  signal :__VdfgRegularize_hcdb8a1dc_0_93
  signal :__VdfgRegularize_hcdb8a1dc_0_94
  signal :__VdfgRegularize_hcdb8a1dc_0_95
  signal :__VdfgRegularize_hcdb8a1dc_0_96
  signal :__VdfgRegularize_hcdb8a1dc_0_97
  signal :__VdfgRegularize_hcdb8a1dc_0_98
  signal :__VdfgRegularize_hcdb8a1dc_0_99
  signal :__VdfgRegularize_hcdb8a1dc_1_0
  signal :_unused_ok
  signal :aflag_arith
  signal :cflag_arith
  signal :cond_0
  signal :cond_1
  signal :cond_10
  signal :cond_100
  signal :cond_101
  signal :cond_102
  signal :cond_103
  signal :cond_104
  signal :cond_105
  signal :cond_107
  signal :cond_109
  signal :cond_11
  signal :cond_110
  signal :cond_111
  signal :cond_112
  signal :cond_113
  signal :cond_114
  signal :cond_117
  signal :cond_118
  signal :cond_119
  signal :cond_12
  signal :cond_120
  signal :cond_121
  signal :cond_122
  signal :cond_123
  signal :cond_124
  signal :cond_125
  signal :cond_128
  signal :cond_129
  signal :cond_130
  signal :cond_131
  signal :cond_132
  signal :cond_133
  signal :cond_135
  signal :cond_136
  signal :cond_139
  signal :cond_14
  signal :cond_141
  signal :cond_142
  signal :cond_143
  signal :cond_145
  signal :cond_146
  signal :cond_147
  signal :cond_149
  signal :cond_15
  signal :cond_152
  signal :cond_155
  signal :cond_156
  signal :cond_158
  signal :cond_160
  signal :cond_162
  signal :cond_164
  signal :cond_167
  signal :cond_168
  signal :cond_169
  signal :cond_171
  signal :cond_174
  signal :cond_175
  signal :cond_176
  signal :cond_177
  signal :cond_178
  signal :cond_179
  signal :cond_18
  signal :cond_180
  signal :cond_181
  signal :cond_189
  signal :cond_19
  signal :cond_192
  signal :cond_193
  signal :cond_196
  signal :cond_197
  signal :cond_198
  signal :cond_199
  signal :cond_20
  signal :cond_200
  signal :cond_201
  signal :cond_202
  signal :cond_204
  signal :cond_21
  signal :cond_210
  signal :cond_212
  signal :cond_214
  signal :cond_215
  signal :cond_216
  signal :cond_22
  signal :cond_220
  signal :cond_223
  signal :cond_225
  signal :cond_227
  signal :cond_23
  signal :cond_230
  signal :cond_231
  signal :cond_232
  signal :cond_234
  signal :cond_235
  signal :cond_238
  signal :cond_24
  signal :cond_242
  signal :cond_244
  signal :cond_247
  signal :cond_248
  signal :cond_249
  signal :cond_250
  signal :cond_253
  signal :cond_254
  signal :cond_255
  signal :cond_258
  signal :cond_260
  signal :cond_261
  signal :cond_263
  signal :cond_264
  signal :cond_265
  signal :cond_266
  signal :cond_272
  signal :cond_273
  signal :cond_274
  signal :cond_32
  signal :cond_33
  signal :cond_34
  signal :cond_35
  signal :cond_36
  signal :cond_37
  signal :cond_38
  signal :cond_42
  signal :cond_44
  signal :cond_5
  signal :cond_51
  signal :cond_54
  signal :cond_55
  signal :cond_57
  signal :cond_60
  signal :cond_62
  signal :cond_63
  signal :cond_65
  signal :cond_66
  signal :cond_67
  signal :cond_7
  signal :cond_70
  signal :cond_73
  signal :cond_75
  signal :cond_76
  signal :cond_78
  signal :cond_8
  signal :cond_80
  signal :cond_81
  signal :cond_82
  signal :cond_87
  signal :cond_88
  signal :cond_89
  signal :cond_9
  signal :cond_90
  signal :cond_91
  signal :cond_93
  signal :cond_96
  signal :cond_97
  signal :cond_98
  signal :oflag_arith
  signal :pflag_result
  signal :sflag_result
  signal :task_cs, width: 16
  signal :task_ds, width: 16
  signal :task_eflags, width: 32
  signal :task_es, width: 16
  signal :task_fs, width: 16
  signal :task_gs, width: 16
  signal :task_ldtr, width: 16
  signal :task_ss, width: 16
  signal :task_trap, width: 16
  signal :w_sub_arith
  signal :wr_IRET_to_v86_cs, width: 16
  signal :wr_IRET_to_v86_ds, width: 16
  signal :wr_IRET_to_v86_fs, width: 16
  signal :wr_ecx_minus_1, width: 32
  signal :wr_task_rpl_to_reg, width: 2
  signal :wr_task_switch_linear, width: 32
  signal :wr_task_switch_linear_next, width: 32
  signal :wr_task_switch_linear_reg, width: 32

  # Assignments

  assign :sflag_result,
    mux(
      sig(:wr_is_8bit, width: 1),
      sig(:result, width: 32)[7],
      mux(
        sig(:wr_operand_16bit, width: 1),
        sig(:result, width: 32)[15],
        sig(:result, width: 32)[31]
      )
    )
  assign :wr_zflag_result,
    mux(
      sig(:wr_is_8bit, width: 1),
      (
          lit(0, width: 8, base: "h", signed: false) ==
          sig(:result, width: 32)[7..0]
      ),
      mux(
        sig(:wr_operand_16bit, width: 1),
        (
            lit(0, width: 16, base: "h", signed: false) ==
            sig(:result, width: 32)[15..0]
        ),
        (
            lit(0, width: 32, base: "h", signed: false) ==
            sig(:result, width: 32)
        )
      )
    )
  assign :pflag_result,
    (
      ~(
          sig(:result, width: 32)[7] ^
          (
              sig(:result, width: 32)[6] ^
              (
                  sig(:result, width: 32)[5] ^
                  (
                      sig(:result, width: 32)[4] ^
                      (
                          sig(:result, width: 32)[3] ^
                          (
                              sig(:result, width: 32)[2] ^
                              (
                                  sig(:result, width: 32)[1] ^
                                  sig(:result, width: 32)[0]
                              )
                          )
                      )
                  )
              )
          )
      )
    )
  assign :w_sub_arith,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_0, width: 1) |
        (
            (
                lit(13, width: 4, base: "h", signed: false) ==
                sig(:wr_arith_index, width: 4)
            ) |
            (
                lit(15, width: 4, base: "h", signed: false) ==
                sig(:wr_arith_index, width: 4)
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_0,
    (
        lit(11, width: 4, base: "h", signed: false) ==
        sig(:wr_arith_index, width: 4)
    )
  assign :aflag_arith,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_1, width: 1) &
        (
            sig(:wr_src, width: 32)[4] ^
            (
                sig(:wr_dst, width: 32)[4] ^
                sig(:result, width: 32)[4]
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_1,
    (
      ~(
          (
            ~sig(:wr_arith_index, width: 4)[3]
          ) |
          (
              (
                  lit(9, width: 4, base: "h", signed: false) ==
                  sig(:wr_arith_index, width: 4)
              ) |
              (
                  (
                      lit(12, width: 4, base: "h", signed: false) ==
                      sig(:wr_arith_index, width: 4)
                  ) |
                  (
                      lit(14, width: 4, base: "h", signed: false) ==
                      sig(:wr_arith_index, width: 4)
                  )
              )
          )
      )
    )
  assign :cflag_arith,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_1, width: 1) &
        mux(
          sig(:wr_is_8bit, width: 1),
          (
              sig(:wr_src, width: 32)[8] ^
              (
                  sig(:wr_dst, width: 32)[8] ^
                  sig(:result, width: 32)[8]
              )
          ),
          mux(
            sig(:wr_operand_16bit, width: 1),
            (
                sig(:wr_src, width: 32)[16] ^
                (
                    sig(:wr_dst, width: 32)[16] ^
                    sig(:result, width: 32)[16]
                )
            ),
            mux(
              (
                  lit(8, width: 4, base: "h", signed: false) ==
                  sig(:wr_arith_index, width: 4)
              ),
              sig(:wr_arith_add_carry, width: 1),
              mux(
                (
                    lit(10, width: 4, base: "h", signed: false) ==
                    sig(:wr_arith_index, width: 4)
                ),
                sig(:wr_arith_adc_carry, width: 1),
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_0, width: 1),
                  sig(:wr_arith_sbb_carry, width: 1),
                  sig(:wr_arith_sub_carry, width: 1)
                )
              )
            )
          )
        )
    )
  assign :oflag_arith,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_1, width: 1) &
        mux(
          (
              sig(:w_sub_arith, width: 1) &
              sig(:wr_is_8bit, width: 1)
          ),
          (
              (
                  sig(:__VdfgRegularize_hcdb8a1dc_0_2, width: 1) &
                  sig(:__VdfgRegularize_hcdb8a1dc_0_171, width: 1)
              ) |
              (
                  sig(:wr_src, width: 32)[7] &
                  sig(:__VdfgRegularize_hcdb8a1dc_0_172, width: 1)
              )
          ),
          mux(
            (
                sig(:w_sub_arith, width: 1) &
                sig(:wr_operand_16bit, width: 1)
            ),
            (
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_3, width: 1) &
                    sig(:__VdfgRegularize_hcdb8a1dc_0_169, width: 1)
                ) |
                (
                    sig(:wr_src, width: 32)[15] &
                    sig(:__VdfgRegularize_hcdb8a1dc_0_170, width: 1)
                )
            ),
            mux(
              sig(:w_sub_arith, width: 1),
              (
                  (
                      sig(:__VdfgRegularize_hcdb8a1dc_0_4, width: 1) &
                      sig(:__VdfgRegularize_hcdb8a1dc_0_167, width: 1)
                  ) |
                  (
                      sig(:wr_src, width: 32)[31] &
                      sig(:__VdfgRegularize_hcdb8a1dc_0_168, width: 1)
                  )
              ),
              mux(
                sig(:wr_is_8bit, width: 1),
                (
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_2, width: 1) &
                        sig(:__VdfgRegularize_hcdb8a1dc_0_172, width: 1)
                    ) |
                    (
                        sig(:wr_src, width: 32)[7] &
                        sig(:__VdfgRegularize_hcdb8a1dc_0_171, width: 1)
                    )
                ),
                mux(
                  sig(:wr_operand_16bit, width: 1),
                  (
                      (
                          sig(:__VdfgRegularize_hcdb8a1dc_0_3, width: 1) &
                          sig(:__VdfgRegularize_hcdb8a1dc_0_170, width: 1)
                      ) |
                      (
                          sig(:wr_src, width: 32)[15] &
                          sig(:__VdfgRegularize_hcdb8a1dc_0_169, width: 1)
                      )
                  ),
                  (
                      (
                          sig(:__VdfgRegularize_hcdb8a1dc_0_4, width: 1) &
                          sig(:__VdfgRegularize_hcdb8a1dc_0_168, width: 1)
                      ) |
                      (
                          sig(:wr_src, width: 32)[31] &
                          sig(:__VdfgRegularize_hcdb8a1dc_0_167, width: 1)
                      )
                  )
                )
              )
            )
          )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_2,
    (
      ~sig(:wr_src, width: 32)[7]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_171,
    (
        (
          ~sig(:result, width: 32)[7]
        ) &
        sig(:wr_dst, width: 32)[7]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_172,
    (
        (
          ~sig(:wr_dst, width: 32)[7]
        ) &
        sig(:result, width: 32)[7]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_3,
    (
      ~sig(:wr_src, width: 32)[15]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_169,
    (
        (
          ~sig(:result, width: 32)[15]
        ) &
        sig(:wr_dst, width: 32)[15]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_170,
    (
        (
          ~sig(:wr_dst, width: 32)[15]
        ) &
        sig(:result, width: 32)[15]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_4,
    (
      ~sig(:wr_src, width: 32)[31]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_167,
    (
        (
          ~sig(:result, width: 32)[31]
        ) &
        sig(:wr_dst, width: 32)[31]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_168,
    (
        (
          ~sig(:wr_dst, width: 32)[31]
        ) &
        sig(:result, width: 32)[31]
    )
  assign :task_eflags,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:exe_buffer_shifted, width: 464)[383..368]
      ),
      sig(:exe_buffer_shifted, width: 464)[399..368]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_5,
    (
        lit(3, width: 4, base: "h", signed: false) >=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :task_es,
    sig(:exe_buffer_shifted, width: 464)[111..96]
  assign :task_cs,
    sig(:exe_buffer_shifted, width: 464)[95..80]
  assign :task_ss,
    sig(:exe_buffer_shifted, width: 464)[79..64]
  assign :task_ds,
    sig(:exe_buffer_shifted, width: 464)[63..48]
  assign :task_fs,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
      lit(0, width: 16, base: "h", signed: false),
      sig(:wr_IRET_to_v86_ds, width: 16)
    )
  assign :wr_IRET_to_v86_ds,
    sig(:exe_buffer_shifted, width: 464)[47..32]
  assign :task_gs,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
      lit(0, width: 16, base: "h", signed: false),
      sig(:exe_buffer_shifted, width: 464)[31..16]
    )
  assign :task_ldtr,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
      sig(:wr_IRET_to_v86_ds, width: 16),
      sig(:wr_IRET_to_v86_fs, width: 16)
    )
  assign :wr_IRET_to_v86_fs,
    sig(:exe_buffer_shifted, width: 464)[15..0]
  assign :task_trap,
    sig(:exe_buffer, width: 32)[15..0]
  assign :wr_IRET_to_v86_cs,
    sig(:glob_param_1, width: 32)[15..0]
  assign :wr_ecx_minus_1,
    (
        sig(:ecx, width: 32) -
        lit(1, width: 32, base: "h", signed: false)
    )
  assign :wr_task_switch_linear,
    mux(
      (
          sig(:cond_230, width: 1) &
          sig(:__VdfgRegularize_hcdb8a1dc_0_6, width: 1)
      ),
      (
          lit(14, width: 32, base: "h", signed: false) +
          sig(:tr_base, width: 32)
      ),
      mux(
        (
            sig(:cond_230, width: 1) &
            sig(:__VdfgRegularize_hcdb8a1dc_0_7, width: 1)
        ),
        (
            lit(32, width: 32, base: "h", signed: false) +
            sig(:tr_base, width: 32)
        ),
        sig(:wr_task_switch_linear_next, width: 32)
      )
    )
  assign :cond_230,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] &
        sig(:cond_123, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_6,
    (
        lit(3, width: 4, base: "h", signed: false) >=
        sig(:tr_cache, width: 64)[43..40]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_7,
    (
        lit(3, width: 4, base: "h", signed: false) <
        sig(:tr_cache, width: 64)[43..40]
    )
  assign :wr_task_switch_linear_next,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_6, width: 1),
      (
          lit(2, width: 32, base: "h", signed: false) +
          sig(:wr_task_switch_linear_reg, width: 32)
      ),
      (
          lit(4, width: 32, base: "h", signed: false) +
          sig(:wr_task_switch_linear_reg, width: 32)
      )
    )
  assign :cond_0,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[1] &
        sig(:cond_81, width: 1)
    )
  assign :cond_81,
    (
        lit(0, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_1,
    (
        sig(:cond_9, width: 1) &
        sig(:wr_dst_is_memory, width: 1)
    )
  assign :cond_9,
    (
      ~sig(:write_for_wr_ready, width: 1)
    )
  assign :cond_5,
    sig(:result_signals, width: 5)[0]
  assign :cond_7,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_10, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_10,
    (
        sig(:cond_248, width: 1) |
        sig(:cond_249, width: 1)
    )
  assign :cond_8,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_11, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_11,
    (
        sig(:cond_250, width: 1) |
        sig(:cond_120, width: 1)
    )
  assign :cond_10,
    (
      ~sig(:wr_push_ss_fault, width: 1)
    )
  assign :cond_11,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_12, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_12,
    (
        sig(:cond_81, width: 1) |
        sig(:cond_260, width: 1)
    )
  assign :cond_12,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
        (
            sig(:cond_247, width: 1) |
            sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1)
        )
    )
  assign :cond_247,
    (
        lit(4, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_13,
    (
        lit(10, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_14,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_14, width: 1) |
            sig(:__VdfgRegularize_hcdb8a1dc_0_15, width: 1)
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_14,
    (
        lit(13, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_15,
    (
        lit(14, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_15,
    (
      ~sig(:wr_new_push_ss_fault, width: 1)
    )
  assign :cond_18,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_17, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_17,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_15, width: 1) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_16, width: 1)
    )
  assign :cond_19,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[5] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_166, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_166,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_12, width: 1) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_9, width: 1)
    )
  assign :cond_20,
    (
        lit(3, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_21,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[6] &
        (
          ~sig(:wr_cmdex, width: 4)[3]
        )
    )
  assign :cond_22,
    (
        sig(:cond_10, width: 1) &
        sig(:write_for_wr_ready, width: 1)
    )
  assign :cond_23,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[6] &
        sig(:wr_cmdex, width: 4)[3]
    )
  assign :cond_24,
    (
        lit(7, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_32,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[13]
  assign :cond_33,
    (
      ~sig(:wr_string_ignore, width: 1)
    )
  assign :cond_34,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:wr_prefix_group_1_rep, width: 2)
    )
  assign :cond_35,
    (
        sig(:wr_string_ignore, width: 1) |
        sig(:wr_string_zf_finish, width: 1)
    )
  assign :cond_36,
    (
        sig(:cond_33, width: 1) &
        (
            (
              ~sig(:wr_string_zf_finish, width: 1)
            ) &
            sig(:cond_34, width: 1)
        )
    )
  assign :cond_37,
    (
        lit(14, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_38,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[15] &
        (
            lit(2, width: 4, base: "h", signed: false) !=
            sig(:wr_cmdex, width: 4)
        )
    )
  assign :cond_42,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[18] &
        sig(:cond_20, width: 1)
    )
  assign :cond_44,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_165, width: 1) &
        sig(:cond_260, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_165,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[19] |
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[20] |
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[21]
        )
    )
  assign :cond_260,
    (
        lit(1, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_51,
    (
        lit(27, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_54,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_18, width: 1) |
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_19, width: 1) |
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_14, width: 1) |
                        sig(:__VdfgRegularize_hcdb8a1dc_0_17, width: 1)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_18,
    (
        lit(11, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_19,
    (
        lit(12, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_55,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[30] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_166, width: 1)
    )
  assign :cond_57,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] &
        sig(:cond_81, width: 1)
    )
  assign :cond_60,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] &
        sig(:cond_250, width: 1)
    )
  assign :cond_250,
    (
        lit(7, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_62,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] &
        sig(:cond_248, width: 1)
    )
  assign :cond_248,
    (
        lit(5, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_63,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[30] &
        sig(:cond_249, width: 1)
    )
  assign :cond_249,
    (
        lit(6, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_65,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_21, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_21,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_9, width: 1) |
        sig(:cond_247, width: 1)
    )
  assign :cond_66,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[32] |
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[31]
    )
  assign :cond_67,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[33] &
        sig(:cond_81, width: 1)
    )
  assign :cond_70,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[33] &
        sig(:cond_260, width: 1)
    )
  assign :cond_73,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:glob_param_1, width: 32)[18..16]
    )
  assign :cond_75,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[34] &
        sig(:cond_81, width: 1)
    )
  assign :cond_76,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[34] &
        sig(:cond_260, width: 1)
    )
  assign :cond_78,
    (
        lit(9, width: 5, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)[6..2]
    )
  assign :cond_80,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[35] &
        (
            lit(2, width: 4, base: "h", signed: false) >=
            sig(:wr_cmdex, width: 4)
        )
    )
  assign :cond_82,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[35] &
        sig(:cond_20, width: 1)
    )
  assign :cond_87,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[35] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_16, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_16,
    (
        lit(15, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_88,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1)
    )
  assign :cond_89,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_8,
    (
        lit(2, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_90,
    (
        sig(:cpl, width: 2) <=
        sig(:iopl, width: 2)
    )
  assign :cond_91,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:cpl, width: 2)
    )
  assign :cond_93,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
        sig(:cond_250, width: 1)
    )
  assign :cond_96,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[41] &
        sig(:cond_81, width: 1)
    )
  assign :cond_97,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[41] &
        sig(:cond_260, width: 1)
    )
  assign :cond_98,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[41] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
    )
  assign :cond_100,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[43] |
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[42]
    )
  assign :cond_101,
    (
      ~sig(:wr_is_8bit, width: 1)
    )
  assign :cond_102,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[44]
  assign :cond_103,
    (
      ~sig(:result_signals, width: 5)[4]
    )
  assign :cond_104,
    sig(:result_signals, width: 5)[3]
  assign :cond_105,
    sig(:result_signals, width: 5)[2]
  assign :cond_107,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[45] &
        sig(:cond_260, width: 1)
    )
  assign :cond_109,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[46] &
        sig(:cond_81, width: 1)
    )
  assign :cond_110,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[46] &
        sig(:cond_260, width: 1)
    )
  assign :cond_111,
    (
        sig(:cr0_pe, width: 1) ^
        sig(:result2, width: 32)[0]
    )
  assign :cond_112,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[46] &
        sig(:cond_20, width: 1)
    )
  assign :cond_113,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[46] &
        sig(:cond_247, width: 1)
    )
  assign :cond_114,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:wr_decoder, width: 16)[13..11]
    )
  assign :cond_117,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:wr_decoder, width: 16)[13..11]
    )
  assign :cond_118,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:wr_decoder, width: 16)[13..11]
    )
  assign :cond_119,
    (
        sig(:cond_121, width: 1) |
        sig(:cond_122, width: 1)
    )
  assign :cond_121,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[47]
  assign :cond_122,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[48]
  assign :cond_120,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_123,
    (
        lit(9, width: 4, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_124,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[49]
  assign :cond_125,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)[2..0]
    )
  assign :cond_128,
    (
        lit(51, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_129,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[52]
  assign :cond_130,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[53] &
        sig(:cond_81, width: 1)
    )
  assign :cond_131,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[53] &
        sig(:cond_260, width: 1)
    )
  assign :cond_132,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[53] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_9, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_9,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1) |
        sig(:cond_20, width: 1)
    )
  assign :cond_133,
    (
        lit(54, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_135,
    (
        lit(55, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_136,
    (
        lit(28, width: 6, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)[6..1]
    )
  assign :cond_139,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)[6..3]
    )
  assign :cond_141,
    (
        lit(7, width: 3, base: "h", signed: false) !=
        sig(:wr_cmd, width: 7)[2..0]
    )
  assign :cond_142,
    (
        lit(59, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_143,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[60]
  assign :cond_145,
    (
        lit(61, width: 7, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)
    )
  assign :cond_146,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[62]
  assign :cond_147,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
        sig(:cond_260, width: 1)
    )
  assign :cond_149,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
        sig(:cond_20, width: 1)
    )
  assign :cond_152,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[72]
  assign :cond_155,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[73] &
        sig(:cond_81, width: 1)
    )
  assign :cond_156,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[73] &
        sig(:cond_260, width: 1)
    )
  assign :cond_158,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[74]
  assign :cond_160,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[75] &
        sig(:cond_260, width: 1)
    )
  assign :cond_162,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[75] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
    )
  assign :cond_164,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[76]
  assign :cond_167,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[77]
  assign :cond_168,
    (
        (
          ~sig(:io_allow_check_needed, width: 1)
        ) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
    )
  assign :cond_169,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[78]
  assign :cond_171,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_27, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_27,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[79] |
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[80]
    )
  assign :cond_174,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
            sig(:cond_247, width: 1)
        ) |
        (
            (
                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
                sig(:cond_260, width: 1)
            ) |
            (
                (
                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] &
                    sig(:cond_81, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] &
                        sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] &
                            sig(:__VdfgRegularize_hcdb8a1dc_0_18, width: 1)
                        ) |
                        (
                            (
                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[88] &
                                sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
                            ) |
                            (
                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] &
                                sig(:cond_247, width: 1)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :cond_175,
    (
      ~sig(:glob_descriptor, width: 64)[40]
    )
  assign :cond_176,
    (
      ~sig(:__VdfgRegularize_hcdb8a1dc_1_0, width: 1)
    )
  assign :cond_177,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[5] &
            sig(:cond_248, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[30] &
            sig(:cond_247, width: 1)
        )
    )
  assign :cond_178,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
            sig(:cond_248, width: 1)
        ) |
        (
            (
                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] &
                sig(:cond_260, width: 1)
            ) |
            (
                (
                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] &
                    sig(:__VdfgRegularize_hcdb8a1dc_0_18, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[5] &
                        sig(:cond_249, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] &
                            sig(:__VdfgRegularize_hcdb8a1dc_0_19, width: 1)
                        ) |
                        (
                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[88] &
                            sig(:cond_20, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :cond_179,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
            sig(:cond_120, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
            sig(:cond_249, width: 1)
        )
    )
  assign :cond_180,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
            sig(:cond_123, width: 1)
        ) |
        (
            (
                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
                sig(:cond_120, width: 1)
            ) |
            (
                (
                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[5] &
                    sig(:cond_247, width: 1)
                ) |
                (
                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[30] &
                    sig(:cond_248, width: 1)
                )
            )
        )
    )
  assign :cond_181,
    (
        sig(:cond_175, width: 1) &
        (
            lit(0, width: 14, base: "h", signed: false) !=
            sig(:glob_param_1, width: 32)[15..2]
        )
    )
  assign :cond_189,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] &
            sig(:__VdfgRegularize_hcdb8a1dc_0_20, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] &
            sig(:__VdfgRegularize_hcdb8a1dc_0_166, width: 1)
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_20,
    (
        sig(:cond_120, width: 1) |
        sig(:cond_123, width: 1)
    )
  assign :cond_192,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[83]
  assign :cond_193,
    (
      ~sig(:wr_string_es_fault, width: 1)
    )
  assign :cond_196,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[84]
  assign :cond_197,
    (
        sig(:cond_81, width: 1) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
    )
  assign :cond_198,
    (
        sig(:wr_string_finish, width: 1) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_26, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_26,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:wr_prefix_group_1_rep, width: 2)
    )
  assign :cond_199,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[85]
  assign :cond_200,
    (
        sig(:io_allow_check_needed, width: 1) &
        sig(:cond_81, width: 1)
    )
  assign :cond_201,
    (
      ~sig(:write_io_for_wr_ready, width: 1)
    )
  assign :cond_202,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[86]
  assign :cond_204,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] &
        (
            sig(:cond_247, width: 1) |
            sig(:cond_120, width: 1)
        )
    )
  assign :cond_210,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[89]
  assign :cond_212,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[90]
  assign :cond_214,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[92]
  assign :cond_215,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[93]
  assign :cond_216,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[94] &
        sig(:cond_81, width: 1)
    )
  assign :cond_220,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[96]
  assign :cond_223,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[98] &
        sig(:cond_81, width: 1)
    )
  assign :cond_225,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] &
        sig(:cond_260, width: 1)
    )
  assign :cond_227,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] &
        sig(:cond_249, width: 1)
    )
  assign :cond_231,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1)
    )
  assign :cond_232,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[100] &
        (
            lit(13, width: 4, base: "h", signed: false) >=
            sig(:wr_cmdex, width: 4)
        )
    )
  assign :cond_234,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_18, width: 1)
    )
  assign :cond_235,
    (
        (
            lit(2, width: 2, base: "h", signed: false) ==
            sig(:glob_param_1, width: 32)[17..16]
        ) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_29, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_29,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:glob_param_1, width: 32)[17..16]
    )
  assign :cond_238,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[102] &
        sig(:cond_81, width: 1)
    )
  assign :cond_242,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[102] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
    )
  assign :cond_244,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[102] &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_25, width: 1) &
            (
                lit(8, width: 4, base: "h", signed: false) >=
                sig(:wr_cmdex, width: 4)
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_25,
    (
        lit(3, width: 4, base: "h", signed: false) <=
        sig(:wr_cmdex, width: 4)
    )
  assign :cond_253,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[102] &
        sig(:cond_123, width: 1)
    )
  assign :cond_254,
    sig(:glob_param_3, width: 32)[16]
  assign :cond_255,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[102] &
        sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1)
    )
  assign :cond_258,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[104] |
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[105]
    )
  assign :cond_261,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[106]
  assign :cond_263,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[109]
  assign :cond_264,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:wr_cmdex, width: 4)[2..0]
    )
  assign :cond_265,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[110] &
        sig(:cond_81, width: 1)
    )
  assign :cond_266,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[110] &
        sig(:cond_260, width: 1)
    )
  assign :cond_272,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[112] |
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[113]
    )
  assign :cond_273,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[114] |
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[115]
    )
  assign :cond_274,
    (
        lit(58, width: 6, base: "h", signed: false) ==
        sig(:wr_cmd, width: 7)[6..1]
    )
  assign :gdtr_limit_to_reg,
    mux(
      (
          sig(:__VdfgRegularize_hcdb8a1dc_0_32, width: 1) &
          sig(:cond_120, width: 1)
      ),
      sig(:result2, width: 32)[15..0],
      sig(:gdtr_limit, width: 16)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_32,
    (
        sig(:cond_119, width: 1) &
        sig(:cond_121, width: 1)
    )
  assign :tr_to_reg,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      sig(:wr_IRET_to_v86_cs, width: 16),
      sig(:tr, width: 16)
    )
  assign :wr_glob_param_3_set,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[102] &
        sig(:cond_260, width: 1)
    )
  assign :cr0_nw_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
      sig(:result2, width: 32)[29],
      sig(:cr0_nw, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_33,
    (
        sig(:cond_113, width: 1) &
        sig(:cond_114, width: 1)
    )
  assign :ss_rpl_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:exe_buffer_shifted, width: 464)[65..64],
        sig(:ss_rpl, width: 2)
      )
    )
  assign :cr0_cd_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
      sig(:result2, width: 32)[30],
      sig(:cr0_cd, width: 1)
    )
  assign :cs_cache_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3888, width: 28, base: "h", signed: false).concat(
        sig(:wr_IRET_to_v86_cs, width: 16).concat(
          lit(65535, width: 20, base: "h", signed: false)
        )
      ),
      mux(
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1) &
            (
                (
                  ~sig(:result2, width: 32)[0]
                ) &
                sig(:cr0_pe, width: 1)
            )
        ),
        sig(:cs_cache, width: 64)[63..48].concat(
          lit(1, width: 1, base: "h", signed: false).concat(
            sig(:cs_cache, width: 64)[46..45].concat(
              lit(19, width: 5, base: "h", signed: false).concat(
                sig(:cs_cache, width: 64)[39..0]
              )
            )
          )
        ),
        sig(:cs_cache, width: 64)
      )
    )
  assign :tr_cache_to_reg,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      (
          lit(2199023255552, width: 64, base: "h", signed: false) |
          sig(:glob_descriptor, width: 64)
      ),
      sig(:tr_cache, width: 64)
    )
  assign :fs_cache_valid_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_35, width: 1) &
        (
            sig(:cond_87, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_36, width: 1) &
                sig(:fs_cache_valid, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_35,
    (
      ~sig(:__VdfgRegularize_hcdb8a1dc_0_34, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_36,
    (
      ~sig(:wr_glob_param_3_set, width: 1)
    )
  assign :ldtr_to_reg,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      sig(:task_ldtr, width: 16),
      sig(:ldtr, width: 16)
    )
  assign :dr6_b12_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_37, width: 1),
      sig(:result2, width: 32)[12],
      sig(:dr6_b12, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_37,
    (
        sig(:cond_266, width: 1) &
        (
            (
                lit(4, width: 3, base: "h", signed: false) ==
                sig(:wr_decoder, width: 16)[13..11]
            ) |
            (
                lit(6, width: 3, base: "h", signed: false) ==
                sig(:wr_decoder, width: 16)[13..11]
            )
        )
    )
  assign :zflag_to_reg,
    mux(
      sig(:cond_0, width: 1),
      sig(:wr_zflag_result, width: 1),
      mux(
        sig(:cond_24, width: 1),
        sig(:wr_zflag_result, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1),
          sig(:wr_zflag_result, width: 1),
          mux(
            sig(:cond_37, width: 1),
            sig(:wr_zflag_result, width: 1),
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_38, width: 1) |
                (
                    (
                      ~(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_39, width: 1) &
                          sig(:wr_regrm_word, width: 1)
                      )
                    ) &
                    mux(
                      sig(:cond_51, width: 1),
                      sig(:eax, width: 32)[14],
                      mux(
                        sig(:cond_66, width: 1),
                        sig(:wr_zflag_result, width: 1),
                        mux(
                          sig(:cond_82, width: 1),
                          sig(:glob_param_3, width: 32)[6],
                          mux(
                            sig(:cond_87, width: 1),
                            sig(:glob_param_3, width: 32)[6],
                            mux(
                              sig(:cond_89, width: 1),
                              sig(:glob_param_3, width: 32)[6],
                              mux(
                                sig(:cond_93, width: 1),
                                sig(:glob_param_5, width: 32)[6],
                                mux(
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_40, width: 1),
                                  sig(:wr_zflag_result, width: 1),
                                  mux(
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
                                    sig(:wr_zflag_result, width: 1),
                                    (
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_41, width: 1) |
                                        mux(
                                          sig(:__VdfgRegularize_hcdb8a1dc_0_162, width: 1),
                                          sig(:wr_zflag_result, width: 1),
                                          mux(
                                            sig(:cond_133, width: 1),
                                            sig(:wr_zflag_result, width: 1),
                                            mux(
                                              sig(:__VdfgRegularize_hcdb8a1dc_0_42, width: 1),
                                              sig(:wr_zflag_result, width: 1),
                                              mux(
                                                sig(:cond_139, width: 1),
                                                sig(:wr_zflag_result, width: 1),
                                                mux(
                                                  sig(:cond_142, width: 1),
                                                  sig(:wr_zflag_result, width: 1),
                                                  mux(
                                                    sig(:cond_145, width: 1),
                                                    sig(:wr_zflag_result, width: 1),
                                                    (
                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_43, width: 1) |
                                                        (
                                                            (
                                                              ~(
                                                                  (
                                                                    ~sig(:wr_dst_is_reg, width: 1)
                                                                  ) &
                                                                  sig(:cond_171, width: 1)
                                                              )
                                                            ) &
                                                            mux(
                                                              (
                                                                  sig(:__VdfgRegularize_hcdb8a1dc_0_28, width: 1) &
                                                                  sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
                                                              ),
                                                              sig(:wr_dst_is_reg, width: 1),
                                                              mux(
                                                                sig(:cond_216, width: 1),
                                                                sig(:result2, width: 32)[6],
                                                                mux(
                                                                  sig(:wr_glob_param_3_set, width: 1),
                                                                  sig(:task_eflags, width: 32)[6],
                                                                  mux(
                                                                    sig(:cond_272, width: 1),
                                                                    sig(:wr_zflag_result, width: 1),
                                                                    mux(
                                                                      sig(:cond_273, width: 1),
                                                                      sig(:wr_zflag_result, width: 1),
                                                                      (
                                                                          (
                                                                              sig(:cond_274, width: 1) &
                                                                              sig(:cond_5, width: 1)
                                                                          ) |
                                                                          (
                                                                              (
                                                                                ~sig(:__VdfgRegularize_hcdb8a1dc_0_161, width: 1)
                                                                              ) &
                                                                              sig(:zflag, width: 1)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_164,
    (
        sig(:cond_33, width: 1) &
        sig(:cond_32, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_38,
    (
        sig(:wr_regrm_word, width: 1) &
        sig(:cond_5, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_39,
    (
      ~sig(:cond_5, width: 1)
    )
  assign :wr_regrm_word,
    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[16]
  assign :__VdfgRegularize_hcdb8a1dc_0_40,
    (
        sig(:cond_102, width: 1) &
        sig(:cond_104, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_163,
    (
        sig(:cond_33, width: 1) &
        sig(:cond_107, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_41,
    (
        sig(:cond_129, width: 1) &
        sig(:cond_5, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_162,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_39, width: 1) &
        sig(:cond_129, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_42,
    (
        sig(:cond_136, width: 1) &
        sig(:cond_104, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_43,
    (
        sig(:cond_171, width: 1) &
        sig(:wr_dst_is_reg, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_28,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[81] |
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[82]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_161,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_39, width: 1) &
        sig(:cond_274, width: 1)
    )
  assign :fs_rpl_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:task_fs, width: 16)[1..0],
        sig(:fs_rpl, width: 2)
      )
    )
  assign :esp_to_reg,
    mux(
      (
          sig(:cond_10, width: 1) &
          sig(:cond_8, width: 1)
      ),
      sig(:wr_stack_esp, width: 32),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_160, width: 1),
        sig(:wr_stack_esp, width: 32),
        mux(
          (
              sig(:cond_15, width: 1) &
              sig(:cond_14, width: 1)
          ),
          sig(:wr_new_stack_esp, width: 32),
          mux(
            (
                sig(:cond_19, width: 1) &
                (
                    sig(:cond_15, width: 1) &
                    sig(:cond_20, width: 1)
                )
            ),
            sig(:wr_new_stack_esp, width: 32),
            mux(
              (
                  sig(:cond_21, width: 1) &
                  sig(:cond_22, width: 1)
              ),
              sig(:wr_stack_esp, width: 32),
              mux(
                sig(:cond_38, width: 1),
                sig(:wr_stack_esp, width: 32),
                mux(
                  (
                      sig(:cond_55, width: 1) &
                      (
                          sig(:cond_15, width: 1) &
                          (
                              (
                                  (
                                    ~sig(:exc_push_error, width: 1)
                                  ) &
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
                              ) |
                              sig(:cond_20, width: 1)
                          )
                      )
                  ),
                  sig(:wr_new_stack_esp, width: 32),
                  mux(
                    (
                        sig(:cond_10, width: 1) &
                        sig(:cond_65, width: 1)
                    ),
                    sig(:wr_stack_esp, width: 32),
                    mux(
                      sig(:cond_75, width: 1),
                      sig(:wr_stack_esp, width: 32),
                      mux(
                        sig(:cond_80, width: 1),
                        sig(:wr_stack_esp, width: 32),
                        mux(
                          sig(:cond_87, width: 1),
                          sig(:exe_buffer_shifted, width: 464)[159..128],
                          mux(
                            sig(:cond_96, width: 1),
                            sig(:wr_stack_esp, width: 32),
                            mux(
                              sig(:cond_97, width: 1),
                              sig(:wr_stack_esp, width: 32),
                              mux(
                                (
                                    sig(:cond_10, width: 1) &
                                    sig(:cond_124, width: 1)
                                ),
                                sig(:wr_stack_esp, width: 32),
                                mux(
                                  sig(:cond_130, width: 1),
                                  sig(:wr_stack_esp, width: 32),
                                  mux(
                                    sig(:cond_131, width: 1),
                                    sig(:wr_stack_esp, width: 32),
                                    mux(
                                      (
                                          sig(:cond_10, width: 1) &
                                          sig(:cond_132, width: 1)
                                      ),
                                      sig(:wr_stack_esp, width: 32),
                                      mux(
                                        sig(:cond_135, width: 1),
                                        sig(:wr_stack_esp, width: 32),
                                        mux(
                                          sig(:cond_147, width: 1),
                                          sig(:wr_stack_esp, width: 32),
                                          mux(
                                            sig(:cond_149, width: 1),
                                            sig(:wr_stack_esp, width: 32),
                                            mux(
                                              (
                                                  sig(:cond_158, width: 1) &
                                                  sig(:cond_22, width: 1)
                                              ),
                                              sig(:wr_stack_esp, width: 32),
                                              mux(
                                                (
                                                    sig(:cond_176, width: 1) &
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_158, width: 1)
                                                ),
                                                sig(:wr_stack_esp, width: 32),
                                                mux(
                                                  (
                                                      sig(:cond_176, width: 1) &
                                                      sig(:__VdfgRegularize_hcdb8a1dc_0_157, width: 1)
                                                  ),
                                                  sig(:wr_stack_esp, width: 32),
                                                  mux(
                                                    sig(:wr_validate_seg_regs, width: 1),
                                                    sig(:wr_stack_esp, width: 32),
                                                    mux(
                                                      (
                                                          sig(:cond_10, width: 1) &
                                                          sig(:cond_189, width: 1)
                                                      ),
                                                      sig(:wr_stack_esp, width: 32),
                                                      mux(
                                                        (
                                                            sig(:cond_202, width: 1) &
                                                            sig(:cond_22, width: 1)
                                                        ),
                                                        sig(:wr_stack_esp, width: 32),
                                                        mux(
                                                          sig(:cond_216, width: 1),
                                                          sig(:wr_stack_esp, width: 32),
                                                          mux(
                                                            sig(:wr_glob_param_3_set, width: 1),
                                                            mux(
                                                              sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
                                                              lit(65535, width: 16, base: "h", signed: false).concat(
                                                                sig(:exe_buffer_shifted, width: 464)[223..208]
                                                              ),
                                                              sig(:exe_buffer_shifted, width: 464)[239..208]
                                                            ),
                                                            mux(
                                                              (
                                                                  sig(:cond_10, width: 1) &
                                                                  sig(:__VdfgRegularize_hcdb8a1dc_0_44, width: 1)
                                                              ),
                                                              sig(:wr_stack_esp, width: 32),
                                                              mux(
                                                                sig(:cond_263, width: 1),
                                                                sig(:wr_stack_esp, width: 32),
                                                                sig(:esp, width: 32)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_160,
    (
        sig(:cond_10, width: 1) &
        sig(:cond_11, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_158,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_159, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_157,
    (
        sig(:glob_descriptor, width: 64)[40] &
        sig(:cond_174, width: 1)
    )
  assign :wr_validate_seg_regs,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
            sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
            sig(:cond_123, width: 1)
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_44,
    (
        sig(:cond_253, width: 1) &
        sig(:cond_254, width: 1)
    )
  assign :ebp_to_reg,
    mux(
      sig(:cond_131, width: 1),
      mux(
        sig(:wr_operand_16bit, width: 1),
        sig(:ebp, width: 32)[31..16],
        sig(:exe_buffer, width: 32)[31..16]
      ).concat(
        sig(:task_trap, width: 16)
      ),
      mux(
        sig(:cond_135, width: 1),
        mux(
          sig(:wr_operand_16bit, width: 1),
          sig(:ebp, width: 32)[31..16],
          sig(:result_push, width: 32)[31..16]
        ).concat(
          sig(:result_push, width: 32)[15..0]
        ),
        mux(
          sig(:wr_glob_param_3_set, width: 1),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
            lit(65535, width: 16, base: "h", signed: false).concat(
              sig(:exe_buffer_shifted, width: 464)[191..176]
            ),
            sig(:exe_buffer_shifted, width: 464)[207..176]
          ),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1),
            mux(
              sig(:wr_operand_16bit, width: 1),
              sig(:ebp, width: 32)[31..16],
              sig(:exe_buffer_shifted, width: 464)[159..144]
            ).concat(
              sig(:exe_buffer_shifted, width: 464)[143..128]
            ),
            sig(:ebp, width: 32)
          )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_45,
    (
        sig(:cond_263, width: 1) &
        sig(:cond_264, width: 1)
    )
  assign :tr_rpl_to_reg,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      sig(:glob_param_1, width: 32)[1..0],
      sig(:tr_rpl, width: 2)
    )
  assign :fs_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_34, width: 1),
      lit(0, width: 16, base: "h", signed: false),
      mux(
        sig(:cond_87, width: 1),
        sig(:wr_IRET_to_v86_fs, width: 16),
        mux(
          sig(:wr_glob_param_3_set, width: 1),
          sig(:task_fs, width: 16),
          sig(:fs, width: 16)
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_34,
    (
        sig(:cond_63, width: 1) &
        sig(:v8086_mode, width: 1)
    )
  assign :gs_cache_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3888, width: 28, base: "h", signed: false).concat(
        sig(:task_trap, width: 16).concat(
          lit(65535, width: 20, base: "h", signed: false)
        )
      ),
      sig(:gs_cache, width: 64)
    )
  assign :oflag_to_reg,
    mux(
      sig(:cond_0, width: 1),
      sig(:oflag_arith, width: 1),
      mux(
        sig(:cond_24, width: 1),
        sig(:oflag_arith, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1),
          sig(:oflag_arith, width: 1),
          mux(
            sig(:cond_37, width: 1),
            sig(:oflag_arith, width: 1),
            mux(
              sig(:cond_66, width: 1),
              sig(:oflag_arith, width: 1),
              mux(
                sig(:cond_82, width: 1),
                sig(:glob_param_3, width: 32)[11],
                mux(
                  sig(:cond_87, width: 1),
                  sig(:glob_param_3, width: 32)[11],
                  mux(
                    sig(:cond_89, width: 1),
                    sig(:glob_param_3, width: 32)[11],
                    mux(
                      sig(:cond_93, width: 1),
                      sig(:glob_param_5, width: 32)[11],
                      mux(
                        sig(:__VdfgRegularize_hcdb8a1dc_0_46, width: 1),
                        sig(:result_signals, width: 5)[1],
                        mux(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
                          sig(:oflag_arith, width: 1),
                          (
                              sig(:__VdfgRegularize_hcdb8a1dc_0_47, width: 1) &
                              mux(
                                sig(:__VdfgRegularize_hcdb8a1dc_0_162, width: 1),
                                sig(:oflag_arith, width: 1),
                                mux(
                                  sig(:cond_133, width: 1),
                                  sig(:wr_mult_overflow, width: 1),
                                  mux(
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_48, width: 1),
                                    sig(:result_signals, width: 5)[1],
                                    mux(
                                      sig(:cond_139, width: 1),
                                      sig(:oflag_arith, width: 1),
                                      mux(
                                        sig(:cond_142, width: 1),
                                        sig(:wr_mult_overflow, width: 1),
                                        mux(
                                          sig(:cond_145, width: 1),
                                          sig(:oflag_arith, width: 1),
                                          mux(
                                            sig(:cond_216, width: 1),
                                            sig(:result2, width: 32)[11],
                                            mux(
                                              sig(:wr_glob_param_3_set, width: 1),
                                              sig(:task_eflags, width: 32)[11],
                                              mux(
                                                sig(:cond_272, width: 1),
                                                sig(:oflag_arith, width: 1),
                                                mux(
                                                  sig(:cond_273, width: 1),
                                                  sig(:oflag_arith, width: 1),
                                                  mux(
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_161, width: 1),
                                                    sig(:oflag_arith, width: 1),
                                                    sig(:oflag, width: 1)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_46,
    (
        sig(:cond_102, width: 1) &
        sig(:cond_105, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_47,
    (
      ~sig(:__VdfgRegularize_hcdb8a1dc_0_41, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_48,
    (
        sig(:cond_136, width: 1) &
        sig(:cond_105, width: 1)
    )
  assign :ss_to_reg,
    mux(
      sig(:cond_87, width: 1),
      sig(:task_es, width: 16),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:task_ss, width: 16),
        sig(:ss, width: 16)
      )
    )
  assign :ebx_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_49, width: 1),
      lit(1970169159, width: 32, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_50, width: 1),
        lit(0, width: 32, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_51, width: 1),
          lit(0, width: 32, base: "h", signed: false),
          mux(
            sig(:wr_glob_param_3_set, width: 1),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
              lit(65535, width: 16, base: "h", signed: false).concat(
                sig(:exe_buffer_shifted, width: 464)[255..240]
              ),
              sig(:exe_buffer_shifted, width: 464)[271..240]
            ),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1),
              mux(
                sig(:wr_operand_16bit, width: 1),
                sig(:ebx, width: 32)[31..16],
                sig(:task_cs, width: 16)
              ).concat(
                sig(:task_ss, width: 16)
              ),
              sig(:ebx, width: 32)
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_49,
    (
        sig(:cond_164, width: 1) &
        (
            lit(0, width: 32, base: "h", signed: false) ==
            sig(:eax, width: 32)
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_50,
    (
        sig(:cond_164, width: 1) &
        (
            lit(1, width: 32, base: "h", signed: false) ==
            sig(:eax, width: 32)
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_51,
    (
        sig(:cond_164, width: 1) &
        (
            lit(1, width: 32, base: "h", signed: false) <
            sig(:eax, width: 32)
        )
    )
  assign :dflag_to_reg,
    (
        (
          ~sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[23]
        ) &
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[26] |
            mux(
              sig(:cond_82, width: 1),
              sig(:glob_param_3, width: 32)[10],
              mux(
                sig(:cond_87, width: 1),
                sig(:glob_param_3, width: 32)[10],
                mux(
                  sig(:cond_89, width: 1),
                  sig(:glob_param_3, width: 32)[10],
                  mux(
                    sig(:cond_93, width: 1),
                    sig(:glob_param_5, width: 32)[10],
                    mux(
                      sig(:cond_216, width: 1),
                      sig(:result2, width: 32)[10],
                      mux(
                        sig(:wr_glob_param_3_set, width: 1),
                        sig(:task_eflags, width: 32)[10],
                        sig(:dflag, width: 1)
                      )
                    )
                  )
                )
              )
            )
        )
    )
  assign :dr3_to_reg,
    mux(
      (
          sig(:cond_266, width: 1) &
          sig(:cond_118, width: 1)
      ),
      sig(:result2, width: 32),
      sig(:dr3, width: 32)
    )
  assign :dr2_to_reg,
    mux(
      (
          sig(:cond_266, width: 1) &
          sig(:cond_117, width: 1)
      ),
      sig(:result2, width: 32),
      sig(:dr2, width: 32)
    )
  assign :acflag_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_52, width: 1) &
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_53, width: 1),
          sig(:glob_param_3, width: 32)[18],
          mux(
            sig(:cond_87, width: 1),
            sig(:glob_param_3, width: 32)[18],
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_54, width: 1),
              sig(:glob_param_3, width: 32)[18],
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_55, width: 1),
                sig(:glob_param_5, width: 32)[18],
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_56, width: 1),
                  sig(:result2, width: 32)[18],
                  mux(
                    sig(:wr_glob_param_3_set, width: 1),
                    sig(:task_eflags, width: 32)[18],
                    sig(:acflag, width: 1)
                  )
                )
              )
            )
          )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_52,
    (
      ~sig(:cond_60, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_53,
    (
        sig(:cond_82, width: 1) &
        sig(:wr_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_54,
    (
        sig(:cond_89, width: 1) &
        sig(:wr_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_55,
    (
        sig(:cond_93, width: 1) &
        sig(:wr_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_56,
    (
        sig(:cond_216, width: 1) &
        sig(:wr_operand_32bit, width: 1)
    )
  assign :cr0_mp_to_reg,
    mux(
      sig(:cond_110, width: 1),
      sig(:result2, width: 32)[1],
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
        sig(:result2, width: 32)[1],
        sig(:cr0_mp, width: 1)
      )
    )
  assign :cr0_wp_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
      sig(:result2, width: 32)[16],
      sig(:cr0_wp, width: 1)
    )
  assign :cr2_to_reg,
    mux(
      (
          sig(:cond_113, width: 1) &
          sig(:cond_117, width: 1)
      ),
      sig(:result2, width: 32),
      sig(:cr2, width: 32)
    )
  assign :cr3_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_57, width: 1),
      sig(:result2, width: 32),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_58, width: 1),
        sig(:__VdfgRegularize_hcdb8a1dc_0_30, width: 32),
        sig(:cr3, width: 32)
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_57,
    (
        sig(:cond_113, width: 1) &
        sig(:cond_118, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_58,
    (
        sig(:wr_glob_param_3_set, width: 1) &
        (
            (
                lit(9, width: 4, base: "h", signed: false) <=
                sig(:glob_descriptor, width: 64)[43..40]
            ) &
            (
                sig(:cr0_pg, width: 1) &
                (
                    sig(:cr3, width: 32) !=
                    sig(:__VdfgRegularize_hcdb8a1dc_0_30, width: 32)
                )
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_30,
    sig(:exe_buffer_shifted, width: 464)[463..432]
  assign :dr1_to_reg,
    mux(
      (
          sig(:cond_266, width: 1) &
          (
              lit(1, width: 3, base: "h", signed: false) ==
              sig(:wr_decoder, width: 16)[13..11]
          )
      ),
      sig(:result2, width: 32),
      sig(:dr1, width: 32)
    )
  assign :dr0_to_reg,
    mux(
      (
          sig(:cond_266, width: 1) &
          sig(:cond_114, width: 1)
      ),
      sig(:result2, width: 32),
      sig(:dr0, width: 32)
    )
  assign :ds_rpl_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:exe_buffer_shifted, width: 464)[49..48],
        sig(:ds_rpl, width: 2)
      )
    )
  assign :dr7_to_reg,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      (
          lit(4294966954, width: 32, base: "h", signed: false) &
          sig(:dr7, width: 32)
      ),
      mux(
        (
            sig(:cond_266, width: 1) &
            (
                (
                    lit(5, width: 3, base: "h", signed: false) ==
                    sig(:wr_decoder, width: 16)[13..11]
                ) |
                (
                    lit(7, width: 3, base: "h", signed: false) ==
                    sig(:wr_decoder, width: 16)[13..11]
                )
            )
        ),
        (
            lit(1024, width: 32, base: "h", signed: false) |
            sig(:result2, width: 32)
        ),
        sig(:dr7, width: 32)
      )
    )
  assign :ds_cache_valid_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_35, width: 1) &
        (
            sig(:cond_87, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_36, width: 1) &
                sig(:ds_cache_valid, width: 1)
            )
        )
    )
  assign :cs_to_reg,
    mux(
      sig(:cond_87, width: 1),
      sig(:wr_IRET_to_v86_cs, width: 16),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:task_cs, width: 16),
        sig(:cs, width: 16)
      )
    )
  assign :cr0_am_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
      sig(:result2, width: 32)[18],
      sig(:cr0_am, width: 1)
    )
  assign :cs_cache_valid_to_reg,
    (
        sig(:cond_87, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_36, width: 1) &
            sig(:cs_cache_valid, width: 1)
        )
    )
  assign :idtr_limit_to_reg,
    mux(
      (
          sig(:__VdfgRegularize_hcdb8a1dc_0_59, width: 1) &
          sig(:cond_120, width: 1)
      ),
      sig(:result2, width: 32)[15..0],
      sig(:idtr_limit, width: 16)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_59,
    (
        sig(:cond_119, width: 1) &
        sig(:cond_122, width: 1)
    )
  assign :gdtr_base_to_reg,
    mux(
      (
          sig(:__VdfgRegularize_hcdb8a1dc_0_60, width: 1) &
          sig(:__VdfgRegularize_hcdb8a1dc_0_32, width: 1)
      ),
      sig(:__VdfgRegularize_hcdb8a1dc_0_61, width: 32),
      sig(:gdtr_base, width: 32)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_60,
    (
      ~sig(:cond_120, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_61,
    mux(
      sig(:wr_operand_32bit, width: 1),
      sig(:result2, width: 32),
      lit(0, width: 8, base: "d", signed: false).concat(
        sig(:result2, width: 32)[23..0]
      )
    )
  assign :cr0_ne_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
      sig(:result2, width: 32)[5],
      sig(:cr0_ne, width: 1)
    )
  assign :cr0_em_to_reg,
    mux(
      sig(:cond_110, width: 1),
      sig(:result2, width: 32)[2],
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
        sig(:result2, width: 32)[2],
        sig(:cr0_em, width: 1)
      )
    )
  assign :fs_cache_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3888, width: 28, base: "h", signed: false).concat(
        sig(:wr_IRET_to_v86_fs, width: 16).concat(
          lit(65535, width: 20, base: "h", signed: false)
        )
      ),
      sig(:fs_cache, width: 64)
    )
  assign :dr6_bd_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_37, width: 1),
      sig(:result2, width: 32)[13],
      sig(:dr6_bd, width: 1)
    )
  assign :idtr_base_to_reg,
    mux(
      (
          sig(:__VdfgRegularize_hcdb8a1dc_0_60, width: 1) &
          sig(:__VdfgRegularize_hcdb8a1dc_0_59, width: 1)
      ),
      sig(:__VdfgRegularize_hcdb8a1dc_0_61, width: 32),
      sig(:idtr_base, width: 32)
    )
  assign :gs_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_34, width: 1),
      lit(0, width: 16, base: "h", signed: false),
      mux(
        sig(:cond_87, width: 1),
        sig(:task_trap, width: 16),
        mux(
          sig(:wr_glob_param_3_set, width: 1),
          sig(:task_gs, width: 16),
          sig(:gs, width: 16)
        )
      )
    )
  assign :ldtr_cache_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_62, width: 1),
      sig(:glob_descriptor, width: 64),
      sig(:ldtr_cache, width: 64)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_62,
    (
        sig(:cond_242, width: 1) &
        (
            lit(0, width: 3, base: "h", signed: false) ==
            sig(:glob_param_2, width: 32)[2..0]
        )
    )
  assign :eax_to_reg,
    mux(
      sig(:cond_66, width: 1),
      sig(:__VdfgRegularize_hcdb8a1dc_0_63, width: 32),
      mux(
        sig(:cond_100, width: 1),
        sig(:__VdfgRegularize_hcdb8a1dc_0_64, width: 32),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_162, width: 1),
          sig(:__VdfgRegularize_hcdb8a1dc_0_66, width: 32),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_67, width: 1),
            sig(:__VdfgRegularize_hcdb8a1dc_0_64, width: 32),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_68, width: 1),
              sig(:__VdfgRegularize_hcdb8a1dc_0_64, width: 32),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_156, width: 1),
                sig(:__VdfgRegularize_hcdb8a1dc_0_66, width: 32),
                mux(
                  sig(:cond_155, width: 1),
                  sig(:__VdfgRegularize_hcdb8a1dc_0_65, width: 32),
                  mux(
                    sig(:__VdfgRegularize_hcdb8a1dc_0_49, width: 1),
                    lit(1, width: 32, base: "h", signed: false),
                    mux(
                      sig(:__VdfgRegularize_hcdb8a1dc_0_50, width: 1),
                      lit(1115, width: 32, base: "h", signed: false),
                      mux(
                        sig(:__VdfgRegularize_hcdb8a1dc_0_51, width: 1),
                        lit(0, width: 32, base: "h", signed: false),
                        mux(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_69, width: 1),
                          sig(:__VdfgRegularize_hcdb8a1dc_0_66, width: 32),
                          mux(
                            (
                                lit(91, width: 7, base: "h", signed: false) ==
                                sig(:wr_cmd, width: 7)
                            ),
                            sig(:eax, width: 32)[31..16].concat(
                              sig(:sflag, width: 1).concat(
                                sig(:zflag, width: 1).concat(
                                  lit(0, width: 1, base: "d", signed: false).concat(
                                    sig(:aflag, width: 1).concat(
                                      lit(0, width: 1, base: "d", signed: false).concat(
                                        sig(:pflag, width: 1).concat(
                                          lit(1, width: 1, base: "h", signed: false).concat(
                                            sig(:cflag, width: 1).concat(
                                              sig(:eax, width: 32)[7..0]
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            ),
                            mux(
                              (
                                  sig(:cond_214, width: 1) &
                                  sig(:wr_operand_32bit, width: 1)
                              ),
                              sig(:__VdfgRegularize_hcdb8a1dc_0_70, width: 16).concat(
                                sig(:eax, width: 32)[15..0]
                              ),
                              mux(
                                (
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_71, width: 1) &
                                    sig(:cond_214, width: 1)
                                ),
                                sig(:eax, width: 32)[31..16].concat(
                                  sig(:eax, width: 32)[7].replicate(
                                    lit(8, width: 32, base: "h", signed: true)
                                  ).concat(
                                    sig(:eax, width: 32)[7..0]
                                  )
                                ),
                                mux(
                                  (
                                      sig(:cond_223, width: 1) &
                                      sig(:cflag, width: 1)
                                  ),
                                  sig(:eax, width: 32)[31..8].concat(
                                    lit(255, width: 8, base: "h", signed: false)
                                  ),
                                  mux(
                                    (
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_72, width: 1) &
                                        sig(:cond_223, width: 1)
                                    ),
                                    sig(:eax, width: 32)[31..8].concat(
                                      lit(0, width: 8, base: "h", signed: false)
                                    ),
                                    mux(
                                      sig(:wr_glob_param_3_set, width: 1),
                                      mux(
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
                                        lit(65535, width: 16, base: "h", signed: false).concat(
                                          sig(:exe_buffer_shifted, width: 464)[351..336]
                                        ),
                                        sig(:exe_buffer_shifted, width: 464)[367..336]
                                      ),
                                      mux(
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1),
                                        mux(
                                          sig(:wr_operand_16bit, width: 1),
                                          sig(:eax, width: 32)[31..16],
                                          sig(:exe_buffer, width: 32)[31..16]
                                        ).concat(
                                          sig(:task_trap, width: 16)
                                        ),
                                        mux(
                                          sig(:cond_272, width: 1),
                                          sig(:__VdfgRegularize_hcdb8a1dc_0_63, width: 32),
                                          mux(
                                            sig(:cond_273, width: 1),
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_63, width: 32),
                                            sig(:eax, width: 32)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_63,
    sig(:eax, width: 32)[31..16].concat(
      sig(:result, width: 32)[15..0]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_64,
    mux(
      (
          sig(:wr_is_8bit, width: 1) |
          sig(:wr_operand_16bit, width: 1)
      ),
      sig(:__VdfgRegularize_hcdb8a1dc_0_63, width: 32),
      sig(:result, width: 32)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_66,
    mux(
      sig(:wr_is_8bit, width: 1),
      sig(:eax, width: 32)[31..8].concat(
        sig(:result2, width: 32)[7..0]
      ),
      sig(:__VdfgRegularize_hcdb8a1dc_0_65, width: 32)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_67,
    (
        sig(:cond_133, width: 1) &
        sig(:wr_dst_is_edx_eax, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_68,
    (
        sig(:cond_142, width: 1) &
        sig(:wr_dst_is_edx_eax, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_156,
    (
        sig(:cond_33, width: 1) &
        sig(:cond_152, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_65,
    mux(
      sig(:wr_operand_16bit, width: 1),
      sig(:eax, width: 32)[31..16].concat(
        sig(:result2, width: 32)[15..0]
      ),
      sig(:result2, width: 32)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_69,
    (
        sig(:cond_167, width: 1) &
        sig(:cond_168, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_70,
    sig(:eax, width: 32)[15].replicate(
      lit(16, width: 32, base: "h", signed: true)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_71,
    (
      ~sig(:wr_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_72,
    (
      ~sig(:cflag, width: 1)
    )
  assign :dr6_bs_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_37, width: 1),
      sig(:result2, width: 32)[14],
      sig(:dr6_bs, width: 1)
    )
  assign :edi_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1),
      sig(:wr_edi_final, width: 32),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
        sig(:wr_edi_final, width: 32),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_154, width: 1),
          sig(:wr_edi_final, width: 32),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_151, width: 1),
            sig(:wr_edi_final, width: 32),
            mux(
              sig(:wr_glob_param_3_set, width: 1),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
                lit(65535, width: 16, base: "h", signed: false).concat(
                  sig(:exe_buffer_shifted, width: 464)[127..112]
                ),
                sig(:exe_buffer_shifted, width: 464)[143..112]
              ),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_149, width: 1),
                sig(:wr_edi_final, width: 32),
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1),
                  mux(
                    sig(:wr_operand_16bit, width: 1),
                    sig(:edi, width: 32)[31..16],
                    sig(:exe_buffer_shifted, width: 464)[223..208]
                  ).concat(
                    sig(:exe_buffer_shifted, width: 464)[207..192]
                  ),
                  sig(:edi, width: 32)
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_154,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_155, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_151,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_152, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_149,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_150, width: 1)
    )
  assign :dr6_bt_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_37, width: 1),
      sig(:result2, width: 32)[15],
      sig(:dr6_bt, width: 1)
    )
  assign :wr_task_rpl_to_reg,
    mux(
      sig(:cond_179, width: 1),
      sig(:cpl, width: 2),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:exe_buffer_shifted, width: 464)[81..80],
        sig(:wr_task_rpl, width: 2)
      )
    )
  assign :iopl_to_reg,
    mux(
      (
          sig(:cond_82, width: 1) &
          sig(:real_mode, width: 1)
      ),
      sig(:glob_param_3, width: 32)[13..12],
      mux(
        sig(:cond_87, width: 1),
        sig(:glob_param_3, width: 32)[13..12],
        mux(
          (
              sig(:cond_89, width: 1) &
              sig(:cond_91, width: 1)
          ),
          sig(:glob_param_3, width: 32)[13..12],
          mux(
            (
                sig(:cond_93, width: 1) &
                (
                    lit(0, width: 2, base: "h", signed: false) ==
                    sig(:wr_task_rpl, width: 2)
                )
            ),
            sig(:glob_param_5, width: 32)[13..12],
            mux(
              (
                  sig(:cond_216, width: 1) &
                  (
                      (
                          sig(:protected_mode, width: 1) &
                          sig(:cond_91, width: 1)
                      ) |
                      sig(:real_mode, width: 1)
                  )
              ),
              sig(:result2, width: 32)[13..12],
              mux(
                sig(:wr_glob_param_3_set, width: 1),
                sig(:task_eflags, width: 32)[13..12],
                sig(:iopl, width: 2)
              )
            )
          )
        )
      )
    )
  assign :ldtr_rpl_to_reg,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      sig(:task_ldtr, width: 16)[1..0],
      sig(:ldtr_rpl, width: 2)
    )
  assign :es_rpl_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:exe_buffer_shifted, width: 464)[97..96],
        sig(:es_rpl, width: 2)
      )
    )
  assign :ldtr_cache_valid_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_36, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_62, width: 1) |
            sig(:ldtr_cache_valid, width: 1)
        )
    )
  assign :es_cache_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3888, width: 28, base: "h", signed: false).concat(
        sig(:task_ss, width: 16).concat(
          lit(65535, width: 20, base: "h", signed: false)
        )
      ),
      sig(:es_cache, width: 64)
    )
  assign :iflag_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_52, width: 1) &
        mux(
          sig(:cond_62, width: 1),
          (
              sig(:glob_param_1, width: 32)[20] &
              sig(:iflag, width: 1)
          ),
          mux(
            sig(:cond_63, width: 1),
            (
                sig(:glob_param_3, width: 32)[20] &
                sig(:iflag, width: 1)
            ),
            mux(
              sig(:cond_82, width: 1),
              sig(:glob_param_3, width: 32)[9],
              mux(
                sig(:cond_87, width: 1),
                sig(:glob_param_3, width: 32)[9],
                mux(
                  (
                      sig(:cond_89, width: 1) &
                      sig(:cond_90, width: 1)
                  ),
                  sig(:glob_param_3, width: 32)[9],
                  mux(
                    (
                        sig(:cond_93, width: 1) &
                        (
                            sig(:wr_task_rpl, width: 2) <=
                            sig(:iopl, width: 2)
                        )
                    ),
                    sig(:glob_param_5, width: 32)[9],
                    mux(
                      (
                          sig(:cond_216, width: 1) &
                          (
                              (
                                  sig(:protected_mode, width: 1) &
                                  sig(:cond_90, width: 1)
                              ) |
                              (
                                  sig(:real_mode, width: 1) |
                                  sig(:v8086_mode, width: 1)
                              )
                          )
                      ),
                      sig(:result2, width: 32)[9],
                      (
                          (
                            ~sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[95]
                          ) &
                          (
                              sig(:cond_220, width: 1) |
                              mux(
                                sig(:wr_glob_param_3_set, width: 1),
                                sig(:task_eflags, width: 32)[9],
                                sig(:iflag, width: 1)
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
  assign :sflag_to_reg,
    mux(
      sig(:cond_0, width: 1),
      sig(:sflag_result, width: 1),
      mux(
        sig(:cond_24, width: 1),
        sig(:sflag_result, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1),
          sig(:sflag_result, width: 1),
          mux(
            sig(:cond_37, width: 1),
            sig(:sflag_result, width: 1),
            mux(
              sig(:cond_51, width: 1),
              sig(:eax, width: 32)[15],
              mux(
                sig(:cond_66, width: 1),
                sig(:sflag_result, width: 1),
                mux(
                  sig(:cond_82, width: 1),
                  sig(:glob_param_3, width: 32)[7],
                  mux(
                    sig(:cond_87, width: 1),
                    sig(:glob_param_3, width: 32)[7],
                    mux(
                      sig(:cond_89, width: 1),
                      sig(:glob_param_3, width: 32)[7],
                      mux(
                        sig(:cond_93, width: 1),
                        sig(:glob_param_5, width: 32)[7],
                        mux(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_40, width: 1),
                          sig(:sflag_result, width: 1),
                          mux(
                            sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
                            sig(:sflag_result, width: 1),
                            (
                                sig(:__VdfgRegularize_hcdb8a1dc_0_47, width: 1) &
                                mux(
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_162, width: 1),
                                  sig(:sflag_result, width: 1),
                                  mux(
                                    sig(:cond_133, width: 1),
                                    sig(:sflag_result, width: 1),
                                    mux(
                                      sig(:__VdfgRegularize_hcdb8a1dc_0_42, width: 1),
                                      sig(:sflag_result, width: 1),
                                      mux(
                                        sig(:cond_139, width: 1),
                                        sig(:sflag_result, width: 1),
                                        mux(
                                          sig(:cond_142, width: 1),
                                          sig(:sflag_result, width: 1),
                                          mux(
                                            sig(:cond_145, width: 1),
                                            sig(:sflag_result, width: 1),
                                            mux(
                                              sig(:cond_216, width: 1),
                                              sig(:result2, width: 32)[7],
                                              mux(
                                                sig(:wr_glob_param_3_set, width: 1),
                                                sig(:task_eflags, width: 32)[7],
                                                mux(
                                                  sig(:cond_272, width: 1),
                                                  sig(:sflag_result, width: 1),
                                                  mux(
                                                    sig(:cond_273, width: 1),
                                                    sig(:sflag_result, width: 1),
                                                    mux(
                                                      sig(:__VdfgRegularize_hcdb8a1dc_0_161, width: 1),
                                                      sig(:sflag_result, width: 1),
                                                      sig(:sflag, width: 1)
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
  assign :edx_to_reg,
    mux(
      (
          sig(:cond_101, width: 1) &
          sig(:cond_100, width: 1)
      ),
      sig(:__VdfgRegularize_hcdb8a1dc_0_73, width: 32),
      mux(
        (
            sig(:cond_101, width: 1) &
            sig(:__VdfgRegularize_hcdb8a1dc_0_67, width: 1)
        ),
        sig(:__VdfgRegularize_hcdb8a1dc_0_73, width: 32),
        mux(
          (
              sig(:cond_101, width: 1) &
              sig(:__VdfgRegularize_hcdb8a1dc_0_68, width: 1)
          ),
          sig(:__VdfgRegularize_hcdb8a1dc_0_73, width: 32),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_49, width: 1),
            lit(1231384169, width: 32, base: "h", signed: false),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_50, width: 1),
              lit(0, width: 32, base: "h", signed: false),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_51, width: 1),
                lit(0, width: 32, base: "h", signed: false),
                mux(
                  (
                      sig(:cond_215, width: 1) &
                      sig(:wr_operand_32bit, width: 1)
                  ),
                  sig(:eax, width: 32)[31].replicate(
                    lit(32, width: 32, base: "h", signed: true)
                  ),
                  mux(
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_71, width: 1) &
                        sig(:cond_215, width: 1)
                    ),
                    sig(:edx, width: 32)[31..16].concat(
                      sig(:__VdfgRegularize_hcdb8a1dc_0_70, width: 16)
                    ),
                    mux(
                      sig(:wr_glob_param_3_set, width: 1),
                      mux(
                        sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
                        lit(65535, width: 16, base: "h", signed: false).concat(
                          sig(:exe_buffer_shifted, width: 464)[287..272]
                        ),
                        sig(:exe_buffer_shifted, width: 464)[303..272]
                      ),
                      mux(
                        sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1),
                        mux(
                          sig(:wr_operand_16bit, width: 1),
                          sig(:edx, width: 32)[31..16],
                          sig(:task_ds, width: 16)
                        ).concat(
                          sig(:wr_IRET_to_v86_ds, width: 16)
                        ),
                        sig(:edx, width: 32)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_73,
    mux(
      sig(:wr_operand_16bit, width: 1),
      sig(:edx, width: 32)[31..16].concat(
        sig(:result, width: 32)[31..16]
      ),
      sig(:result2, width: 32)
    )
  assign :vmflag_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_74, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_75, width: 1) &
            mux(
              sig(:cond_87, width: 1),
              sig(:glob_param_3, width: 32)[17],
              mux(
                sig(:wr_glob_param_3_set, width: 1),
                sig(:task_eflags, width: 32)[17],
                sig(:vmflag, width: 1)
              )
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_74,
    (
      ~sig(:cond_62, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_75,
    (
      ~sig(:cond_63, width: 1)
    )
  assign :gs_rpl_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        sig(:task_gs, width: 16)[1..0],
        sig(:gs_rpl, width: 2)
      )
    )
  assign :ds_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_34, width: 1),
      lit(0, width: 16, base: "h", signed: false),
      mux(
        sig(:cond_87, width: 1),
        sig(:wr_IRET_to_v86_ds, width: 16),
        mux(
          sig(:wr_glob_param_3_set, width: 1),
          sig(:task_ds, width: 16),
          sig(:ds, width: 16)
        )
      )
    )
  assign :ds_cache_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3888, width: 28, base: "h", signed: false).concat(
        sig(:wr_IRET_to_v86_ds, width: 16).concat(
          lit(65535, width: 20, base: "h", signed: false)
        )
      ),
      sig(:ds_cache, width: 64)
    )
  assign :rflag_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_52, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_74, width: 1) &
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_75, width: 1) &
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_53, width: 1),
                  sig(:cond_254, width: 1),
                  mux(
                    sig(:cond_87, width: 1),
                    sig(:cond_254, width: 1),
                    mux(
                      sig(:__VdfgRegularize_hcdb8a1dc_0_54, width: 1),
                      sig(:cond_254, width: 1),
                      mux(
                        sig(:__VdfgRegularize_hcdb8a1dc_0_55, width: 1),
                        sig(:glob_param_5, width: 32)[16],
                        mux(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_56, width: 1),
                          sig(:result2, width: 32)[16],
                          mux(
                            sig(:wr_glob_param_3_set, width: 1),
                            sig(:task_eflags, width: 32)[16],
                            sig(:rflag, width: 1)
                          )
                        )
                      )
                    )
                  )
                )
            )
        )
    )
  assign :esi_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
      sig(:wr_esi_final, width: 32),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_156, width: 1),
        sig(:wr_esi_final, width: 32),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_146, width: 1),
          sig(:wr_esi_final, width: 32),
          mux(
            sig(:wr_glob_param_3_set, width: 1),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
              lit(65535, width: 16, base: "h", signed: false).concat(
                sig(:exe_buffer_shifted, width: 464)[159..144]
              ),
              sig(:exe_buffer_shifted, width: 464)[175..144]
            ),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_149, width: 1),
              sig(:wr_esi_final, width: 32),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1),
                mux(
                  sig(:wr_operand_16bit, width: 1),
                  sig(:esi, width: 32)[31..16],
                  sig(:exe_buffer_shifted, width: 464)[191..176]
                ).concat(
                  sig(:exe_buffer_shifted, width: 464)[175..160]
                ),
                sig(:esi, width: 32)
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_146,
    (
        sig(:write_io_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_147, width: 1)
    )
  assign :ss_cache_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3888, width: 28, base: "h", signed: false).concat(
        sig(:task_es, width: 16).concat(
          lit(65535, width: 20, base: "h", signed: false)
        )
      ),
      sig(:ss_cache, width: 64)
    )
  assign :gs_cache_valid_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_35, width: 1) &
        (
            sig(:cond_87, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_36, width: 1) &
                sig(:gs_cache_valid, width: 1)
            )
        )
    )
  assign :es_cache_valid_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_35, width: 1) &
        (
            sig(:cond_87, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_36, width: 1) &
                sig(:es_cache_valid, width: 1)
            )
        )
    )
  assign :ntflag_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_74, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_75, width: 1) &
            mux(
              sig(:cond_82, width: 1),
              sig(:glob_param_3, width: 32)[14],
              mux(
                sig(:cond_87, width: 1),
                sig(:glob_param_3, width: 32)[14],
                mux(
                  sig(:cond_89, width: 1),
                  sig(:glob_param_3, width: 32)[14],
                  mux(
                    sig(:cond_93, width: 1),
                    sig(:glob_param_5, width: 32)[14],
                    mux(
                      sig(:cond_216, width: 1),
                      sig(:result2, width: 32)[14],
                      mux(
                        sig(:wr_glob_param_3_set, width: 1),
                        (
                            sig(:task_eflags, width: 32)[14] |
                            sig(:cond_235, width: 1)
                        ),
                        sig(:ntflag, width: 1)
                      )
                    )
                  )
                )
              )
            )
        )
    )
  assign :cr0_pg_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
      sig(:result2, width: 32)[31],
      sig(:cr0_pg, width: 1)
    )
  assign :tflag_to_reg,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_52, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_74, width: 1) &
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_75, width: 1) &
                mux(
                  sig(:cond_82, width: 1),
                  sig(:glob_param_3, width: 32)[8],
                  mux(
                    sig(:cond_87, width: 1),
                    sig(:glob_param_3, width: 32)[8],
                    mux(
                      sig(:cond_89, width: 1),
                      sig(:glob_param_3, width: 32)[8],
                      mux(
                        sig(:cond_93, width: 1),
                        sig(:glob_param_5, width: 32)[8],
                        mux(
                          sig(:cond_216, width: 1),
                          sig(:result2, width: 32)[8],
                          mux(
                            sig(:wr_glob_param_3_set, width: 1),
                            sig(:task_eflags, width: 32)[8],
                            sig(:tflag, width: 1)
                          )
                        )
                      )
                    )
                  )
                )
            )
        )
    )
  assign :cr0_ts_to_reg,
    mux(
      sig(:cond_110, width: 1),
      sig(:result2, width: 32)[3],
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
        sig(:result2, width: 32)[3],
        (
            (
              ~sig(:cond_146, width: 1)
            ) &
            (
                sig(:wr_glob_param_3_set, width: 1) |
                sig(:cr0_ts, width: 1)
            )
        )
      )
    )
  assign :aflag_to_reg,
    mux(
      sig(:cond_0, width: 1),
      sig(:aflag_arith, width: 1),
      mux(
        sig(:cond_24, width: 1),
        sig(:aflag_arith, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1),
          sig(:aflag_arith, width: 1),
          mux(
            sig(:cond_37, width: 1),
            sig(:aflag_arith, width: 1),
            mux(
              sig(:cond_51, width: 1),
              sig(:eax, width: 32)[12],
              mux(
                sig(:cond_66, width: 1),
                sig(:aflag_arith, width: 1),
                mux(
                  sig(:cond_82, width: 1),
                  sig(:glob_param_3, width: 32)[4],
                  mux(
                    sig(:cond_87, width: 1),
                    sig(:glob_param_3, width: 32)[4],
                    mux(
                      sig(:cond_89, width: 1),
                      sig(:glob_param_3, width: 32)[4],
                      mux(
                        sig(:cond_93, width: 1),
                        sig(:glob_param_5, width: 32)[4],
                        mux(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_40, width: 1),
                          sig(:aflag_arith, width: 1),
                          mux(
                            sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
                            sig(:aflag_arith, width: 1),
                            (
                                sig(:__VdfgRegularize_hcdb8a1dc_0_47, width: 1) &
                                mux(
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_162, width: 1),
                                  sig(:aflag_arith, width: 1),
                                  (
                                      (
                                        ~sig(:cond_133, width: 1)
                                      ) &
                                      mux(
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_42, width: 1),
                                        sig(:aflag_arith, width: 1),
                                        mux(
                                          sig(:cond_139, width: 1),
                                          sig(:aflag_arith, width: 1),
                                          (
                                              (
                                                ~sig(:cond_142, width: 1)
                                              ) &
                                              mux(
                                                sig(:cond_145, width: 1),
                                                sig(:aflag_arith, width: 1),
                                                mux(
                                                  sig(:cond_216, width: 1),
                                                  sig(:result2, width: 32)[4],
                                                  mux(
                                                    sig(:wr_glob_param_3_set, width: 1),
                                                    sig(:task_eflags, width: 32)[4],
                                                    mux(
                                                      sig(:cond_272, width: 1),
                                                      sig(:result_signals, width: 5)[1],
                                                      mux(
                                                        sig(:cond_273, width: 1),
                                                        sig(:result_signals, width: 5)[1],
                                                        mux(
                                                          sig(:__VdfgRegularize_hcdb8a1dc_0_161, width: 1),
                                                          sig(:aflag_arith, width: 1),
                                                          sig(:aflag, width: 1)
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
  assign :ecx_to_reg,
    mux(
      (
          sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1) &
          sig(:cond_34, width: 1)
      ),
      sig(:wr_ecx_final, width: 32),
      mux(
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1) &
            sig(:cond_34, width: 1)
        ),
        sig(:wr_ecx_final, width: 32),
        mux(
          (
              sig(:cond_143, width: 1) &
              sig(:wr_address_16bit, width: 1)
          ),
          sig(:ecx, width: 32)[31..16].concat(
            sig(:wr_ecx_minus_1, width: 32)[15..0]
          ),
          mux(
            (
                (
                  ~sig(:wr_address_16bit, width: 1)
                ) &
                sig(:cond_143, width: 1)
            ),
            sig(:wr_ecx_minus_1, width: 32),
            mux(
              (
                  sig(:__VdfgRegularize_hcdb8a1dc_0_156, width: 1) &
                  sig(:cond_34, width: 1)
              ),
              sig(:wr_ecx_final, width: 32),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_49, width: 1),
                lit(1818588270, width: 32, base: "h", signed: false),
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_50, width: 1),
                  lit(0, width: 32, base: "h", signed: false),
                  mux(
                    sig(:__VdfgRegularize_hcdb8a1dc_0_51, width: 1),
                    lit(0, width: 32, base: "h", signed: false),
                    mux(
                      (
                          sig(:__VdfgRegularize_hcdb8a1dc_0_154, width: 1) &
                          sig(:cond_34, width: 1)
                      ),
                      sig(:wr_ecx_final, width: 32),
                      mux(
                        (
                            sig(:__VdfgRegularize_hcdb8a1dc_0_151, width: 1) &
                            sig(:cond_34, width: 1)
                        ),
                        sig(:wr_ecx_final, width: 32),
                        mux(
                          (
                              sig(:__VdfgRegularize_hcdb8a1dc_0_146, width: 1) &
                              sig(:cond_34, width: 1)
                          ),
                          sig(:wr_ecx_final, width: 32),
                          mux(
                            sig(:wr_glob_param_3_set, width: 1),
                            mux(
                              sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
                              lit(65535, width: 16, base: "h", signed: false).concat(
                                sig(:exe_buffer_shifted, width: 464)[319..304]
                              ),
                              sig(:exe_buffer_shifted, width: 464)[335..304]
                            ),
                            mux(
                              (
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_149, width: 1) &
                                  sig(:cond_34, width: 1)
                              ),
                              sig(:wr_ecx_final, width: 32),
                              mux(
                                sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1),
                                mux(
                                  sig(:wr_operand_16bit, width: 1),
                                  sig(:ecx, width: 32)[31..16],
                                  sig(:exe_buffer_shifted, width: 464)[31..16]
                                ).concat(
                                  sig(:wr_IRET_to_v86_fs, width: 16)
                                ),
                                sig(:ecx, width: 32)
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
  assign :cr0_pe_to_reg,
    mux(
      sig(:cond_110, width: 1),
      (
          sig(:cr0_pe, width: 1) |
          sig(:result2, width: 32)[0]
      ),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1),
        sig(:result2, width: 32)[0],
        sig(:cr0_pe, width: 1)
      )
    )
  assign :ss_cache_valid_to_reg,
    (
        sig(:cond_87, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_36, width: 1) &
            sig(:ss_cache_valid, width: 1)
        )
    )
  assign :pflag_to_reg,
    mux(
      sig(:cond_0, width: 1),
      sig(:pflag_result, width: 1),
      mux(
        sig(:cond_24, width: 1),
        sig(:pflag_result, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1),
          sig(:pflag_result, width: 1),
          mux(
            sig(:cond_37, width: 1),
            sig(:pflag_result, width: 1),
            mux(
              sig(:cond_51, width: 1),
              sig(:eax, width: 32)[10],
              mux(
                sig(:cond_66, width: 1),
                sig(:pflag_result, width: 1),
                mux(
                  sig(:cond_82, width: 1),
                  sig(:glob_param_3, width: 32)[2],
                  mux(
                    sig(:cond_87, width: 1),
                    sig(:glob_param_3, width: 32)[2],
                    mux(
                      sig(:cond_89, width: 1),
                      sig(:glob_param_3, width: 32)[2],
                      mux(
                        sig(:cond_93, width: 1),
                        sig(:glob_param_5, width: 32)[2],
                        mux(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_40, width: 1),
                          sig(:pflag_result, width: 1),
                          mux(
                            sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
                            sig(:pflag_result, width: 1),
                            (
                                sig(:__VdfgRegularize_hcdb8a1dc_0_41, width: 1) |
                                mux(
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_162, width: 1),
                                  sig(:pflag_result, width: 1),
                                  mux(
                                    sig(:cond_133, width: 1),
                                    sig(:pflag_result, width: 1),
                                    mux(
                                      sig(:__VdfgRegularize_hcdb8a1dc_0_42, width: 1),
                                      sig(:pflag_result, width: 1),
                                      mux(
                                        sig(:cond_139, width: 1),
                                        sig(:pflag_result, width: 1),
                                        mux(
                                          sig(:cond_142, width: 1),
                                          sig(:pflag_result, width: 1),
                                          mux(
                                            sig(:cond_145, width: 1),
                                            sig(:pflag_result, width: 1),
                                            mux(
                                              sig(:cond_216, width: 1),
                                              sig(:result2, width: 32)[2],
                                              mux(
                                                sig(:wr_glob_param_3_set, width: 1),
                                                sig(:task_eflags, width: 32)[2],
                                                mux(
                                                  sig(:cond_272, width: 1),
                                                  sig(:pflag_result, width: 1),
                                                  mux(
                                                    sig(:cond_273, width: 1),
                                                    sig(:pflag_result, width: 1),
                                                    mux(
                                                      sig(:__VdfgRegularize_hcdb8a1dc_0_161, width: 1),
                                                      sig(:pflag_result, width: 1),
                                                      sig(:pflag, width: 1)
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
  assign :dr6_breakpoints_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_37, width: 1),
      sig(:result2, width: 32)[3..0],
      sig(:dr6_breakpoints, width: 4)
    )
  assign :cs_rpl_to_reg,
    mux(
      sig(:cond_87, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:wr_glob_param_3_set, width: 1),
        lit(3, width: 2, base: "h", signed: false),
        mux(
          (
              sig(:cond_244, width: 1) &
              sig(:cond_20, width: 1)
          ),
          sig(:wr_task_rpl, width: 2),
          sig(:cs_rpl, width: 2)
        )
      )
    )
  assign :es_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_34, width: 1),
      lit(0, width: 16, base: "h", signed: false),
      mux(
        sig(:cond_87, width: 1),
        sig(:task_ss, width: 16),
        mux(
          sig(:wr_glob_param_3_set, width: 1),
          sig(:task_es, width: 16),
          sig(:es, width: 16)
        )
      )
    )
  assign :cflag_to_reg,
    mux(
      sig(:cond_0, width: 1),
      sig(:cflag_arith, width: 1),
      mux(
        sig(:cond_24, width: 1),
        sig(:cflag_arith, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_164, width: 1),
          sig(:cflag_arith, width: 1),
          (
              (
                ~sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[22]
              ) &
              mux(
                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[24],
                sig(:__VdfgRegularize_hcdb8a1dc_0_72, width: 1),
                (
                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[25] |
                    mux(
                      sig(:cond_51, width: 1),
                      sig(:eax, width: 32)[8],
                      mux(
                        sig(:cond_66, width: 1),
                        sig(:cflag_arith, width: 1),
                        mux(
                          sig(:cond_78, width: 1),
                          sig(:cond_5, width: 1),
                          mux(
                            sig(:cond_82, width: 1),
                            sig(:glob_param_3, width: 32)[0],
                            mux(
                              sig(:cond_87, width: 1),
                              sig(:glob_param_3, width: 32)[0],
                              mux(
                                sig(:cond_89, width: 1),
                                sig(:glob_param_3, width: 32)[0],
                                mux(
                                  sig(:cond_93, width: 1),
                                  sig(:glob_param_5, width: 32)[0],
                                  mux(
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_46, width: 1),
                                    sig(:cond_5, width: 1),
                                    mux(
                                      sig(:__VdfgRegularize_hcdb8a1dc_0_163, width: 1),
                                      sig(:cflag_arith, width: 1),
                                      (
                                          sig(:__VdfgRegularize_hcdb8a1dc_0_47, width: 1) &
                                          mux(
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_162, width: 1),
                                            sig(:cflag_arith, width: 1),
                                            mux(
                                              sig(:cond_133, width: 1),
                                              sig(:wr_mult_overflow, width: 1),
                                              mux(
                                                sig(:__VdfgRegularize_hcdb8a1dc_0_48, width: 1),
                                                sig(:cond_5, width: 1),
                                                mux(
                                                  sig(:cond_139, width: 1),
                                                  sig(:cflag_arith, width: 1),
                                                  mux(
                                                    sig(:cond_142, width: 1),
                                                    sig(:wr_mult_overflow, width: 1),
                                                    mux(
                                                      sig(:cond_145, width: 1),
                                                      sig(:cflag_arith, width: 1),
                                                      mux(
                                                        sig(:cond_216, width: 1),
                                                        sig(:result2, width: 32)[0],
                                                        mux(
                                                          sig(:wr_glob_param_3_set, width: 1),
                                                          sig(:task_eflags, width: 32)[0],
                                                          mux(
                                                            sig(:cond_272, width: 1),
                                                            sig(:result_signals, width: 5)[1],
                                                            mux(
                                                              sig(:cond_273, width: 1),
                                                              sig(:cond_5, width: 1),
                                                              mux(
                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_161, width: 1),
                                                                sig(:cflag_arith, width: 1),
                                                                sig(:cflag, width: 1)
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
  assign :idflag_to_reg,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_53, width: 1),
      sig(:glob_param_3, width: 32)[21],
      mux(
        sig(:cond_87, width: 1),
        sig(:glob_param_3, width: 32)[21],
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_54, width: 1),
          sig(:glob_param_3, width: 32)[21],
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_55, width: 1),
            sig(:glob_param_5, width: 32)[21],
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_56, width: 1),
              sig(:result2, width: 32)[21],
              mux(
                sig(:wr_glob_param_3_set, width: 1),
                sig(:task_eflags, width: 32)[21],
                sig(:idflag, width: 1)
              )
            )
          )
        )
      )
    )
  assign :wr_make_esp_commit,
    (
        sig(:cond_12, width: 1) |
        (
            sig(:cond_60, width: 1) |
            (
                sig(:cond_62, width: 1) |
                (
                    sig(:cond_63, width: 1) |
                    (
                        sig(:cond_76, width: 1) |
                        (
                            sig(:cond_82, width: 1) |
                            (
                                (
                                    sig(:cond_98, width: 1) &
                                    (
                                        (
                                          ~sig(:wr_dst_is_memory, width: 1)
                                        ) |
                                        sig(:write_for_wr_ready, width: 1)
                                    )
                                ) |
                                (
                                    (
                                        sig(:cond_124, width: 1) &
                                        (
                                            sig(:cond_264, width: 1) &
                                            sig(:cond_22, width: 1)
                                        )
                                    ) |
                                    (
                                        sig(:cond_131, width: 1) |
                                        (
                                            sig(:cond_149, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_hcdb8a1dc_0_158, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_157, width: 1) |
                                                    (
                                                        sig(:wr_validate_seg_regs, width: 1) |
                                                        (
                                                            sig(:wr_glob_param_3_set, width: 1) |
                                                            (
                                                                sig(:cond_255, width: 1) |
                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_45, width: 1)
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
  assign :wr_glob_param_3_value,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
        sig(:glob_param_3, width: 32),
        (
            lit(131072, width: 32, base: "h", signed: false) |
            sig(:glob_param_3, width: 32)
        )
      ),
      lit(0, width: 32, base: "h", signed: false)
    )
  assign :wr_seg_sel,
    mux(
      sig(:cond_67, width: 1),
      sig(:wr_IRET_to_v86_cs, width: 16),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_145, width: 1),
        sig(:wr_IRET_to_v86_cs, width: 16),
        mux(
          sig(:cond_174, width: 1),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_144, width: 1),
            sig(:glob_param_1, width: 32)[15..2].concat(
              sig(:cpl, width: 2)
            ),
            sig(:wr_IRET_to_v86_cs, width: 16)
          ),
          mux(
            sig(:cond_177, width: 1),
            sig(:glob_param_1, width: 32)[15..2].concat(
              sig(:glob_descriptor, width: 64)[46..45]
            ),
            mux(
              sig(:cond_179, width: 1),
              sig(:wr_IRET_to_v86_cs, width: 16),
              mux(
                sig(:cond_180, width: 1),
                sig(:wr_IRET_to_v86_cs, width: 16),
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1),
                  sig(:wr_IRET_to_v86_cs, width: 16),
                  lit(0, width: 16, base: "h", signed: false)
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_145,
    (
        (
          ~(
              sig(:protected_mode, width: 1) &
              (
                  sig(:__VdfgRegularize_hcdb8a1dc_0_22, width: 1) |
                  sig(:glob_param_1, width: 32)[19]
              )
          )
        ) &
        sig(:cond_70, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_144,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] |
        sig(:__VdfgRegularize_hcdb8a1dc_1_0, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_76,
    (
        sig(:cond_244, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_31, width: 1) &
            sig(:glob_descriptor, width: 64)[40]
        )
    )
  assign :wr_exception_finished,
    (
        sig(:cond_60, width: 1) |
        (
            sig(:cond_62, width: 1) |
            (
                sig(:cond_63, width: 1) |
                sig(:cond_255, width: 1)
            )
        )
    )
  assign :wr_seg_cache_mask,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_77, width: 1),
      lit(62890965597224959, width: 64, base: "h", signed: false),
      lit(0, width: 64, base: "h", signed: false)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_77,
    (
        sig(:cond_67, width: 1) &
        sig(:real_mode, width: 1)
    )
  assign :write_seg_cache,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_78, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_77, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_79, width: 1) |
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_143, width: 1) |
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_81, width: 1) |
                        (
                            sig(:__VdfgRegularize_hcdb8a1dc_0_158, width: 1) |
                            (
                                sig(:__VdfgRegularize_hcdb8a1dc_0_157, width: 1) |
                                (
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_141, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_140, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_138, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_hcdb8a1dc_0_137, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_136, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_135, width: 1) |
                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_84, width: 1)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_78,
    (
        sig(:cond_67, width: 1) &
        sig(:v8086_mode, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_79,
    (
        sig(:cond_67, width: 1) &
        (
            sig(:protected_mode, width: 1) &
            sig(:__VdfgRegularize_hcdb8a1dc_0_22, width: 1)
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_143,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_80, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_81,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_145, width: 1) &
        (
            (
                lit(6, width: 3, base: "h", signed: false) ==
                sig(:glob_param_1, width: 32)[18..16]
            ) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_23, width: 1) &
                sig(:glob_descriptor, width: 64)[40]
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_141,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_142, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_140,
    (
        sig(:glob_descriptor, width: 64)[40] &
        sig(:cond_177, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_138,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_139, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_137,
    (
        sig(:glob_descriptor, width: 64)[40] &
        sig(:cond_179, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_136,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_82, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_135,
    (
        (
          ~sig(:cond_181, width: 1)
        ) &
        sig(:cond_180, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_84,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_134, width: 1) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1)
    )
  assign :wr_seg_rpl,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_78, width: 1),
      lit(3, width: 2, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_77, width: 1),
        lit(0, width: 2, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_79, width: 1),
          sig(:glob_param_1, width: 32)[1..0],
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_145, width: 1),
            sig(:glob_param_1, width: 32)[1..0],
            mux(
              sig(:cond_174, width: 1),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_144, width: 1),
                sig(:cpl, width: 2),
                sig(:glob_param_1, width: 32)[1..0]
              ),
              mux(
                sig(:cond_177, width: 1),
                sig(:glob_descriptor, width: 64)[46..45],
                mux(
                  sig(:cond_179, width: 1),
                  sig(:glob_param_1, width: 32)[1..0],
                  mux(
                    sig(:cond_180, width: 1),
                    sig(:glob_param_1, width: 32)[1..0],
                    mux(
                      sig(:__VdfgRegularize_hcdb8a1dc_0_85, width: 1),
                      lit(3, width: 2, base: "h", signed: false),
                      lit(0, width: 2, base: "h", signed: false)
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_85,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1) &
        sig(:v8086_mode, width: 1)
    )
  assign :wr_debug_trap_clear,
    (
        sig(:cond_57, width: 1) |
        sig(:cond_225, width: 1)
    )
  assign :write_length_word,
    (
        sig(:cond_23, width: 1) |
        (
            sig(:wr_regrm_word, width: 1) |
            (
                sig(:cond_109, width: 1) |
                sig(:__VdfgRegularize_hcdb8a1dc_0_86, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_86,
    (
        sig(:cond_258, width: 1) &
        sig(:cond_81, width: 1)
    )
  assign :wr_waiting,
    (
        (
            sig(:cond_0, width: 1) &
            sig(:cond_1, width: 1)
        ) |
        (
            (
                sig(:cond_9, width: 1) &
                sig(:cond_8, width: 1)
            ) |
            (
                (
                    sig(:cond_9, width: 1) &
                    sig(:cond_11, width: 1)
                ) |
                (
                    (
                        sig(:cond_9, width: 1) &
                        sig(:cond_14, width: 1)
                    ) |
                    (
                        (
                            sig(:cond_9, width: 1) &
                            sig(:cond_18, width: 1)
                        ) |
                        (
                            (
                                sig(:cond_9, width: 1) &
                                sig(:cond_19, width: 1)
                            ) |
                            (
                                (
                                    sig(:cond_9, width: 1) &
                                    sig(:cond_21, width: 1)
                                ) |
                                (
                                    (
                                        sig(:cond_23, width: 1) &
                                        sig(:cond_1, width: 1)
                                    ) |
                                    (
                                        (
                                            sig(:cond_24, width: 1) &
                                            sig(:cond_1, width: 1)
                                        ) |
                                        (
                                            (
                                                sig(:cond_37, width: 1) &
                                                sig(:cond_1, width: 1)
                                            ) |
                                            (
                                                (
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_38, width: 1) &
                                                    sig(:cond_1, width: 1)
                                                ) |
                                                (
                                                    (
                                                        sig(:cond_9, width: 1) &
                                                        sig(:cond_54, width: 1)
                                                    ) |
                                                    (
                                                        (
                                                            sig(:cond_9, width: 1) &
                                                            sig(:cond_55, width: 1)
                                                        ) |
                                                        (
                                                            (
                                                                sig(:cond_9, width: 1) &
                                                                sig(:cond_65, width: 1)
                                                            ) |
                                                            (
                                                                (
                                                                    sig(:cond_9, width: 1) &
                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_80, width: 1)
                                                                ) |
                                                                (
                                                                    (
                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_87, width: 1) &
                                                                        sig(:cond_1, width: 1)
                                                                    ) |
                                                                    (
                                                                        (
                                                                            sig(:cond_98, width: 1) &
                                                                            sig(:cond_1, width: 1)
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_133, width: 1) &
                                                                                sig(:cond_1, width: 1)
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    sig(:cond_109, width: 1) &
                                                                                    sig(:cond_1, width: 1)
                                                                                ) |
                                                                                (
                                                                                    (
                                                                                        sig(:cond_9, width: 1) &
                                                                                        sig(:cond_124, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        (
                                                                                            sig(:cond_128, width: 1) &
                                                                                            sig(:cond_1, width: 1)
                                                                                        ) |
                                                                                        (
                                                                                            (
                                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_41, width: 1) &
                                                                                                sig(:cond_1, width: 1)
                                                                                            ) |
                                                                                            (
                                                                                                (
                                                                                                    sig(:cond_9, width: 1) &
                                                                                                    sig(:cond_130, width: 1)
                                                                                                ) |
                                                                                                (
                                                                                                    (
                                                                                                        sig(:cond_9, width: 1) &
                                                                                                        sig(:cond_132, width: 1)
                                                                                                    ) |
                                                                                                    (
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_132, width: 1) &
                                                                                                            sig(:cond_1, width: 1)
                                                                                                        ) |
                                                                                                        (
                                                                                                            (
                                                                                                                sig(:cond_139, width: 1) &
                                                                                                                (
                                                                                                                    sig(:cond_141, width: 1) &
                                                                                                                    sig(:cond_1, width: 1)
                                                                                                                )
                                                                                                            ) |
                                                                                                            (
                                                                                                                (
                                                                                                                    sig(:cond_156, width: 1) &
                                                                                                                    sig(:cond_1, width: 1)
                                                                                                                ) |
                                                                                                                (
                                                                                                                    (
                                                                                                                        sig(:cond_9, width: 1) &
                                                                                                                        sig(:cond_158, width: 1)
                                                                                                                    ) |
                                                                                                                    (
                                                                                                                        (
                                                                                                                            sig(:cond_169, width: 1) &
                                                                                                                            sig(:cond_1, width: 1)
                                                                                                                        ) |
                                                                                                                        (
                                                                                                                            (
                                                                                                                                sig(:cond_9, width: 1) &
                                                                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_159, width: 1)
                                                                                                                            ) |
                                                                                                                            (
                                                                                                                                (
                                                                                                                                    sig(:cond_9, width: 1) &
                                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_142, width: 1)
                                                                                                                                ) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:cond_9, width: 1) &
                                                                                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_139, width: 1)
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:cond_9, width: 1) &
                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_82, width: 1)
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            (
                                                                                                                                                sig(:cond_9, width: 1) &
                                                                                                                                                sig(:cond_189, width: 1)
                                                                                                                                            ) |
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    sig(:cond_9, width: 1) &
                                                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_155, width: 1)
                                                                                                                                                ) |
                                                                                                                                                (
                                                                                                                                                    (
                                                                                                                                                        sig(:cond_9, width: 1) &
                                                                                                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_152, width: 1)
                                                                                                                                                    ) |
                                                                                                                                                    (
                                                                                                                                                        (
                                                                                                                                                            sig(:cond_201, width: 1) &
                                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_147, width: 1)
                                                                                                                                                        ) |
                                                                                                                                                        (
                                                                                                                                                            (
                                                                                                                                                                sig(:cond_9, width: 1) &
                                                                                                                                                                sig(:cond_202, width: 1)
                                                                                                                                                            ) |
                                                                                                                                                            (
                                                                                                                                                                (
                                                                                                                                                                    sig(:cond_201, width: 1) &
                                                                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_88, width: 1)
                                                                                                                                                                ) |
                                                                                                                                                                (
                                                                                                                                                                    (
                                                                                                                                                                        sig(:cond_212, width: 1) &
                                                                                                                                                                        sig(:cond_1, width: 1)
                                                                                                                                                                    ) |
                                                                                                                                                                    (
                                                                                                                                                                        sig(:cond_9, width: 1) &
                                                                                                                                                                        (
                                                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_89, width: 1) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:cond_230, width: 1) |
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:cond_231, width: 1) |
                                                                                                                                                                                    (
                                                                                                                                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_90, width: 1) |
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_91, width: 1) |
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_92, width: 1) |
                                                                                                                                                                                                (
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :__VdfgRegularize_hcdb8a1dc_0_83,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ) |
                                                                                                                                                                                                    (
                                                                                                                                                                                                      sig(:__VdfgRegularize_hcdb8a1dc_0_44, width: 1) |
                                                                                                                                                                                                      (sig(:cond_258, width: 1) | sig(:__VdfgRegularize_hcdb8a1dc_0_150, width: 1))
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
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_80,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_145, width: 1) &
        (
            sig(:cond_73, width: 1) |
            (
                sig(:cond_175, width: 1) &
                sig(:__VdfgRegularize_hcdb8a1dc_0_23, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_87,
    (
        sig(:cond_78, width: 1) &
        (
            lit(0, width: 2, base: "h", signed: false) !=
            sig(:wr_cmd, width: 7)[1..0]
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_133,
    (
        sig(:cond_103, width: 1) &
        sig(:cond_102, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_132,
    (
        sig(:cond_103, width: 1) &
        sig(:cond_136, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_159,
    (
        sig(:cond_175, width: 1) &
        sig(:cond_174, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_142,
    (
        sig(:cond_175, width: 1) &
        sig(:cond_177, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_139,
    (
        sig(:cond_175, width: 1) &
        sig(:cond_179, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_82,
    (
        sig(:cond_180, width: 1) &
        sig(:cond_181, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_155,
    (
        sig(:cond_33, width: 1) &
        sig(:cond_192, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_152,
    (
        sig(:cond_33, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_153, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_147,
    (
        sig(:cond_33, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_148, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_88,
    (
        sig(:cond_210, width: 1) &
        sig(:cond_168, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_89,
    (
        sig(:cond_227, width: 1) &
        (
            (
                lit(3, width: 2, base: "h", signed: false) ==
                sig(:glob_param_1, width: 32)[17..16]
            ) |
            (
                lit(0, width: 2, base: "h", signed: false) ==
                sig(:glob_param_1, width: 32)[17..16]
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_90,
    (
        sig(:cond_232, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_7, width: 1) |
            (
                lit(11, width: 4, base: "h", signed: false) >=
                sig(:wr_cmdex, width: 4)
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_91,
    (
        sig(:cond_234, width: 1) &
        sig(:cond_235, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_92,
    (
        sig(:cond_238, width: 1) &
        (
            lit(0, width: 2, base: "h", signed: false) !=
            sig(:glob_param_1, width: 32)[17..16]
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_83,
    (
        sig(:cond_244, width: 1) &
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_31, width: 1) &
            (
                (
                  ~sig(:v8086_mode, width: 1)
                ) &
                sig(:cond_175, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_150,
    (
        sig(:cond_33, width: 1) &
        sig(:cond_261, width: 1)
    )
  assign :wr_inhibit_interrupts_and_debug,
    (
        (
            sig(:cond_44, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[19] &
                sig(:cond_117, width: 1)
            )
        ) |
        (
            sig(:cond_76, width: 1) &
            (
                lit(2, width: 3, base: "h", signed: false) ==
                sig(:wr_decoder, width: 16)[5..3]
            )
        )
    )
  assign :write_system_word,
    mux(
      sig(:cond_230, width: 1),
      sig(:__VdfgRegularize_hcdb8a1dc_0_6, width: 1),
      mux(
        sig(:cond_231, width: 1),
        sig(:__VdfgRegularize_hcdb8a1dc_0_6, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_90, width: 1),
          (
              sig(:__VdfgRegularize_hcdb8a1dc_0_6, width: 1) |
              (
                  lit(7, width: 4, base: "h", signed: false) <
                  sig(:wr_cmdex, width: 4)
              )
          ),
          sig(:__VdfgRegularize_hcdb8a1dc_0_91, width: 1)
        )
      )
    )
  assign :wr_new_push_ss_fault_check,
    (
        sig(:cond_14, width: 1) |
        (
            sig(:cond_18, width: 1) |
            (
                sig(:cond_19, width: 1) |
                (
                    sig(:cond_54, width: 1) |
                    sig(:cond_55, width: 1)
                )
            )
        )
    )
  assign :write_system_dword,
    mux(
      sig(:cond_230, width: 1),
      sig(:__VdfgRegularize_hcdb8a1dc_0_7, width: 1),
      mux(
        sig(:cond_231, width: 1),
        sig(:__VdfgRegularize_hcdb8a1dc_0_7, width: 1),
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_90, width: 1) &
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_7, width: 1) &
                (
                    lit(7, width: 4, base: "h", signed: false) >=
                    sig(:wr_cmdex, width: 4)
                )
            )
        )
      )
    )
  assign :wr_req_reset_pr,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_93, width: 1) |
        (
            sig(:cond_12, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_94, width: 1) |
                (
                    sig(:cond_38, width: 1) |
                    (
                        sig(:cond_60, width: 1) |
                        (
                            sig(:cond_62, width: 1) |
                            (
                                sig(:cond_63, width: 1) |
                                (
                                    sig(:cond_82, width: 1) |
                                    (
                                        sig(:cond_88, width: 1) |
                                        (
                                            sig(:cond_89, width: 1) |
                                            (
                                                sig(:cond_110, width: 1) |
                                                (
                                                    sig(:cond_113, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_95, width: 1) |
                                                        (
                                                            sig(:cond_149, width: 1) |
                                                            (
                                                                sig(:cond_178, width: 1) |
                                                                (
                                                                    sig(:wr_validate_seg_regs, width: 1) |
                                                                    (
                                                                        sig(:cond_204, width: 1) |
                                                                        sig(:cond_255, width: 1)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_93,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[2] &
        sig(:cond_5, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_94,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[8] &
        sig(:cond_5, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_95,
    (
        sig(:cond_143, width: 1) &
        sig(:cond_5, width: 1)
    )
  assign :write_seg_sel,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_78, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_77, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_79, width: 1) |
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_143, width: 1) |
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_81, width: 1) |
                        (
                            sig(:__VdfgRegularize_hcdb8a1dc_0_158, width: 1) |
                            (
                                sig(:__VdfgRegularize_hcdb8a1dc_0_157, width: 1) |
                                (
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_141, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_140, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_138, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_hcdb8a1dc_0_137, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_136, width: 1) |
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_135, width: 1)
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
  assign :wr_glob_param_1_set,
    (
        sig(:wr_glob_param_3_set, width: 1) |
        (
            sig(:cond_242, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_96, width: 1) |
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_97, width: 1) |
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_98, width: 1) |
                        (
                            sig(:__VdfgRegularize_hcdb8a1dc_0_99, width: 1) |
                            (
                                sig(:__VdfgRegularize_hcdb8a1dc_0_100, width: 1) |
                                (
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_101, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_102, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_103, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_hcdb8a1dc_0_104, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_105, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_107, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_108, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_109, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_110, width: 1) |
                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_111, width: 1)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_96,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_134, width: 1) &
        sig(:cond_20, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_97,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_134, width: 1) &
        sig(:cond_247, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_98,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_134, width: 1) &
        sig(:cond_248, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_99,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_134, width: 1) &
        sig(:cond_249, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_100,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_134, width: 1) &
        sig(:cond_250, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_101,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1) &
        sig(:cond_20, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_102,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1) &
        sig(:cond_247, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_103,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1) &
        sig(:cond_248, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_104,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1) &
        sig(:cond_249, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_105,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_76, width: 1) &
        sig(:cond_250, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_107,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_106, width: 1) &
        sig(:cond_20, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_108,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_106, width: 1) &
        sig(:cond_247, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_109,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_106, width: 1) &
        sig(:cond_248, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_110,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_106, width: 1) &
        sig(:cond_249, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_111,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_106, width: 1) &
        sig(:cond_250, width: 1)
    )
  assign :wr_glob_param_4_set,
    sig(:wr_glob_param_3_set, width: 1)
  assign :write_stack_virtual,
    (
        sig(:cond_10, width: 1) &
        sig(:wr_push_ss_fault_check, width: 1)
    )
  assign :wr_push_ss_fault_check,
    (
        sig(:cond_8, width: 1) |
        (
            sig(:cond_11, width: 1) |
            (
                sig(:cond_21, width: 1) |
                (
                    sig(:cond_65, width: 1) |
                    (
                        sig(:cond_124, width: 1) |
                        (
                            sig(:cond_130, width: 1) |
                            (
                                sig(:cond_132, width: 1) |
                                (
                                    sig(:cond_158, width: 1) |
                                    (
                                        sig(:cond_189, width: 1) |
                                        (
                                            sig(:cond_202, width: 1) |
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_44, width: 1)
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
  assign :wr_exception_external_set,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[75] &
        sig(:cond_20, width: 1)
    )
  assign :wr_system_linear,
    mux(
      sig(:cond_230, width: 1),
      sig(:wr_task_switch_linear, width: 32),
      mux(
        sig(:cond_231, width: 1),
        sig(:wr_task_switch_linear, width: 32),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_90, width: 1),
          sig(:wr_task_switch_linear, width: 32),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_91, width: 1),
            sig(:glob_desc_base, width: 32),
            lit(0, width: 32, base: "h", signed: false)
          )
        )
      )
    )
  assign :wr_int_soft_int_ib,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[75] &
        sig(:cond_81, width: 1)
    )
  assign :wr_error_code,
    mux(
      sig(:cond_14, width: 1),
      mux(
        (
            sig(:ss, width: 16)[1..0] ==
            sig(:cpl, width: 2)
        ),
        lit(0, width: 16, base: "h", signed: false),
        sig(:ss, width: 16)[15..2].concat(
          lit(0, width: 2, base: "h", signed: false)
        )
      ),
      mux(
        sig(:cond_18, width: 1),
        sig(:__VdfgRegularize_hcdb8a1dc_0_131, width: 16),
        mux(
          sig(:cond_19, width: 1),
          sig(:__VdfgRegularize_hcdb8a1dc_0_131, width: 16),
          mux(
            sig(:cond_54, width: 1),
            sig(:__VdfgRegularize_hcdb8a1dc_0_131, width: 16),
            mux(
              sig(:cond_55, width: 1),
              sig(:__VdfgRegularize_hcdb8a1dc_0_131, width: 16),
              lit(0, width: 16, base: "h", signed: false)
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_131,
    mux(
      (
          sig(:glob_param_1, width: 32)[1..0] ==
          sig(:cpl, width: 2)
      ),
      lit(0, width: 16, base: "h", signed: false),
      sig(:glob_param_1, width: 32)[15..2].concat(
        lit(0, width: 2, base: "h", signed: false)
      )
    )
  assign :write_string_es_virtual,
    (
        (
            sig(:cond_193, width: 1) &
            sig(:__VdfgRegularize_hcdb8a1dc_0_155, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_152, width: 1) |
            (
                sig(:cond_193, width: 1) &
                sig(:__VdfgRegularize_hcdb8a1dc_0_150, width: 1)
            )
        )
    )
  assign :write_system_touch,
    (
        (
            (
              ~sig(:cond_73, width: 1)
            ) &
            sig(:__VdfgRegularize_hcdb8a1dc_0_80, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_159, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_142, width: 1) |
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_139, width: 1) |
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_82, width: 1) |
                        sig(:__VdfgRegularize_hcdb8a1dc_0_83, width: 1)
                    )
                )
            )
        )
    )
  assign :write_virtual,
    mux(
      sig(:cond_23, width: 1),
      sig(:wr_dst_is_memory, width: 1),
      mux(
        sig(:cond_98, width: 1),
        sig(:wr_dst_is_memory, width: 1),
        mux(
          sig(:cond_109, width: 1),
          sig(:wr_dst_is_memory, width: 1),
          mux(
            sig(:cond_128, width: 1),
            sig(:wr_dst_is_memory, width: 1),
            mux(
              sig(:cond_212, width: 1),
              sig(:wr_dst_is_memory, width: 1),
              sig(:cond_258, width: 1)
            )
          )
        )
      )
    )
  assign :wr_not_finished,
    (
        sig(:cond_0, width: 1) |
        (
            (
                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
                sig(:__VdfgRegularize_hcdb8a1dc_0_9, width: 1)
            ) |
            (
                sig(:cond_7, width: 1) |
                (
                    sig(:cond_8, width: 1) |
                    (
                        sig(:cond_11, width: 1) |
                        (
                            (
                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
                                sig(:cond_123, width: 1)
                            ) |
                            (
                                sig(:cond_14, width: 1) |
                                (
                                    (
                                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] &
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_16, width: 1)
                                    ) |
                                    (
                                        (
                                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] &
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
                                        ) |
                                        (
                                            sig(:cond_18, width: 1) |
                                            (
                                                sig(:cond_19, width: 1) |
                                                (
                                                    (
                                                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[9] &
                                                        sig(:cond_81, width: 1)
                                                    ) |
                                                    (
                                                        (
                                                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[10] &
                                                            sig(:cond_81, width: 1)
                                                        ) |
                                                        (
                                                            (
                                                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[11] &
                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_12, width: 1)
                                                            ) |
                                                            (
                                                                sig(:wr_hlt_in_progress, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_112, width: 1) |
                                                                    (
                                                                        (
                                                                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[18] &
                                                                            (
                                                                                lit(3, width: 4, base: "h", signed: false) !=
                                                                                sig(:wr_cmdex, width: 4)
                                                                            )
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_165, width: 1) &
                                                                                sig(:cond_81, width: 1)
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] &
                                                                                    sig(:cond_120, width: 1)
                                                                                ) |
                                                                                (
                                                                                    (
                                                                                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] &
                                                                                        sig(:cond_123, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        sig(:cond_54, width: 1) |
                                                                                        (
                                                                                            sig(:cond_55, width: 1) |
                                                                                            (
                                                                                                sig(:cond_57, width: 1) |
                                                                                                (
                                                                                                    (
                                                                                                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] &
                                                                                                        sig(:cond_260, width: 1)
                                                                                                    ) |
                                                                                                    (
                                                                                                        (
                                                                                                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] &
                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_10, width: 1)
                                                                                                        ) |
                                                                                                        (
                                                                                                            (
                                                                                                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] &
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_20, width: 1) |
                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1)
                                                                                                                )
                                                                                                            ) |
                                                                                                            (
                                                                                                                sig(:cond_65, width: 1) |
                                                                                                                (
                                                                                                                    sig(:cond_67, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:cond_70, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:cond_75, width: 1) |
                                                                                                                            (
                                                                                                                                sig(:cond_80, width: 1) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[35] &
                                                                                                                                        (
                                                                                                                                            sig(:cond_247, width: 1) |
                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_10, width: 1)
                                                                                                                                        )
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[35] &
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    lit(7, width: 4, base: "h", signed: false) <=
                                                                                                                                                    sig(:wr_cmdex, width: 4)
                                                                                                                                                ) &
                                                                                                                                                (
                                                                                                                                                    lit(9, width: 4, base: "h", signed: false) >=
                                                                                                                                                    sig(:wr_cmdex, width: 4)
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[35] &
                                                                                                                                                (
                                                                                                                                                    (
                                                                                                                                                        lit(10, width: 4, base: "h", signed: false) <=
                                                                                                                                                        sig(:wr_cmdex, width: 4)
                                                                                                                                                    ) &
                                                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_24, width: 1)
                                                                                                                                                )
                                                                                                                                            ) |
                                                                                                                                            (
                                                                                                                                                sig(:cond_87, width: 1) |
                                                                                                                                                (
                                                                                                                                                    (
                                                                                                                                                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[40] &
                                                                                                                                                        (
                                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_25, width: 1) &
                                                                                                                                                            (
                                                                                                                                                                lit(5, width: 4, base: "h", signed: false) >=
                                                                                                                                                                sig(:wr_cmdex, width: 4)
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    ) |
                                                                                                                                                    (
                                                                                                                                                        sig(:cond_93, width: 1) |
                                                                                                                                                        (
                                                                                                                                                            sig(:cond_97, width: 1) |
                                                                                                                                                            (
                                                                                                                                                                (
                                                                                                                                                                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[45] &
                                                                                                                                                                    sig(:cond_81, width: 1)
                                                                                                                                                                ) |
                                                                                                                                                                (
                                                                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_113, width: 1) |
                                                                                                                                                                    (
                                                                                                                                                                        (
                                                                                                                                                                            sig(:cond_119, width: 1) &
                                                                                                                                                                            sig(:cond_120, width: 1)
                                                                                                                                                                        ) |
                                                                                                                                                                        (
                                                                                                                                                                            (
                                                                                                                                                                                (
                                                                                                                                                                                  ~sig(:cond_123, width: 1)
                                                                                                                                                                                ) &
                                                                                                                                                                                sig(:cond_119, width: 1)
                                                                                                                                                                            ) |
                                                                                                                                                                            (
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:cond_124, width: 1) &
                                                                                                                                                                                    (
                                                                                                                                                                                        lit(7, width: 3, base: "h", signed: false) >
                                                                                                                                                                                        sig(:wr_cmdex, width: 4)[2..0]
                                                                                                                                                                                    )
                                                                                                                                                                                ) |
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:cond_130, width: 1) |
                                                                                                                                                                                    (
                                                                                                                                                                                        sig(:cond_132, width: 1) |
                                                                                                                                                                                        (
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[58] &
                                                                                                                                                                                                sig(:cond_81, width: 1)
                                                                                                                                                                                            ) |
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:cond_147, width: 1) |
                                                                                                                                                                                                (
                                                                                                                                                                                                    (
                                                                                                                                                                                                      sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] &
                                                                                                                                                                                                      sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
                                                                                                                                                                                                    ) |
                                                                                                                                                                                                    (
                                                                                                                                                                                                      (sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] & sig(:cond_249, width: 1)) |
                                                                                                                                                                                                      ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[63] & sig(:cond_250, width: 1)) | (sig(:__VdfgRegularize_hcdb8a1dc_0_114, width: 1) | (sig(:cond_156, width: 1) | (sig(:wr_int_soft_int_ib, width: 1) | (sig(:cond_160, width: 1) | (sig(:wr_exception_external_set, width: 1) | (sig(:__VdfgRegularize_hcdb8a1dc_0_115, width: 1) | ((sig(:__VdfgRegularize_hcdb8a1dc_0_116, width: 1) & sig(:cond_167, width: 1)) | (((sig(:__VdfgRegularize_hcdb8a1dc_0_27, width: 1) | sig(:__VdfgRegularize_hcdb8a1dc_0_28, width: 1)) & sig(:__VdfgRegularize_hcdb8a1dc_0_12, width: 1)) | (sig(:cond_174, width: 1) | (sig(:cond_177, width: 1) | (sig(:cond_179, width: 1) | (sig(:cond_180, width: 1) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[3] & (sig(:__VdfgRegularize_hcdb8a1dc_0_18, width: 1) | sig(:__VdfgRegularize_hcdb8a1dc_0_19, width: 1))) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] & (sig(:cond_123, width: 1) | sig(:__VdfgRegularize_hcdb8a1dc_0_13, width: 1))) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] & sig(:cond_20, width: 1)) | (((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] & sig(:__VdfgRegularize_hcdb8a1dc_0_15, width: 1)) | (sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] & sig(:__VdfgRegularize_hcdb8a1dc_0_18, width: 1))) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] & sig(:cond_247, width: 1)) | (((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] & sig(:__VdfgRegularize_hcdb8a1dc_0_16, width: 1)) | (sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] & sig(:__VdfgRegularize_hcdb8a1dc_0_19, width: 1))) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] & sig(:cond_248, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] & sig(:__VdfgRegularize_hcdb8a1dc_0_14, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] & sig(:cond_249, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] & sig(:__VdfgRegularize_hcdb8a1dc_0_15, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] & sig(:cond_250, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[28] & sig(:__VdfgRegularize_hcdb8a1dc_0_16, width: 1)) | (sig(:cond_189, width: 1) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] & sig(:__VdfgRegularize_hcdb8a1dc_0_19, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] & sig(:cond_249, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[4] & sig(:__VdfgRegularize_hcdb8a1dc_0_14, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29] & sig(:cond_250, width: 1)) | (sig(:__VdfgRegularize_hcdb8a1dc_0_130, width: 1) | ((sig(:cond_196, width: 1) & sig(:cond_197, width: 1)) | (sig(:__VdfgRegularize_hcdb8a1dc_0_129, width: 1) | ((sig(:cond_199, width: 1) & sig(:cond_200, width: 1)) | (sig(:__VdfgRegularize_hcdb8a1dc_0_128, width: 1) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] & (sig(:cond_260, width: 1) | sig(:cond_81, width: 1))) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] & (sig(:__VdfgRegularize_hcdb8a1dc_0_9, width: 1) | sig(:__VdfgRegularize_hcdb8a1dc_0_10, width: 1))) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] & sig(:cond_250, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] & sig(:__VdfgRegularize_hcdb8a1dc_0_14, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[88] & sig(:cond_81, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[88] & sig(:cond_260, width: 1)) | ((sig(:__VdfgRegularize_hcdb8a1dc_0_116, width: 1) & sig(:cond_210, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[97] & sig(:cond_81, width: 1)) | (sig(:cond_225, width: 1) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] & (sig(:__VdfgRegularize_hcdb8a1dc_0_21, width: 1) | sig(:cond_248, width: 1))) | (sig(:cond_227, width: 1) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] & sig(:__VdfgRegularize_hcdb8a1dc_0_11, width: 1)) | (sig(:cond_230, width: 1) | (sig(:cond_231, width: 1) | (sig(:cond_232, width: 1) | (sig(:cond_234, width: 1) | ((sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[99] & ((lit(12, width: 4, base: "h", signed: false) <= sig(:wr_cmdex, width: 4)) & sig(:__VdfgRegularize_hcdb8a1dc_0_24, width: 1))) | (sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[101] | (sig(:cond_238, width: 1) | (sig(:wr_glob_param_3_set, width: 1) | (sig(:cond_242, width: 1) | (sig(:cond_244, width: 1) | (sig(:cond_253, width: 1) | (sig(:__VdfgRegularize_hcdb8a1dc_0_86, width: 1) | (sig(:__VdfgRegularize_hcdb8a1dc_0_127, width: 1) | (((~sig(:cond_264, width: 1)) & sig(:cond_263, width: 1)) | sig(:cond_266, width: 1))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
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
                    )
                )
            )
        )
    )
  assign :wr_hlt_in_progress,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[12] &
        sig(:cond_81, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_112,
    (
        sig(:cond_32, width: 1) &
        sig(:cond_36, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_24,
    (
        lit(14, width: 4, base: "h", signed: false) >=
        sig(:wr_cmdex, width: 4)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_113,
    (
        sig(:cond_107, width: 1) &
        sig(:cond_36, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_114,
    (
        sig(:cond_152, width: 1) &
        (
            sig(:cond_33, width: 1) &
            sig(:__VdfgRegularize_hcdb8a1dc_0_126, width: 1)
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_115,
    (
        sig(:cond_162, width: 1) &
        sig(:oflag, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_116,
    (
      ~sig(:cond_168, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_130,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_154, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_126, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_129,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_117, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_151, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_128,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_117, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_146, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_127,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_149, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_126, width: 1)
    )
  assign :wr_int_soft_int,
    (
        sig(:wr_int_soft_int_ib, width: 1) |
        (
            sig(:cond_160, width: 1) |
            sig(:__VdfgRegularize_hcdb8a1dc_0_115, width: 1)
        )
    )
  assign :wr_int,
    (
        sig(:wr_int_soft_int_ib, width: 1) |
        (
            sig(:cond_160, width: 1) |
            (
                sig(:wr_exception_external_set, width: 1) |
                sig(:__VdfgRegularize_hcdb8a1dc_0_115, width: 1)
            )
        )
    )
  assign :wr_debug_task_trigger,
    (
        sig(:cond_255, width: 1) &
        (
            sig(:glob_param_3, width: 32)[17] &
            sig(:exe_buffer, width: 32)[0]
        )
    )
  assign :wr_int_vector,
    mux(
      sig(:wr_int_soft_int_ib, width: 1),
      sig(:wr_decoder, width: 16)[15..8],
      mux(
        sig(:cond_160, width: 1),
        lit(3, width: 8, base: "h", signed: false),
        mux(
          sig(:wr_exception_external_set, width: 1),
          lit(1, width: 8, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_115, width: 1),
            lit(4, width: 8, base: "h", signed: false),
            lit(0, width: 8, base: "h", signed: false)
          )
        )
      )
    )
  assign :wr_string_in_progress,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_112, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_113, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_114, width: 1) |
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_130, width: 1) |
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_129, width: 1) |
                        (
                            sig(:__VdfgRegularize_hcdb8a1dc_0_128, width: 1) |
                            sig(:__VdfgRegularize_hcdb8a1dc_0_127, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :write_regrm,
    mux(
      sig(:cond_0, width: 1),
      sig(:wr_dst_is_rm, width: 1),
      (
          (
              sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[1] &
              (
                  sig(:cond_260, width: 1) &
                  (
                      (
                          lit(3, width: 2, base: "h", signed: false) !=
                          sig(:wr_modregrm_mod, width: 2)
                      ) |
                      (
                          sig(:wr_modregrm_reg, width: 3) !=
                          sig(:wr_modregrm_rm, width: 3)
                      )
                  )
              )
          ) |
          mux(
            sig(:cond_23, width: 1),
            sig(:wr_dst_is_rm, width: 1),
            mux(
              sig(:cond_24, width: 1),
              sig(:wr_dst_is_rm, width: 1),
              mux(
                sig(:cond_37, width: 1),
                (
                    sig(:wr_dst_is_implicit_reg, width: 1) |
                    sig(:wr_dst_is_rm, width: 1)
                ),
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_38, width: 1),
                  sig(:wr_dst_is_rm, width: 1),
                  (
                      sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[17] |
                      (
                          sig(:cond_42, width: 1) |
                          mux(
                            sig(:__VdfgRegularize_hcdb8a1dc_0_87, width: 1),
                            sig(:wr_dst_is_rm, width: 1),
                            (
                                sig(:cond_96, width: 1) |
                                mux(
                                  sig(:cond_98, width: 1),
                                  sig(:wr_dst_is_rm, width: 1),
                                  mux(
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_133, width: 1),
                                    sig(:wr_dst_is_rm, width: 1),
                                    mux(
                                      sig(:cond_109, width: 1),
                                      sig(:wr_dst_is_rm, width: 1),
                                      (
                                          sig(:cond_112, width: 1) |
                                          mux(
                                            sig(:cond_128, width: 1),
                                            sig(:wr_dst_is_rm, width: 1),
                                            mux(
                                              sig(:__VdfgRegularize_hcdb8a1dc_0_41, width: 1),
                                              sig(:wr_dst_is_rm, width: 1),
                                              mux(
                                                sig(:cond_133, width: 1),
                                                sig(:wr_dst_is_reg, width: 1),
                                                mux(
                                                  sig(:__VdfgRegularize_hcdb8a1dc_0_132, width: 1),
                                                  sig(:wr_dst_is_rm, width: 1),
                                                  mux(
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_118, width: 1),
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_119, width: 1),
                                                    mux(
                                                      sig(:cond_142, width: 1),
                                                      sig(:wr_dst_is_reg, width: 1),
                                                      (
                                                          sig(:cond_155, width: 1) |
                                                          mux(
                                                            sig(:cond_156, width: 1),
                                                            sig(:wr_dst_is_rm, width: 1),
                                                            (
                                                                (
                                                                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[73] &
                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
                                                                ) |
                                                                mux(
                                                                  sig(:cond_169, width: 1),
                                                                  sig(:wr_dst_is_rm, width: 1),
                                                                  (
                                                                      sig(:__VdfgRegularize_hcdb8a1dc_0_43, width: 1) |
                                                                      mux(
                                                                        sig(:cond_212, width: 1),
                                                                        (
                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_119, width: 1) |
                                                                            sig(:wr_dst_is_implicit_reg, width: 1)
                                                                        ),
                                                                        (
                                                                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[103] |
                                                                            (
                                                                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[108] |
                                                                                (
                                                                                    sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[107] |
                                                                                    (
                                                                                        sig(:cond_265, width: 1) |
                                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_161, width: 1)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_118,
    (
        sig(:cond_139, width: 1) &
        sig(:cond_141, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_119,
    (
        sig(:wr_dst_is_reg, width: 1) |
        sig(:wr_dst_is_rm, width: 1)
    )
  assign :wr_req_reset_rd,
    sig(:wr_req_reset_micro, width: 1)
  assign :wr_req_reset_micro,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_93, width: 1) |
        (
            sig(:cond_12, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_94, width: 1) |
                (
                    (
                        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[9] &
                        sig(:cond_260, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[10] &
                            sig(:cond_260, width: 1)
                        ) |
                        (
                            (
                                sig(:cond_32, width: 1) &
                                sig(:cond_35, width: 1)
                            ) |
                            (
                                sig(:cond_38, width: 1) |
                                (
                                    sig(:cond_42, width: 1) |
                                    (
                                        sig(:cond_44, width: 1) |
                                        (
                                            sig(:cond_60, width: 1) |
                                            (
                                                sig(:cond_62, width: 1) |
                                                (
                                                    sig(:cond_63, width: 1) |
                                                    (
                                                        sig(:cond_76, width: 1) |
                                                        (
                                                            sig(:cond_82, width: 1) |
                                                            (
                                                                sig(:cond_88, width: 1) |
                                                                (
                                                                    sig(:cond_89, width: 1) |
                                                                    (
                                                                        (
                                                                            sig(:cond_107, width: 1) &
                                                                            (
                                                                                sig(:cond_35, width: 1) |
                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_26, width: 1)
                                                                            )
                                                                        ) |
                                                                        (
                                                                            sig(:cond_110, width: 1) |
                                                                            (
                                                                                sig(:cond_113, width: 1) |
                                                                                (
                                                                                    (
                                                                                        sig(:cond_119, width: 1) &
                                                                                        sig(:cond_123, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        (
                                                                                            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[58] &
                                                                                            sig(:cond_260, width: 1)
                                                                                        ) |
                                                                                        (
                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_95, width: 1) |
                                                                                            (
                                                                                                sig(:cond_146, width: 1) |
                                                                                                (
                                                                                                    sig(:cond_149, width: 1) |
                                                                                                    (
                                                                                                        (
                                                                                                            sig(:cond_152, width: 1) &
                                                                                                            (
                                                                                                                sig(:wr_string_finish, width: 1) |
                                                                                                                sig(:wr_string_ignore, width: 1)
                                                                                                            )
                                                                                                        ) |
                                                                                                        (
                                                                                                            (
                                                                                                                (
                                                                                                                  ~sig(:oflag, width: 1)
                                                                                                                ) &
                                                                                                                sig(:cond_162, width: 1)
                                                                                                            ) |
                                                                                                            (
                                                                                                                sig(:cond_164, width: 1) |
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_69, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:cond_178, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:wr_validate_seg_regs, width: 1) |
                                                                                                                            (
                                                                                                                                (
                                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_154, width: 1) &
                                                                                                                                    sig(:wr_string_finish, width: 1)
                                                                                                                                ) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:cond_192, width: 1) &
                                                                                                                                        sig(:wr_string_ignore, width: 1)
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_151, width: 1) &
                                                                                                                                            sig(:cond_198, width: 1)
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_153, width: 1) &
                                                                                                                                                sig(:wr_string_ignore, width: 1)
                                                                                                                                            ) |
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_146, width: 1) &
                                                                                                                                                    sig(:cond_198, width: 1)
                                                                                                                                                ) |
                                                                                                                                                (
                                                                                                                                                    (
                                                                                                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_148, width: 1) &
                                                                                                                                                        sig(:wr_string_ignore, width: 1)
                                                                                                                                                    ) |
                                                                                                                                                    (
                                                                                                                                                        sig(:cond_204, width: 1) |
                                                                                                                                                        (
                                                                                                                                                            (
                                                                                                                                                                sig(:write_io_for_wr_ready, width: 1) &
                                                                                                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_88, width: 1)
                                                                                                                                                            ) |
                                                                                                                                                            (
                                                                                                                                                                sig(:cond_216, width: 1) |
                                                                                                                                                                (
                                                                                                                                                                    sig(:cond_255, width: 1) |
                                                                                                                                                                    (
                                                                                                                                                                        (
                                                                                                                                                                            sig(:__VdfgRegularize_hcdb8a1dc_0_149, width: 1) &
                                                                                                                                                                            sig(:wr_string_finish, width: 1)
                                                                                                                                                                        ) |
                                                                                                                                                                        (
                                                                                                                                                                            (
                                                                                                                                                                                sig(:cond_261, width: 1) &
                                                                                                                                                                                sig(:wr_string_ignore, width: 1)
                                                                                                                                                                            ) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[110] &
                                                                                                                                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_8, width: 1)
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
  assign :wr_string_gp_fault_check,
    (
        sig(:cond_192, width: 1) |
        sig(:cond_261, width: 1)
    )
  assign :write_rmw_system_dword,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_89, width: 1) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_92, width: 1)
    )
  assign :write_seg_cache_valid,
    sig(:write_seg_cache, width: 1)
  assign :write_rmw_virtual,
    mux(
      sig(:cond_0, width: 1),
      sig(:wr_dst_is_memory, width: 1),
      mux(
        sig(:cond_24, width: 1),
        sig(:wr_dst_is_memory, width: 1),
        mux(
          sig(:cond_37, width: 1),
          sig(:wr_dst_is_memory, width: 1),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_38, width: 1),
            sig(:wr_dst_is_memory, width: 1),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_87, width: 1),
              sig(:wr_dst_is_memory, width: 1),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_133, width: 1),
                sig(:wr_dst_is_memory, width: 1),
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_41, width: 1),
                  sig(:wr_dst_is_memory, width: 1),
                  mux(
                    sig(:__VdfgRegularize_hcdb8a1dc_0_132, width: 1),
                    sig(:wr_dst_is_memory, width: 1),
                    mux(
                      sig(:__VdfgRegularize_hcdb8a1dc_0_118, width: 1),
                      sig(:wr_dst_is_memory, width: 1),
                      mux(
                        sig(:cond_156, width: 1),
                        sig(:wr_dst_is_memory, width: 1),
                        (
                            sig(:cond_169, width: 1) &
                            sig(:wr_dst_is_memory, width: 1)
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
  assign :wr_glob_param_4_value,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      sig(:task_fs, width: 16).concat(
        sig(:task_gs, width: 16)
      ),
      lit(0, width: 32, base: "h", signed: false)
    )
  assign :write_length_dword,
    (
        sig(:cond_258, width: 1) &
        sig(:cond_260, width: 1)
    )
  assign :tlbflushall_do,
    (
        (
            sig(:cond_110, width: 1) &
            sig(:cond_111, width: 1)
        ) |
        (
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_33, width: 1) &
                (
                    sig(:cond_111, width: 1) |
                    (
                        (
                            sig(:cr0_wp, width: 1) ^
                            sig(:result2, width: 32)[16]
                        ) |
                        (
                            sig(:cr0_pg, width: 1) ^
                            sig(:result, width: 32)[31]
                        )
                    )
                )
            ) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_57, width: 1) |
                sig(:__VdfgRegularize_hcdb8a1dc_0_58, width: 1)
            )
        )
    )
  assign :wr_push_length_word,
    mux(
      sig(:cond_18, width: 1),
      sig(:__VdfgRegularize_hcdb8a1dc_0_120, width: 1),
      mux(
        sig(:cond_19, width: 1),
        sig(:__VdfgRegularize_hcdb8a1dc_0_120, width: 1),
        (
            sig(:cond_21, width: 1) |
            mux(
              sig(:cond_54, width: 1),
              sig(:__VdfgRegularize_hcdb8a1dc_0_120, width: 1),
              mux(
                sig(:cond_55, width: 1),
                sig(:__VdfgRegularize_hcdb8a1dc_0_120, width: 1),
                (
                    sig(:cond_65, width: 1) |
                    mux(
                      sig(:cond_189, width: 1),
                      (
                        ~sig(:glob_param_1, width: 32)[19]
                      ),
                      (
                          (
                            ~sig(:glob_param_3, width: 32)[17]
                          ) &
                          sig(:cond_253, width: 1)
                      )
                    )
                )
              )
            )
        )
      )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_120,
    (
      ~sig(:glob_param_3, width: 32)[19]
    )
  assign :wr_system_dword,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_89, width: 1),
      (
          lit(4294966783, width: 32, base: "h", signed: false) &
          sig(:glob_param_2, width: 32)
      ),
      mux(
        sig(:cond_230, width: 1),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_29, width: 1),
          sig(:exc_eip, width: 32),
          sig(:eip, width: 32)
        ),
        mux(
          sig(:cond_231, width: 1),
          (
              sig(:result_push, width: 32) &
              case_select(
                sig(:glob_descriptor, width: 64)[43..40],
                cases: {
                  3 => lit(4294950911, width: 32, base: "h", signed: false),
                  11 => lit(4294950911, width: 32, base: "h", signed: false)
                },
                default: lit(4294967295, width: 32, base: "h", signed: false)
              )
          ),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_90, width: 1),
            sig(:result2, width: 32),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_91, width: 1),
              lit(0, width: 16, base: "d", signed: false).concat(
                sig(:tr, width: 16)
              ),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_92, width: 1),
                (
                    lit(512, width: 32, base: "h", signed: false) |
                    sig(:result2, width: 32)
                ),
                lit(0, width: 32, base: "h", signed: false)
              )
            )
          )
        )
      )
    )
  assign :wr_seg_cache_valid,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_78, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_77, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_145, width: 1) |
                (
                    sig(:cond_174, width: 1) |
                    (
                        sig(:cond_177, width: 1) |
                        (
                            sig(:cond_179, width: 1) |
                            (
                                sig(:cond_180, width: 1) |
                                sig(:__VdfgRegularize_hcdb8a1dc_0_84, width: 1)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :wr_inhibit_interrupts,
    (
        (
          ~sig(:iflag, width: 1)
        ) &
        sig(:cond_220, width: 1)
    )
  assign :write_seg_rpl,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_78, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_77, width: 1) |
            (
                sig(:__VdfgRegularize_hcdb8a1dc_0_79, width: 1) |
                (
                    sig(:__VdfgRegularize_hcdb8a1dc_0_143, width: 1) |
                    (
                        sig(:__VdfgRegularize_hcdb8a1dc_0_81, width: 1) |
                        (
                            sig(:__VdfgRegularize_hcdb8a1dc_0_158, width: 1) |
                            (
                                sig(:__VdfgRegularize_hcdb8a1dc_0_157, width: 1) |
                                (
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_141, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_hcdb8a1dc_0_140, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_138, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_hcdb8a1dc_0_137, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_hcdb8a1dc_0_136, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_135, width: 1) |
                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_85, width: 1)
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
  assign :wr_req_reset_dec,
    sig(:wr_req_reset_pr, width: 1)
  assign :wr_req_reset_exe,
    sig(:wr_req_reset_micro, width: 1)
  assign :wr_push_length_dword,
    mux(
      sig(:cond_18, width: 1),
      sig(:glob_param_3, width: 32)[19],
      mux(
        sig(:cond_19, width: 1),
        sig(:glob_param_3, width: 32)[19],
        mux(
          sig(:cond_54, width: 1),
          sig(:glob_param_3, width: 32)[19],
          mux(
            sig(:cond_55, width: 1),
            sig(:glob_param_3, width: 32)[19],
            mux(
              sig(:cond_189, width: 1),
              sig(:glob_param_1, width: 32)[19],
              (
                  sig(:cond_253, width: 1) &
                  sig(:glob_param_3, width: 32)[17]
              )
            )
          )
        )
      )
    )
  assign :wr_one_cycle_wait,
    (
        sig(:cond_8, width: 1) |
        (
            sig(:cond_11, width: 1) |
            (
                sig(:cond_14, width: 1) |
                (
                    sig(:cond_18, width: 1) |
                    (
                        sig(:cond_19, width: 1) |
                        (
                            sig(:cond_21, width: 1) |
                            (
                                sig(:cond_54, width: 1) |
                                (
                                    sig(:cond_55, width: 1) |
                                    (
                                        sig(:cond_65, width: 1) |
                                        (
                                            sig(:cond_124, width: 1) |
                                            (
                                                sig(:cond_130, width: 1) |
                                                (
                                                    sig(:cond_132, width: 1) |
                                                    (
                                                        sig(:cond_158, width: 1) |
                                                        (
                                                            sig(:cond_189, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_hcdb8a1dc_0_155, width: 1) |
                                                                (
                                                                    sig(:cond_202, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_44, width: 1) |
                                                                        sig(:__VdfgRegularize_hcdb8a1dc_0_150, width: 1)
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
  assign :wr_regrm_dword,
    (
        sig(:cond_112, width: 1) |
        sig(:cond_265, width: 1)
    )
  assign :write_io,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_147, width: 1) |
        sig(:__VdfgRegularize_hcdb8a1dc_0_88, width: 1)
    )
  assign :write_eax,
    mux(
      sig(:__VdfgRegularize_hcdb8a1dc_0_118, width: 1),
      sig(:wr_dst_is_eax, width: 1),
      mux(
        sig(:cond_212, width: 1),
        sig(:wr_dst_is_eax, width: 1),
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[111]
      )
    )
  assign :write_new_stack_virtual,
    (
        sig(:cond_15, width: 1) &
        sig(:wr_new_push_ss_fault_check, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_153,
    (
        (
          ~sig(:cond_197, width: 1)
        ) &
        sig(:cond_196, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_148,
    (
        (
          ~sig(:cond_200, width: 1)
        ) &
        sig(:cond_199, width: 1)
    )
  assign :wr_make_esp_speculative,
    (
        sig(:cond_7, width: 1) |
        (
            sig(:__VdfgRegularize_hcdb8a1dc_0_160, width: 1) |
            (
                sig(:cond_57, width: 1) |
                (
                    sig(:cond_75, width: 1) |
                    (
                        (
                            sig(:cond_80, width: 1) &
                            sig(:cond_81, width: 1)
                        ) |
                        (
                            sig(:cond_97, width: 1) |
                            (
                                (
                                    sig(:cond_124, width: 1) &
                                    sig(:cond_125, width: 1)
                                ) |
                                (
                                    sig(:cond_130, width: 1) |
                                    (
                                        sig(:cond_147, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_hcdb8a1dc_0_44, width: 1) |
                                            (
                                                sig(:cond_263, width: 1) &
                                                sig(:cond_125, width: 1)
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
  assign :write_system_busy_tss,
    (
        sig(:__VdfgRegularize_hcdb8a1dc_0_80, width: 1) &
        sig(:cond_73, width: 1)
    )
  assign :wr_glob_param_1_value,
    mux(
      sig(:wr_glob_param_3_set, width: 1),
      mux(
        sig(:__VdfgRegularize_hcdb8a1dc_0_5, width: 1),
        lit(6, width: 16, base: "h", signed: false).concat(
          sig(:wr_IRET_to_v86_ds, width: 16)
        ),
        lit(6, width: 16, base: "h", signed: false).concat(
          sig(:wr_IRET_to_v86_fs, width: 16)
        )
      ),
      mux(
        sig(:cond_242, width: 1),
        lit(2, width: 16, base: "h", signed: false).concat(
          sig(:task_ss, width: 16)
        ),
        mux(
          sig(:__VdfgRegularize_hcdb8a1dc_0_96, width: 1),
          sig(:__VdfgRegularize_hcdb8a1dc_0_121, width: 32),
          mux(
            sig(:__VdfgRegularize_hcdb8a1dc_0_97, width: 1),
            sig(:__VdfgRegularize_hcdb8a1dc_0_125, width: 32),
            mux(
              sig(:__VdfgRegularize_hcdb8a1dc_0_98, width: 1),
              sig(:__VdfgRegularize_hcdb8a1dc_0_122, width: 32),
              mux(
                sig(:__VdfgRegularize_hcdb8a1dc_0_99, width: 1),
                sig(:__VdfgRegularize_hcdb8a1dc_0_123, width: 32),
                mux(
                  sig(:__VdfgRegularize_hcdb8a1dc_0_100, width: 1),
                  sig(:__VdfgRegularize_hcdb8a1dc_0_124, width: 32),
                  mux(
                    sig(:__VdfgRegularize_hcdb8a1dc_0_101, width: 1),
                    sig(:__VdfgRegularize_hcdb8a1dc_0_121, width: 32),
                    mux(
                      sig(:__VdfgRegularize_hcdb8a1dc_0_102, width: 1),
                      sig(:__VdfgRegularize_hcdb8a1dc_0_125, width: 32),
                      mux(
                        sig(:__VdfgRegularize_hcdb8a1dc_0_103, width: 1),
                        sig(:__VdfgRegularize_hcdb8a1dc_0_122, width: 32),
                        mux(
                          sig(:__VdfgRegularize_hcdb8a1dc_0_104, width: 1),
                          sig(:__VdfgRegularize_hcdb8a1dc_0_123, width: 32),
                          mux(
                            sig(:__VdfgRegularize_hcdb8a1dc_0_105, width: 1),
                            sig(:__VdfgRegularize_hcdb8a1dc_0_124, width: 32),
                            mux(
                              sig(:__VdfgRegularize_hcdb8a1dc_0_107, width: 1),
                              sig(:__VdfgRegularize_hcdb8a1dc_0_121, width: 32),
                              mux(
                                sig(:__VdfgRegularize_hcdb8a1dc_0_108, width: 1),
                                sig(:__VdfgRegularize_hcdb8a1dc_0_125, width: 32),
                                mux(
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_109, width: 1),
                                  sig(:__VdfgRegularize_hcdb8a1dc_0_122, width: 32),
                                  mux(
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_110, width: 1),
                                    sig(:__VdfgRegularize_hcdb8a1dc_0_123, width: 32),
                                    mux(
                                      sig(:__VdfgRegularize_hcdb8a1dc_0_111, width: 1),
                                      sig(:__VdfgRegularize_hcdb8a1dc_0_124, width: 32),
                                      lit(0, width: 32, base: "h", signed: false)
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
  assign :__VdfgRegularize_hcdb8a1dc_0_121,
    lit(3, width: 16, base: "h", signed: false).concat(
      sig(:task_ds, width: 16)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_125,
    lit(0, width: 16, base: "d", signed: false).concat(
      sig(:task_es, width: 16)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_122,
    lit(4, width: 16, base: "h", signed: false).concat(
      sig(:glob_param_4, width: 32)[31..16]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_123,
    lit(5, width: 16, base: "h", signed: false).concat(
      sig(:glob_param_4, width: 32)[15..0]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_124,
    lit(1, width: 16, base: "h", signed: false).concat(
      sig(:task_cs, width: 16)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_22,
    (
        lit(0, width: 14, base: "h", signed: false) ==
        sig(:glob_param_1, width: 32)[15..2]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_23,
    (
        lit(6, width: 3, base: "h", signed: false) >
        sig(:glob_param_1, width: 32)[18..16]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_31,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:glob_param_2, width: 32)[1..0]
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_134,
    (
        sig(:write_for_wr_ready, width: 1) &
        sig(:__VdfgRegularize_hcdb8a1dc_0_83, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_106,
    (
        sig(:cond_244, width: 1) &
        (
            lit(0, width: 2, base: "h", signed: false) !=
            sig(:glob_param_2, width: 32)[1..0]
        )
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_126,
    (
        (
          ~sig(:wr_string_finish, width: 1)
        ) &
        sig(:cond_34, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_0_117,
    (
      ~sig(:cond_198, width: 1)
    )
  assign :__VdfgRegularize_hcdb8a1dc_1_0,
    (
        sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[87] |
        (
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[88] |
            sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[29]
        )
    )

  # Processes

  process :initial_block_0,
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

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(((lit(99, width: 7, base: "h", signed: false) == sig(:wr_cmd, width: 7)) & (lit(9, width: 4, base: "h", signed: false) == sig(:wr_cmdex, width: 4)))) do
        assign(
          :wr_task_switch_linear_reg,
          sig(:wr_task_switch_linear, width: 32),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:wr_ready, width: 1)) do
            assign(
              :wr_task_switch_linear_reg,
              sig(:wr_task_switch_linear_next, width: 32),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :wr_task_switch_linear_reg,
          lit(0, width: 32, base: "h", signed: false),
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
    assign(
      :wr_task_rpl,
      mux(
        sig(:rst_n, width: 1),
        sig(:wr_task_rpl_to_reg, width: 2),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :initial_block_3,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :__VdfgBinToOneHot_Pre_h3ef411c2_0_0,
      lit(0, width: 7, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :combinational_logic_4,
    sensitivity: [
    ],
    clocked: false,
    initial: false do
    assign(
      sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[sig(:__VdfgBinToOneHot_Pre_h3ef411c2_0_0, width: 7)],
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      sig(:__VdfgBinToOneHot_Tab_h3ef411c2_0_0, width: 128)[sig(:wr_cmd, width: 7)],
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      :__VdfgBinToOneHot_Pre_h3ef411c2_0_0,
      sig(:wr_cmd, width: 7),
      kind: :blocking
    )
  end

end
