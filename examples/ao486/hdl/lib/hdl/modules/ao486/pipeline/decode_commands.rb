# frozen_string_literal: true

class DecodeCommands < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: decode_commands

  def self._import_decl_kinds
    {
      __VdfgBinToOneHot_Idx_h2af0f070_0_0: :logic,
      __VdfgBinToOneHot_Pre_h2af0f070_0_0: :logic,
      __VdfgBinToOneHot_Tab_h2af0f070_0_0: :logic,
      __VdfgRegularize_h2186f3a2_0_0: :logic,
      __VdfgRegularize_h2186f3a2_0_1: :logic,
      __VdfgRegularize_h2186f3a2_0_10: :logic,
      __VdfgRegularize_h2186f3a2_0_100: :logic,
      __VdfgRegularize_h2186f3a2_0_101: :logic,
      __VdfgRegularize_h2186f3a2_0_102: :logic,
      __VdfgRegularize_h2186f3a2_0_103: :logic,
      __VdfgRegularize_h2186f3a2_0_104: :logic,
      __VdfgRegularize_h2186f3a2_0_105: :logic,
      __VdfgRegularize_h2186f3a2_0_106: :logic,
      __VdfgRegularize_h2186f3a2_0_107: :logic,
      __VdfgRegularize_h2186f3a2_0_108: :logic,
      __VdfgRegularize_h2186f3a2_0_109: :logic,
      __VdfgRegularize_h2186f3a2_0_11: :logic,
      __VdfgRegularize_h2186f3a2_0_110: :logic,
      __VdfgRegularize_h2186f3a2_0_111: :logic,
      __VdfgRegularize_h2186f3a2_0_112: :logic,
      __VdfgRegularize_h2186f3a2_0_113: :logic,
      __VdfgRegularize_h2186f3a2_0_114: :logic,
      __VdfgRegularize_h2186f3a2_0_115: :logic,
      __VdfgRegularize_h2186f3a2_0_116: :logic,
      __VdfgRegularize_h2186f3a2_0_117: :logic,
      __VdfgRegularize_h2186f3a2_0_118: :logic,
      __VdfgRegularize_h2186f3a2_0_119: :logic,
      __VdfgRegularize_h2186f3a2_0_12: :logic,
      __VdfgRegularize_h2186f3a2_0_120: :logic,
      __VdfgRegularize_h2186f3a2_0_121: :logic,
      __VdfgRegularize_h2186f3a2_0_122: :logic,
      __VdfgRegularize_h2186f3a2_0_123: :logic,
      __VdfgRegularize_h2186f3a2_0_124: :logic,
      __VdfgRegularize_h2186f3a2_0_125: :logic,
      __VdfgRegularize_h2186f3a2_0_126: :logic,
      __VdfgRegularize_h2186f3a2_0_127: :logic,
      __VdfgRegularize_h2186f3a2_0_128: :logic,
      __VdfgRegularize_h2186f3a2_0_129: :logic,
      __VdfgRegularize_h2186f3a2_0_13: :logic,
      __VdfgRegularize_h2186f3a2_0_130: :logic,
      __VdfgRegularize_h2186f3a2_0_131: :logic,
      __VdfgRegularize_h2186f3a2_0_132: :logic,
      __VdfgRegularize_h2186f3a2_0_133: :logic,
      __VdfgRegularize_h2186f3a2_0_134: :logic,
      __VdfgRegularize_h2186f3a2_0_135: :logic,
      __VdfgRegularize_h2186f3a2_0_136: :logic,
      __VdfgRegularize_h2186f3a2_0_137: :logic,
      __VdfgRegularize_h2186f3a2_0_138: :logic,
      __VdfgRegularize_h2186f3a2_0_139: :logic,
      __VdfgRegularize_h2186f3a2_0_14: :logic,
      __VdfgRegularize_h2186f3a2_0_140: :logic,
      __VdfgRegularize_h2186f3a2_0_141: :logic,
      __VdfgRegularize_h2186f3a2_0_142: :logic,
      __VdfgRegularize_h2186f3a2_0_143: :logic,
      __VdfgRegularize_h2186f3a2_0_144: :logic,
      __VdfgRegularize_h2186f3a2_0_145: :logic,
      __VdfgRegularize_h2186f3a2_0_146: :logic,
      __VdfgRegularize_h2186f3a2_0_147: :logic,
      __VdfgRegularize_h2186f3a2_0_148: :logic,
      __VdfgRegularize_h2186f3a2_0_149: :logic,
      __VdfgRegularize_h2186f3a2_0_15: :logic,
      __VdfgRegularize_h2186f3a2_0_150: :logic,
      __VdfgRegularize_h2186f3a2_0_151: :logic,
      __VdfgRegularize_h2186f3a2_0_152: :logic,
      __VdfgRegularize_h2186f3a2_0_153: :logic,
      __VdfgRegularize_h2186f3a2_0_154: :logic,
      __VdfgRegularize_h2186f3a2_0_155: :logic,
      __VdfgRegularize_h2186f3a2_0_156: :logic,
      __VdfgRegularize_h2186f3a2_0_157: :logic,
      __VdfgRegularize_h2186f3a2_0_158: :logic,
      __VdfgRegularize_h2186f3a2_0_159: :logic,
      __VdfgRegularize_h2186f3a2_0_16: :logic,
      __VdfgRegularize_h2186f3a2_0_160: :logic,
      __VdfgRegularize_h2186f3a2_0_161: :logic,
      __VdfgRegularize_h2186f3a2_0_162: :logic,
      __VdfgRegularize_h2186f3a2_0_163: :logic,
      __VdfgRegularize_h2186f3a2_0_17: :logic,
      __VdfgRegularize_h2186f3a2_0_18: :logic,
      __VdfgRegularize_h2186f3a2_0_19: :logic,
      __VdfgRegularize_h2186f3a2_0_2: :logic,
      __VdfgRegularize_h2186f3a2_0_20: :logic,
      __VdfgRegularize_h2186f3a2_0_21: :logic,
      __VdfgRegularize_h2186f3a2_0_22: :logic,
      __VdfgRegularize_h2186f3a2_0_23: :logic,
      __VdfgRegularize_h2186f3a2_0_24: :logic,
      __VdfgRegularize_h2186f3a2_0_25: :logic,
      __VdfgRegularize_h2186f3a2_0_26: :logic,
      __VdfgRegularize_h2186f3a2_0_27: :logic,
      __VdfgRegularize_h2186f3a2_0_28: :logic,
      __VdfgRegularize_h2186f3a2_0_29: :logic,
      __VdfgRegularize_h2186f3a2_0_3: :logic,
      __VdfgRegularize_h2186f3a2_0_30: :logic,
      __VdfgRegularize_h2186f3a2_0_31: :logic,
      __VdfgRegularize_h2186f3a2_0_32: :logic,
      __VdfgRegularize_h2186f3a2_0_33: :logic,
      __VdfgRegularize_h2186f3a2_0_34: :logic,
      __VdfgRegularize_h2186f3a2_0_35: :logic,
      __VdfgRegularize_h2186f3a2_0_36: :logic,
      __VdfgRegularize_h2186f3a2_0_37: :logic,
      __VdfgRegularize_h2186f3a2_0_38: :logic,
      __VdfgRegularize_h2186f3a2_0_39: :logic,
      __VdfgRegularize_h2186f3a2_0_4: :logic,
      __VdfgRegularize_h2186f3a2_0_40: :logic,
      __VdfgRegularize_h2186f3a2_0_41: :logic,
      __VdfgRegularize_h2186f3a2_0_42: :logic,
      __VdfgRegularize_h2186f3a2_0_43: :logic,
      __VdfgRegularize_h2186f3a2_0_44: :logic,
      __VdfgRegularize_h2186f3a2_0_45: :logic,
      __VdfgRegularize_h2186f3a2_0_46: :logic,
      __VdfgRegularize_h2186f3a2_0_47: :logic,
      __VdfgRegularize_h2186f3a2_0_48: :logic,
      __VdfgRegularize_h2186f3a2_0_49: :logic,
      __VdfgRegularize_h2186f3a2_0_5: :logic,
      __VdfgRegularize_h2186f3a2_0_50: :logic,
      __VdfgRegularize_h2186f3a2_0_51: :logic,
      __VdfgRegularize_h2186f3a2_0_52: :logic,
      __VdfgRegularize_h2186f3a2_0_53: :logic,
      __VdfgRegularize_h2186f3a2_0_54: :logic,
      __VdfgRegularize_h2186f3a2_0_55: :logic,
      __VdfgRegularize_h2186f3a2_0_56: :logic,
      __VdfgRegularize_h2186f3a2_0_57: :logic,
      __VdfgRegularize_h2186f3a2_0_58: :logic,
      __VdfgRegularize_h2186f3a2_0_59: :logic,
      __VdfgRegularize_h2186f3a2_0_6: :logic,
      __VdfgRegularize_h2186f3a2_0_60: :logic,
      __VdfgRegularize_h2186f3a2_0_61: :logic,
      __VdfgRegularize_h2186f3a2_0_62: :logic,
      __VdfgRegularize_h2186f3a2_0_63: :logic,
      __VdfgRegularize_h2186f3a2_0_64: :logic,
      __VdfgRegularize_h2186f3a2_0_65: :logic,
      __VdfgRegularize_h2186f3a2_0_66: :logic,
      __VdfgRegularize_h2186f3a2_0_67: :logic,
      __VdfgRegularize_h2186f3a2_0_68: :logic,
      __VdfgRegularize_h2186f3a2_0_69: :logic,
      __VdfgRegularize_h2186f3a2_0_7: :logic,
      __VdfgRegularize_h2186f3a2_0_70: :logic,
      __VdfgRegularize_h2186f3a2_0_71: :logic,
      __VdfgRegularize_h2186f3a2_0_72: :logic,
      __VdfgRegularize_h2186f3a2_0_73: :logic,
      __VdfgRegularize_h2186f3a2_0_74: :logic,
      __VdfgRegularize_h2186f3a2_0_75: :logic,
      __VdfgRegularize_h2186f3a2_0_76: :logic,
      __VdfgRegularize_h2186f3a2_0_77: :logic,
      __VdfgRegularize_h2186f3a2_0_78: :logic,
      __VdfgRegularize_h2186f3a2_0_79: :logic,
      __VdfgRegularize_h2186f3a2_0_8: :logic,
      __VdfgRegularize_h2186f3a2_0_80: :logic,
      __VdfgRegularize_h2186f3a2_0_81: :logic,
      __VdfgRegularize_h2186f3a2_0_82: :logic,
      __VdfgRegularize_h2186f3a2_0_83: :logic,
      __VdfgRegularize_h2186f3a2_0_84: :logic,
      __VdfgRegularize_h2186f3a2_0_85: :logic,
      __VdfgRegularize_h2186f3a2_0_86: :logic,
      __VdfgRegularize_h2186f3a2_0_87: :logic,
      __VdfgRegularize_h2186f3a2_0_88: :logic,
      __VdfgRegularize_h2186f3a2_0_89: :logic,
      __VdfgRegularize_h2186f3a2_0_9: :logic,
      __VdfgRegularize_h2186f3a2_0_90: :logic,
      __VdfgRegularize_h2186f3a2_0_91: :logic,
      __VdfgRegularize_h2186f3a2_0_92: :logic,
      __VdfgRegularize_h2186f3a2_0_93: :logic,
      __VdfgRegularize_h2186f3a2_0_94: :logic,
      __VdfgRegularize_h2186f3a2_0_95: :logic,
      __VdfgRegularize_h2186f3a2_0_96: :logic,
      __VdfgRegularize_h2186f3a2_0_97: :logic,
      __VdfgRegularize_h2186f3a2_0_98: :logic,
      __VdfgRegularize_h2186f3a2_0_99: :logic,
      _unused_ok: :wire,
      cond_0: :wire,
      cond_1: :wire,
      cond_10: :wire,
      cond_100: :wire,
      cond_102: :wire,
      cond_103: :wire,
      cond_104: :wire,
      cond_105: :wire,
      cond_106: :wire,
      cond_107: :wire,
      cond_108: :wire,
      cond_109: :wire,
      cond_11: :wire,
      cond_110: :wire,
      cond_111: :wire,
      cond_113: :wire,
      cond_114: :wire,
      cond_115: :wire,
      cond_116: :wire,
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
      cond_126: :wire,
      cond_127: :wire,
      cond_128: :wire,
      cond_129: :wire,
      cond_13: :wire,
      cond_130: :wire,
      cond_131: :wire,
      cond_132: :wire,
      cond_133: :wire,
      cond_134: :wire,
      cond_135: :wire,
      cond_136: :wire,
      cond_137: :wire,
      cond_138: :wire,
      cond_139: :wire,
      cond_14: :wire,
      cond_140: :wire,
      cond_141: :wire,
      cond_142: :wire,
      cond_143: :wire,
      cond_15: :wire,
      cond_16: :wire,
      cond_17: :wire,
      cond_2: :wire,
      cond_20: :wire,
      cond_21: :wire,
      cond_22: :wire,
      cond_23: :wire,
      cond_24: :wire,
      cond_25: :wire,
      cond_26: :wire,
      cond_27: :wire,
      cond_28: :wire,
      cond_29: :wire,
      cond_3: :wire,
      cond_30: :wire,
      cond_31: :wire,
      cond_32: :wire,
      cond_33: :wire,
      cond_34: :wire,
      cond_35: :wire,
      cond_36: :wire,
      cond_37: :wire,
      cond_38: :wire,
      cond_39: :wire,
      cond_40: :wire,
      cond_41: :wire,
      cond_42: :wire,
      cond_43: :wire,
      cond_44: :wire,
      cond_45: :wire,
      cond_46: :wire,
      cond_47: :wire,
      cond_48: :wire,
      cond_49: :wire,
      cond_5: :wire,
      cond_50: :wire,
      cond_51: :wire,
      cond_52: :wire,
      cond_53: :wire,
      cond_54: :wire,
      cond_55: :wire,
      cond_56: :wire,
      cond_57: :wire,
      cond_58: :wire,
      cond_59: :wire,
      cond_6: :wire,
      cond_60: :wire,
      cond_61: :wire,
      cond_62: :wire,
      cond_63: :wire,
      cond_64: :wire,
      cond_65: :wire,
      cond_66: :wire,
      cond_67: :wire,
      cond_68: :wire,
      cond_69: :wire,
      cond_7: :wire,
      cond_70: :wire,
      cond_71: :wire,
      cond_72: :wire,
      cond_73: :wire,
      cond_74: :wire,
      cond_75: :wire,
      cond_76: :wire,
      cond_77: :wire,
      cond_78: :wire,
      cond_79: :wire,
      cond_8: :wire,
      cond_80: :wire,
      cond_81: :wire,
      cond_82: :wire,
      cond_83: :wire,
      cond_84: :wire,
      cond_85: :wire,
      cond_86: :wire,
      cond_87: :wire,
      cond_88: :wire,
      cond_89: :wire,
      cond_9: :wire,
      cond_90: :wire,
      cond_91: :wire,
      cond_92: :wire,
      cond_93: :wire,
      cond_94: :wire,
      cond_95: :wire,
      cond_96: :wire,
      cond_97: :wire,
      cond_98: :wire,
      cond_99: :wire
    }
  end

  # Ports

  input :protected_mode
  input :dec_ready_one
  input :dec_ready_one_one
  input :dec_ready_one_two
  input :dec_ready_one_three
  input :dec_ready_2byte_one
  input :dec_ready_modregrm_one
  input :dec_ready_2byte_modregrm
  input :dec_ready_call_jmp_imm
  input :dec_ready_one_imm
  input :dec_ready_2byte_imm
  input :dec_ready_mem_offset
  input :dec_ready_modregrm_imm
  input :dec_ready_2byte_modregrm_imm
  input :decoder, width: 96
  input :prefix_group_1_lock
  input :dec_prefix_group_1_rep, width: 2
  input :dec_prefix_2byte
  output :consume_one
  output :consume_one_one
  output :consume_one_two
  output :consume_one_three
  output :consume_call_jmp_imm
  output :consume_modregrm_one
  output :consume_one_imm
  output :consume_modregrm_imm
  output :consume_mem_offset
  output :dec_exception_ud
  output :dec_is_8bit
  output :dec_cmd, width: 7
  output :dec_cmdex, width: 4
  output :dec_is_complex

  # Signals

  signal :__VdfgBinToOneHot_Idx_h2af0f070_0_0, width: 8
  signal :__VdfgBinToOneHot_Pre_h2af0f070_0_0, width: 8
  signal :__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256
  signal :__VdfgRegularize_h2186f3a2_0_0
  signal :__VdfgRegularize_h2186f3a2_0_1
  signal :__VdfgRegularize_h2186f3a2_0_10
  signal :__VdfgRegularize_h2186f3a2_0_100
  signal :__VdfgRegularize_h2186f3a2_0_101
  signal :__VdfgRegularize_h2186f3a2_0_102
  signal :__VdfgRegularize_h2186f3a2_0_103
  signal :__VdfgRegularize_h2186f3a2_0_104
  signal :__VdfgRegularize_h2186f3a2_0_105
  signal :__VdfgRegularize_h2186f3a2_0_106
  signal :__VdfgRegularize_h2186f3a2_0_107
  signal :__VdfgRegularize_h2186f3a2_0_108
  signal :__VdfgRegularize_h2186f3a2_0_109
  signal :__VdfgRegularize_h2186f3a2_0_11
  signal :__VdfgRegularize_h2186f3a2_0_110
  signal :__VdfgRegularize_h2186f3a2_0_111
  signal :__VdfgRegularize_h2186f3a2_0_112
  signal :__VdfgRegularize_h2186f3a2_0_113
  signal :__VdfgRegularize_h2186f3a2_0_114
  signal :__VdfgRegularize_h2186f3a2_0_115
  signal :__VdfgRegularize_h2186f3a2_0_116
  signal :__VdfgRegularize_h2186f3a2_0_117
  signal :__VdfgRegularize_h2186f3a2_0_118
  signal :__VdfgRegularize_h2186f3a2_0_119
  signal :__VdfgRegularize_h2186f3a2_0_12
  signal :__VdfgRegularize_h2186f3a2_0_120
  signal :__VdfgRegularize_h2186f3a2_0_121
  signal :__VdfgRegularize_h2186f3a2_0_122
  signal :__VdfgRegularize_h2186f3a2_0_123
  signal :__VdfgRegularize_h2186f3a2_0_124
  signal :__VdfgRegularize_h2186f3a2_0_125
  signal :__VdfgRegularize_h2186f3a2_0_126
  signal :__VdfgRegularize_h2186f3a2_0_127
  signal :__VdfgRegularize_h2186f3a2_0_128
  signal :__VdfgRegularize_h2186f3a2_0_129
  signal :__VdfgRegularize_h2186f3a2_0_13
  signal :__VdfgRegularize_h2186f3a2_0_130
  signal :__VdfgRegularize_h2186f3a2_0_131
  signal :__VdfgRegularize_h2186f3a2_0_132
  signal :__VdfgRegularize_h2186f3a2_0_133
  signal :__VdfgRegularize_h2186f3a2_0_134
  signal :__VdfgRegularize_h2186f3a2_0_135
  signal :__VdfgRegularize_h2186f3a2_0_136
  signal :__VdfgRegularize_h2186f3a2_0_137
  signal :__VdfgRegularize_h2186f3a2_0_138
  signal :__VdfgRegularize_h2186f3a2_0_139
  signal :__VdfgRegularize_h2186f3a2_0_14
  signal :__VdfgRegularize_h2186f3a2_0_140
  signal :__VdfgRegularize_h2186f3a2_0_141
  signal :__VdfgRegularize_h2186f3a2_0_142
  signal :__VdfgRegularize_h2186f3a2_0_143
  signal :__VdfgRegularize_h2186f3a2_0_144
  signal :__VdfgRegularize_h2186f3a2_0_145
  signal :__VdfgRegularize_h2186f3a2_0_146
  signal :__VdfgRegularize_h2186f3a2_0_147
  signal :__VdfgRegularize_h2186f3a2_0_148
  signal :__VdfgRegularize_h2186f3a2_0_149
  signal :__VdfgRegularize_h2186f3a2_0_15
  signal :__VdfgRegularize_h2186f3a2_0_150
  signal :__VdfgRegularize_h2186f3a2_0_151
  signal :__VdfgRegularize_h2186f3a2_0_152
  signal :__VdfgRegularize_h2186f3a2_0_153
  signal :__VdfgRegularize_h2186f3a2_0_154
  signal :__VdfgRegularize_h2186f3a2_0_155
  signal :__VdfgRegularize_h2186f3a2_0_156
  signal :__VdfgRegularize_h2186f3a2_0_157
  signal :__VdfgRegularize_h2186f3a2_0_158
  signal :__VdfgRegularize_h2186f3a2_0_159
  signal :__VdfgRegularize_h2186f3a2_0_16, width: 8
  signal :__VdfgRegularize_h2186f3a2_0_160
  signal :__VdfgRegularize_h2186f3a2_0_161
  signal :__VdfgRegularize_h2186f3a2_0_162
  signal :__VdfgRegularize_h2186f3a2_0_163
  signal :__VdfgRegularize_h2186f3a2_0_17
  signal :__VdfgRegularize_h2186f3a2_0_18
  signal :__VdfgRegularize_h2186f3a2_0_19
  signal :__VdfgRegularize_h2186f3a2_0_2
  signal :__VdfgRegularize_h2186f3a2_0_20
  signal :__VdfgRegularize_h2186f3a2_0_21
  signal :__VdfgRegularize_h2186f3a2_0_22
  signal :__VdfgRegularize_h2186f3a2_0_23
  signal :__VdfgRegularize_h2186f3a2_0_24
  signal :__VdfgRegularize_h2186f3a2_0_25
  signal :__VdfgRegularize_h2186f3a2_0_26
  signal :__VdfgRegularize_h2186f3a2_0_27
  signal :__VdfgRegularize_h2186f3a2_0_28
  signal :__VdfgRegularize_h2186f3a2_0_29
  signal :__VdfgRegularize_h2186f3a2_0_3
  signal :__VdfgRegularize_h2186f3a2_0_30
  signal :__VdfgRegularize_h2186f3a2_0_31
  signal :__VdfgRegularize_h2186f3a2_0_32
  signal :__VdfgRegularize_h2186f3a2_0_33
  signal :__VdfgRegularize_h2186f3a2_0_34
  signal :__VdfgRegularize_h2186f3a2_0_35
  signal :__VdfgRegularize_h2186f3a2_0_36
  signal :__VdfgRegularize_h2186f3a2_0_37
  signal :__VdfgRegularize_h2186f3a2_0_38
  signal :__VdfgRegularize_h2186f3a2_0_39
  signal :__VdfgRegularize_h2186f3a2_0_4
  signal :__VdfgRegularize_h2186f3a2_0_40
  signal :__VdfgRegularize_h2186f3a2_0_41
  signal :__VdfgRegularize_h2186f3a2_0_42
  signal :__VdfgRegularize_h2186f3a2_0_43
  signal :__VdfgRegularize_h2186f3a2_0_44
  signal :__VdfgRegularize_h2186f3a2_0_45
  signal :__VdfgRegularize_h2186f3a2_0_46
  signal :__VdfgRegularize_h2186f3a2_0_47
  signal :__VdfgRegularize_h2186f3a2_0_48
  signal :__VdfgRegularize_h2186f3a2_0_49
  signal :__VdfgRegularize_h2186f3a2_0_5
  signal :__VdfgRegularize_h2186f3a2_0_50
  signal :__VdfgRegularize_h2186f3a2_0_51
  signal :__VdfgRegularize_h2186f3a2_0_52
  signal :__VdfgRegularize_h2186f3a2_0_53
  signal :__VdfgRegularize_h2186f3a2_0_54
  signal :__VdfgRegularize_h2186f3a2_0_55
  signal :__VdfgRegularize_h2186f3a2_0_56
  signal :__VdfgRegularize_h2186f3a2_0_57
  signal :__VdfgRegularize_h2186f3a2_0_58
  signal :__VdfgRegularize_h2186f3a2_0_59
  signal :__VdfgRegularize_h2186f3a2_0_6
  signal :__VdfgRegularize_h2186f3a2_0_60
  signal :__VdfgRegularize_h2186f3a2_0_61
  signal :__VdfgRegularize_h2186f3a2_0_62
  signal :__VdfgRegularize_h2186f3a2_0_63
  signal :__VdfgRegularize_h2186f3a2_0_64
  signal :__VdfgRegularize_h2186f3a2_0_65
  signal :__VdfgRegularize_h2186f3a2_0_66
  signal :__VdfgRegularize_h2186f3a2_0_67
  signal :__VdfgRegularize_h2186f3a2_0_68
  signal :__VdfgRegularize_h2186f3a2_0_69
  signal :__VdfgRegularize_h2186f3a2_0_7
  signal :__VdfgRegularize_h2186f3a2_0_70
  signal :__VdfgRegularize_h2186f3a2_0_71
  signal :__VdfgRegularize_h2186f3a2_0_72
  signal :__VdfgRegularize_h2186f3a2_0_73
  signal :__VdfgRegularize_h2186f3a2_0_74
  signal :__VdfgRegularize_h2186f3a2_0_75
  signal :__VdfgRegularize_h2186f3a2_0_76
  signal :__VdfgRegularize_h2186f3a2_0_77
  signal :__VdfgRegularize_h2186f3a2_0_78
  signal :__VdfgRegularize_h2186f3a2_0_79
  signal :__VdfgRegularize_h2186f3a2_0_8
  signal :__VdfgRegularize_h2186f3a2_0_80
  signal :__VdfgRegularize_h2186f3a2_0_81
  signal :__VdfgRegularize_h2186f3a2_0_82
  signal :__VdfgRegularize_h2186f3a2_0_83
  signal :__VdfgRegularize_h2186f3a2_0_84
  signal :__VdfgRegularize_h2186f3a2_0_85
  signal :__VdfgRegularize_h2186f3a2_0_86
  signal :__VdfgRegularize_h2186f3a2_0_87
  signal :__VdfgRegularize_h2186f3a2_0_88
  signal :__VdfgRegularize_h2186f3a2_0_89
  signal :__VdfgRegularize_h2186f3a2_0_9
  signal :__VdfgRegularize_h2186f3a2_0_90
  signal :__VdfgRegularize_h2186f3a2_0_91
  signal :__VdfgRegularize_h2186f3a2_0_92
  signal :__VdfgRegularize_h2186f3a2_0_93
  signal :__VdfgRegularize_h2186f3a2_0_94
  signal :__VdfgRegularize_h2186f3a2_0_95
  signal :__VdfgRegularize_h2186f3a2_0_96
  signal :__VdfgRegularize_h2186f3a2_0_97, width: 7
  signal :__VdfgRegularize_h2186f3a2_0_98
  signal :__VdfgRegularize_h2186f3a2_0_99
  signal :_unused_ok
  signal :cond_0
  signal :cond_1
  signal :cond_10
  signal :cond_100
  signal :cond_102
  signal :cond_103
  signal :cond_104
  signal :cond_105
  signal :cond_106
  signal :cond_107
  signal :cond_108
  signal :cond_109
  signal :cond_11
  signal :cond_110
  signal :cond_111
  signal :cond_113
  signal :cond_114
  signal :cond_115
  signal :cond_116
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
  signal :cond_126
  signal :cond_127
  signal :cond_128
  signal :cond_129
  signal :cond_13
  signal :cond_130
  signal :cond_131
  signal :cond_132
  signal :cond_133
  signal :cond_134
  signal :cond_135
  signal :cond_136
  signal :cond_137
  signal :cond_138
  signal :cond_139
  signal :cond_14
  signal :cond_140
  signal :cond_141
  signal :cond_142
  signal :cond_143
  signal :cond_15
  signal :cond_16
  signal :cond_17
  signal :cond_2
  signal :cond_20
  signal :cond_21
  signal :cond_22
  signal :cond_23
  signal :cond_24
  signal :cond_25
  signal :cond_26
  signal :cond_27
  signal :cond_28
  signal :cond_29
  signal :cond_3
  signal :cond_30
  signal :cond_31
  signal :cond_32
  signal :cond_33
  signal :cond_34
  signal :cond_35
  signal :cond_36
  signal :cond_37
  signal :cond_38
  signal :cond_39
  signal :cond_40
  signal :cond_41
  signal :cond_42
  signal :cond_43
  signal :cond_44
  signal :cond_45
  signal :cond_46
  signal :cond_47
  signal :cond_48
  signal :cond_49
  signal :cond_5
  signal :cond_50
  signal :cond_51
  signal :cond_52
  signal :cond_53
  signal :cond_54
  signal :cond_55
  signal :cond_56
  signal :cond_57
  signal :cond_58
  signal :cond_59
  signal :cond_6
  signal :cond_60
  signal :cond_61
  signal :cond_62
  signal :cond_63
  signal :cond_64
  signal :cond_65
  signal :cond_66
  signal :cond_67
  signal :cond_68
  signal :cond_69
  signal :cond_7
  signal :cond_70
  signal :cond_71
  signal :cond_72
  signal :cond_73
  signal :cond_74
  signal :cond_75
  signal :cond_76
  signal :cond_77
  signal :cond_78
  signal :cond_79
  signal :cond_8
  signal :cond_80
  signal :cond_81
  signal :cond_82
  signal :cond_83
  signal :cond_84
  signal :cond_85
  signal :cond_86
  signal :cond_87
  signal :cond_88
  signal :cond_89
  signal :cond_9
  signal :cond_90
  signal :cond_91
  signal :cond_92
  signal :cond_93
  signal :cond_94
  signal :cond_95
  signal :cond_96
  signal :cond_97
  signal :cond_98
  signal :cond_99

  # Assignments

  assign :dec_exception_ud,
    (
        (
            (
                sig(:dec_ready_modregrm_one, width: 1) &
                (
                    (
                        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[143] &
                        sig(:__VdfgRegularize_h2186f3a2_0_0, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[254] &
                            (
                                lit(0, width: 2, base: "h", signed: false) !=
                                sig(:decoder, width: 96)[13..12]
                            )
                        ) |
                        (
                            (
                                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[255] &
                                sig(:__VdfgRegularize_h2186f3a2_0_1, width: 1)
                            ) |
                            sig(:__VdfgRegularize_h2186f3a2_0_2, width: 1)
                        )
                    )
                )
            ) |
            (
                sig(:dec_ready_2byte_modregrm, width: 1) &
                (
                    (
                        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[0] &
                        (
                            lit(3, width: 2, base: "h", signed: false) ==
                            sig(:decoder, width: 96)[13..12]
                        )
                    ) |
                    (
                        (
                            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[1] &
                            sig(:__VdfgRegularize_h2186f3a2_0_3, width: 1)
                        ) |
                        (
                            (
                              ~sig(:decoder, width: 96)[13]
                            ) &
                            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[186]
                        )
                    )
                )
            )
        ) |
        (
            (
                (
                    sig(:dec_ready_modregrm_imm, width: 1) &
                    sig(:__VdfgRegularize_h2186f3a2_0_2, width: 1)
                ) |
                (
                    sig(:dec_ready_2byte_one, width: 1) &
                    (
                        sig(:__VdfgRegularize_h2186f3a2_0_162, width: 1) |
                        (
                            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[170] |
                            (
                                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[174] |
                                (
                                    (
                                        lit(92, width: 7, base: "h", signed: false) ==
                                        sig(:decoder, width: 96)[7..1]
                                    ) |
                                    (
                                        (
                                            (
                                                lit(12, width: 4, base: "h", signed: false) ==
                                                sig(:decoder, width: 96)[7..4]
                                            ) &
                                            (
                                                sig(:cond_118, width: 1) &
                                                (
                                                    lit(0, width: 2, base: "h", signed: false) !=
                                                    sig(:decoder, width: 96)[2..1]
                                                )
                                            )
                                        ) |
                                        (
                                            (
                                                lit(13, width: 4, base: "h", signed: false) <=
                                                sig(:decoder, width: 96)[7..4]
                                            ) |
                                            (
                                                (
                                                    (
                                                        lit(3, width: 4, base: "h", signed: false) <=
                                                        sig(:decoder, width: 96)[7..4]
                                                    ) &
                                                    (
                                                        lit(7, width: 4, base: "h", signed: false) >=
                                                        sig(:decoder, width: 96)[7..4]
                                                    )
                                                ) |
                                                (
                                                    (
                                                        lit(1, width: 4, base: "h", signed: false) ==
                                                        sig(:decoder, width: 96)[7..4]
                                                    ) |
                                                    (
                                                        (
                                                            (
                                                                lit(2, width: 4, base: "h", signed: false) ==
                                                                sig(:decoder, width: 96)[7..4]
                                                            ) &
                                                            (
                                                                lit(4, width: 4, base: "h", signed: false) <=
                                                                sig(:decoder, width: 96)[3..0]
                                                            )
                                                        ) |
                                                        (
                                                            (
                                                                lit(2, width: 7, base: "h", signed: false) ==
                                                                sig(:decoder, width: 96)[7..1]
                                                            ) |
                                                            (
                                                                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[7] |
                                                                (
                                                                    (
                                                                        lit(0, width: 4, base: "h", signed: false) ==
                                                                        sig(:decoder, width: 96)[7..4]
                                                                    ) &
                                                                    (
                                                                        lit(10, width: 4, base: "h", signed: false) <=
                                                                        sig(:decoder, width: 96)[3..0]
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            ) |
            (
                (
                    sig(:cond_0, width: 1) &
                    sig(:cond_1, width: 1)
                ) |
                (
                    (
                        sig(:cond_3, width: 1) &
                        sig(:prefix_group_1_lock, width: 1)
                    ) |
                    (
                        (
                            sig(:cond_5, width: 1) &
                            sig(:prefix_group_1_lock, width: 1)
                        ) |
                        (
                            (
                                sig(:cond_7, width: 1) &
                                sig(:cond_8, width: 1)
                            ) |
                            (
                                (
                                    sig(:cond_10, width: 1) &
                                    sig(:prefix_group_1_lock, width: 1)
                                ) |
                                (
                                    (
                                        sig(:cond_11, width: 1) &
                                        sig(:cond_12, width: 1)
                                    ) |
                                    (
                                        (
                                            sig(:cond_13, width: 1) &
                                            sig(:cond_14, width: 1)
                                        ) |
                                        (
                                            (
                                                sig(:cond_15, width: 1) &
                                                sig(:cond_14, width: 1)
                                            ) |
                                            (
                                                (
                                                    sig(:cond_16, width: 1) &
                                                    sig(:cond_1, width: 1)
                                                ) |
                                                (
                                                    (
                                                        sig(:cond_17, width: 1) &
                                                        sig(:prefix_group_1_lock, width: 1)
                                                    ) |
                                                    (
                                                        (
                                                            sig(:cond_20, width: 1) &
                                                            sig(:prefix_group_1_lock, width: 1)
                                                        ) |
                                                        (
                                                            (
                                                                sig(:cond_21, width: 1) &
                                                                sig(:cond_22, width: 1)
                                                            ) |
                                                            (
                                                                (
                                                                    sig(:cond_23, width: 1) &
                                                                    sig(:prefix_group_1_lock, width: 1)
                                                                ) |
                                                                (
                                                                    (
                                                                        sig(:cond_24, width: 1) &
                                                                        sig(:prefix_group_1_lock, width: 1)
                                                                    ) |
                                                                    (
                                                                        (
                                                                            sig(:cond_26, width: 1) &
                                                                            sig(:prefix_group_1_lock, width: 1)
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:cond_27, width: 1) &
                                                                                sig(:cond_1, width: 1)
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    sig(:cond_28, width: 1) &
                                                                                    sig(:prefix_group_1_lock, width: 1)
                                                                                ) |
                                                                                (
                                                                                    (
                                                                                        sig(:cond_29, width: 1) &
                                                                                        sig(:cond_14, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        (
                                                                                            sig(:cond_30, width: 1) &
                                                                                            sig(:prefix_group_1_lock, width: 1)
                                                                                        ) |
                                                                                        (
                                                                                            (
                                                                                                sig(:cond_31, width: 1) &
                                                                                                sig(:cond_22, width: 1)
                                                                                            ) |
                                                                                            (
                                                                                                (
                                                                                                    sig(:cond_32, width: 1) &
                                                                                                    sig(:cond_33, width: 1)
                                                                                                ) |
                                                                                                (
                                                                                                    (
                                                                                                        sig(:cond_34, width: 1) &
                                                                                                        sig(:cond_14, width: 1)
                                                                                                    ) |
                                                                                                    (
                                                                                                        (
                                                                                                            sig(:cond_35, width: 1) &
                                                                                                            sig(:cond_14, width: 1)
                                                                                                        ) |
                                                                                                        (
                                                                                                            (
                                                                                                                sig(:cond_36, width: 1) &
                                                                                                                sig(:prefix_group_1_lock, width: 1)
                                                                                                            ) |
                                                                                                            (
                                                                                                                (
                                                                                                                    sig(:cond_37, width: 1) &
                                                                                                                    sig(:prefix_group_1_lock, width: 1)
                                                                                                                ) |
                                                                                                                (
                                                                                                                    (
                                                                                                                        sig(:cond_38, width: 1) &
                                                                                                                        sig(:prefix_group_1_lock, width: 1)
                                                                                                                    ) |
                                                                                                                    (
                                                                                                                        (
                                                                                                                            sig(:cond_39, width: 1) &
                                                                                                                            sig(:prefix_group_1_lock, width: 1)
                                                                                                                        ) |
                                                                                                                        (
                                                                                                                            (
                                                                                                                                sig(:cond_40, width: 1) &
                                                                                                                                sig(:prefix_group_1_lock, width: 1)
                                                                                                                            ) |
                                                                                                                            (
                                                                                                                                (
                                                                                                                                    sig(:cond_41, width: 1) &
                                                                                                                                    sig(:prefix_group_1_lock, width: 1)
                                                                                                                                ) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:cond_42, width: 1) &
                                                                                                                                        sig(:prefix_group_1_lock, width: 1)
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:cond_43, width: 1) &
                                                                                                                                            sig(:prefix_group_1_lock, width: 1)
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            (
                                                                                                                                                sig(:cond_44, width: 1) &
                                                                                                                                                sig(:prefix_group_1_lock, width: 1)
                                                                                                                                            ) |
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    sig(:cond_45, width: 1) &
                                                                                                                                                    sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                ) |
                                                                                                                                                (
                                                                                                                                                    (
                                                                                                                                                        sig(:cond_46, width: 1) &
                                                                                                                                                        sig(:cond_1, width: 1)
                                                                                                                                                    ) |
                                                                                                                                                    (
                                                                                                                                                        (
                                                                                                                                                            sig(:cond_47, width: 1) &
                                                                                                                                                            sig(:cond_1, width: 1)
                                                                                                                                                        ) |
                                                                                                                                                        (
                                                                                                                                                            (
                                                                                                                                                                sig(:cond_48, width: 1) &
                                                                                                                                                                sig(:cond_1, width: 1)
                                                                                                                                                            ) |
                                                                                                                                                            (
                                                                                                                                                                (
                                                                                                                                                                    sig(:cond_49, width: 1) &
                                                                                                                                                                    sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                ) |
                                                                                                                                                                (
                                                                                                                                                                    (
                                                                                                                                                                        sig(:cond_51, width: 1) &
                                                                                                                                                                        sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                    ) |
                                                                                                                                                                    (
                                                                                                                                                                        (
                                                                                                                                                                            sig(:cond_52, width: 1) &
                                                                                                                                                                            sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                        ) |
                                                                                                                                                                        (
                                                                                                                                                                            (
                                                                                                                                                                                sig(:cond_53, width: 1) &
                                                                                                                                                                                sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                            ) |
                                                                                                                                                                            (
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:cond_54, width: 1) &
                                                                                                                                                                                    sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                                ) |
                                                                                                                                                                                (
                                                                                                                                                                                    (
                                                                                                                                                                                        sig(:cond_55, width: 1) &
                                                                                                                                                                                        sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                                    ) |
                                                                                                                                                                                    (
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:cond_57, width: 1) &
                                                                                                                                                                                            sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                                        ) |
                                                                                                                                                                                        (
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:cond_58, width: 1) &
                                                                                                                                                                                                sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                                            ) |
                                                                                                                                                                                            (
                                                                                                                                                                                                (
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :cond_59,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ) &
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :prefix_group_1_lock,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    )
                                                                                                                                                                                                ) |
                                                                                                                                                                                                (
                                                                                                                                                                                                    (
                                                                                                                                                                                                      sig(:cond_60, width: 1) &
                                                                                                                                                                                                      sig(:prefix_group_1_lock, width: 1)
                                                                                                                                                                                                    ) |
                                                                                                                                                                                                    (
                                                                                                                                                                                                      (sig(:cond_61, width: 1) & sig(:cond_62, width: 1)) |
                                                                                                                                                                                                      ((sig(:cond_63, width: 1) & sig(:cond_22, width: 1)) | ((sig(:cond_64, width: 1) & sig(:cond_22, width: 1)) | ((sig(:cond_65, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_66, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_67, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_68, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_69, width: 1) & sig(:cond_1, width: 1)) | ((sig(:cond_70, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_71, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_72, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_73, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_74, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_76, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_77, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_78, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_79, width: 1) & sig(:cond_80, width: 1)) | ((sig(:cond_81, width: 1) & sig(:cond_82, width: 1)) | ((sig(:cond_83, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_84, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_85, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_86, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_87, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_88, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_89, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_90, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_91, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_92, width: 1) & sig(:cond_1, width: 1)) | ((sig(:cond_93, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_94, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_95, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_96, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_98, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_99, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_102, width: 1) & sig(:cond_1, width: 1)) | ((sig(:cond_103, width: 1) & sig(:cond_14, width: 1)) | ((sig(:cond_104, width: 1) & sig(:cond_14, width: 1)) | ((sig(:cond_105, width: 1) & sig(:cond_14, width: 1)) | ((sig(:cond_106, width: 1) & sig(:cond_14, width: 1)) | ((sig(:cond_107, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_108, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_109, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_110, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_111, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_113, width: 1) & sig(:cond_114, width: 1)) | ((sig(:cond_115, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_116, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_117, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_119, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_120, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_121, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_122, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_123, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_124, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_125, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_126, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_127, width: 1) & sig(:cond_22, width: 1)) | ((sig(:cond_128, width: 1) & sig(:prefix_group_1_lock, width: 1)) | ((sig(:cond_129, width: 1) & sig(:cond_22, width: 1)) | ((sig(:cond_130, width: 1) & sig(:cond_22, width: 1)) | ((sig(:cond_131, width: 1) & sig(:cond_22, width: 1)) | ((sig(:cond_132, width: 1) | (sig(:cond_133, width: 1) | (sig(:cond_134, width: 1) | (sig(:cond_135, width: 1) | (sig(:cond_136, width: 1) | (sig(:cond_137, width: 1) | (sig(:cond_138, width: 1) | (sig(:cond_139, width: 1) | (sig(:cond_140, width: 1) | (sig(:cond_141, width: 1) | (sig(:cond_142, width: 1) | sig(:cond_143, width: 1)))))))))))) & sig(:prefix_group_1_lock, width: 1))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                )
                                                                                                                                                                                            )
                                                                                                                                                                                        )
                                                                                                                                                                                    )
                                                                                                                                                                                )
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    )
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h2186f3a2_0_0,
    (
        lit(0, width: 3, base: "h", signed: false) !=
        sig(:decoder, width: 96)[13..11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_1,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_2,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_163, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_0, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_3,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_162,
    (
        lit(83, width: 7, base: "h", signed: false) ==
        sig(:decoder, width: 96)[7..1]
    )
  assign :cond_118,
    (
      ~sig(:cond_100, width: 1)
    )
  assign :cond_0,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_161, width: 1)
    )
  assign :cond_1,
    (
        sig(:prefix_group_1_lock, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_4, width: 1)
    )
  assign :cond_3,
    (
        sig(:dec_ready_one_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[227]
    )
  assign :cond_5,
    (
        sig(:dec_ready_call_jmp_imm, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[154] |
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[232]
        )
    )
  assign :cond_7,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_5, width: 1) &
        (
            sig(:__VdfgRegularize_h2186f3a2_0_6, width: 1) |
            sig(:__VdfgRegularize_h2186f3a2_0_7, width: 1)
        )
    )
  assign :cond_8,
    (
        sig(:prefix_group_1_lock, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_7, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_4, width: 1)
        )
    )
  assign :cond_10,
    (
        (
            sig(:dec_ready_one, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[6] |
                (
                    sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[22] |
                    (
                        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[14] |
                        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[30]
                    )
                )
            )
        ) |
        (
            sig(:dec_ready_2byte_one, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[160] |
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[168]
            )
        )
    )
  assign :cond_11,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[140]
    )
  assign :cond_12,
    (
        sig(:prefix_group_1_lock, width: 1) |
        (
            lit(6, width: 3, base: "h", signed: false) <=
            sig(:decoder, width: 96)[13..11]
        )
    )
  assign :cond_13,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_8, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_9, width: 1)
    )
  assign :cond_14,
    (
        sig(:cond_50, width: 1) |
        sig(:prefix_group_1_lock, width: 1)
    )
  assign :cond_15,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_8, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_10, width: 1)
    )
  assign :cond_16,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_11, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_7, width: 1)
    )
  assign :cond_17,
    (
        (
            sig(:dec_ready_one_one, width: 1) &
            (
                lit(7, width: 4, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..4]
            )
        ) |
        (
            sig(:dec_ready_2byte_imm, width: 1) &
            (
                lit(8, width: 4, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..4]
            )
        )
    )
  assign :cond_20,
    (
        sig(:dec_ready_2byte_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[8]
    )
  assign :cond_21,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_12, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_1, width: 1)
    )
  assign :cond_22,
    (
        sig(:prefix_group_1_lock, width: 1) |
        sig(:__VdfgRegularize_h2186f3a2_0_4, width: 1)
    )
  assign :cond_23,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[244]
    )
  assign :cond_24,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(87, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_26,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(4, width: 4, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..4]
        )
    )
  assign :cond_27,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            (
                lit(127, width: 7, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..1]
            ) &
            sig(:__VdfgRegularize_h2186f3a2_0_159, width: 1)
        )
    )
  assign :cond_28,
    (
        (
            sig(:dec_ready_one, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[195]
        ) |
        (
            sig(:dec_ready_one_two, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[194]
        )
    )
  assign :cond_29,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[99]
    )
  assign :cond_30,
    (
        sig(:dec_ready_2byte_one, width: 1) &
        (
            lit(25, width: 5, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..3]
        )
    )
  assign :cond_31,
    (
        (
            sig(:dec_ready_modregrm_one, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[196] |
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[197]
            )
        ) |
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[178] |
                (
                    sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[180] |
                    sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[181]
                )
            )
        )
    )
  assign :cond_32,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[142]
    )
  assign :cond_33,
    (
        sig(:cond_12, width: 1) |
        sig(:__VdfgRegularize_h2186f3a2_0_10, width: 1)
    )
  assign :cond_34,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_8, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_6, width: 1)
    )
  assign :cond_35,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_8, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_7, width: 1)
    )
  assign :cond_36,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[248]
    )
  assign :cond_37,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[252]
    )
  assign :cond_38,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[245]
    )
  assign :cond_39,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[249]
    )
  assign :cond_40,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[253]
    )
  assign :cond_41,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[158]
    )
  assign :cond_42,
    (
        sig(:dec_ready_one_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[213]
    )
  assign :cond_43,
    (
        sig(:dec_ready_one_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[212]
    )
  assign :cond_44,
    (
        (
            sig(:dec_ready_one, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[7] |
                (
                    sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[23] |
                    sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[31]
                )
            )
        ) |
        (
            sig(:dec_ready_2byte_one, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[161] |
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[169]
            )
        )
    )
  assign :cond_45,
    (
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[163]
        ) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_13, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_14, width: 1)
        )
    )
  assign :cond_46,
    (
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[179]
        ) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_13, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_15, width: 1)
        )
    )
  assign :cond_47,
    (
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[171]
        ) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_13, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_3, width: 1)
        )
    )
  assign :cond_48,
    (
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[187]
        ) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_13, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_1, width: 1)
        )
    )
  assign :cond_49,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[207]
    )
  assign :cond_51,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(11, width: 5, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..3]
        )
    )
  assign :cond_52,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[143] &
            sig(:__VdfgRegularize_h2186f3a2_0_9, width: 1)
        )
    )
  assign :cond_53,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_11, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_15, width: 1)
    )
  assign :cond_54,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_11, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_1, width: 1)
    )
  assign :cond_55,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            lit(52, width: 6, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..2]
        )
    )
  assign :cond_57,
    (
        sig(:dec_ready_modregrm_imm, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_161, width: 1)
    )
  assign :cond_58,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_162, width: 1)
    )
  assign :cond_59,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_12, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_14, width: 1)
    )
  assign :cond_60,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_12, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_15, width: 1)
    )
  assign :cond_61,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        (
            lit(32, width: 8, base: "h", signed: false) ==
            sig(:__VdfgRegularize_h2186f3a2_0_16, width: 8)
        )
    )
  assign :cond_62,
    (
        sig(:prefix_group_1_lock, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_0, width: 1) &
            (
                (
                    lit(2, width: 3, base: "h", signed: false) !=
                    sig(:decoder, width: 96)[13..11]
                ) &
                (
                    lit(3, width: 3, base: "h", signed: false) !=
                    sig(:decoder, width: 96)[13..11]
                )
            )
        )
    )
  assign :cond_63,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_12, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_6, width: 1)
    )
  assign :cond_64,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_12, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_7, width: 1)
    )
  assign :cond_65,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[96]
    )
  assign :cond_66,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[155]
    )
  assign :cond_67,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            lit(27, width: 5, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..3]
        )
    )
  assign :cond_68,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        (
            lit(9, width: 4, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..4]
        )
    )
  assign :cond_69,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        (
            lit(88, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_70,
    (
        sig(:dec_ready_one_three, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[200]
    )
  assign :cond_71,
    (
        (
            sig(:dec_ready_modregrm_one, width: 1) &
            (
                sig(:__VdfgRegularize_h2186f3a2_0_160, width: 1) &
                sig(:__VdfgRegularize_h2186f3a2_0_3, width: 1)
            )
        ) |
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[175]
        )
    )
  assign :cond_72,
    (
        sig(:dec_ready_modregrm_imm, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[105] |
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[107]
        )
    )
  assign :cond_73,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[201]
    )
  assign :cond_74,
    (
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[165]
        ) |
        (
            sig(:dec_ready_2byte_modregrm_imm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[164]
        )
    )
  assign :cond_76,
    (
        (
            sig(:dec_ready_2byte_modregrm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[173]
        ) |
        (
            sig(:dec_ready_2byte_modregrm_imm, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[172]
        )
    )
  assign :cond_77,
    (
        sig(:dec_ready_2byte_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[9]
    )
  assign :cond_78,
    (
        sig(:dec_ready_one_imm, width: 1) &
        (
            sig(:__VdfgRegularize_h2186f3a2_0_17, width: 1) &
            (
                lit(2, width: 2, base: "h", signed: false) ==
                sig(:decoder, width: 96)[2..1]
            )
        )
    )
  assign :cond_79,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            (
              ~sig(:decoder, width: 96)[2]
            ) &
            sig(:__VdfgRegularize_h2186f3a2_0_17, width: 1)
        )
    )
  assign :cond_80,
    (
        sig(:prefix_group_1_lock, width: 1) &
        (
            sig(:cond_56, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_4, width: 1) |
                (
                    lit(7, width: 3, base: "h", signed: false) ==
                    sig(:decoder, width: 96)[5..3]
                )
            )
        )
    )
  assign :cond_81,
    (
        sig(:dec_ready_modregrm_imm, width: 1) &
        (
            lit(32, width: 6, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..2]
        )
    )
  assign :cond_82,
    (
        sig(:prefix_group_1_lock, width: 1) &
        (
            sig(:__VdfgRegularize_h2186f3a2_0_1, width: 1) |
            sig(:__VdfgRegularize_h2186f3a2_0_4, width: 1)
        )
    )
  assign :cond_83,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_11, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_14, width: 1)
    )
  assign :cond_84,
    (
        sig(:dec_ready_one_one, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[224] |
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[225] |
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[226]
            )
        )
    )
  assign :cond_85,
    (
        sig(:dec_ready_one_imm, width: 1) &
        (
            lit(84, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_86,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            lit(66, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_87,
    (
        sig(:dec_ready_modregrm_imm, width: 1) &
        (
            sig(:__VdfgRegularize_h2186f3a2_0_160, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_159, width: 1)
        )
    )
  assign :cond_88,
    (
        sig(:dec_ready_2byte_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[6]
    )
  assign :cond_89,
    (
        (
            sig(:dec_ready_one, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[203]
        ) |
        (
            sig(:dec_ready_one_two, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[202]
        )
    )
  assign :cond_90,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(86, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_91,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(18, width: 5, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..3]
        )
    )
  assign :cond_92,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            lit(67, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_93,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(10, width: 5, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..3]
        )
    )
  assign :cond_94,
    (
        sig(:dec_ready_one_imm, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[106] |
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[104]
        )
    )
  assign :cond_95,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_5, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_15, width: 1)
    )
  assign :cond_96,
    (
        (
            sig(:dec_ready_one, width: 1) &
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[204] |
                (
                    sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[206] |
                    sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[241]
                )
            )
        ) |
        (
            sig(:dec_ready_one_one, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[205]
        )
    )
  assign :cond_98,
    (
        sig(:dec_ready_2byte_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[162]
    )
  assign :cond_99,
    (
        (
            sig(:dec_ready_one, width: 1) &
            (
                lit(118, width: 7, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..1]
            )
        ) |
        (
            sig(:dec_ready_one_one, width: 1) &
            (
                lit(114, width: 7, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..1]
            )
        )
    )
  assign :cond_102,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_11, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_6, width: 1)
    )
  assign :cond_103,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_8, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_14, width: 1)
    )
  assign :cond_104,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_8, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_3, width: 1)
    )
  assign :cond_105,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[2]
    )
  assign :cond_106,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[3]
    )
  assign :cond_107,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(85, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_108,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(54, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_109,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(55, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_110,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[156]
    )
  assign :cond_111,
    (
        sig(:dec_ready_call_jmp_imm, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[234] |
            (
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[233] |
                sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[235]
            )
        )
    )
  assign :cond_113,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_5, width: 1) &
        (
            sig(:__VdfgRegularize_h2186f3a2_0_14, width: 1) |
            sig(:__VdfgRegularize_h2186f3a2_0_3, width: 1)
        )
    )
  assign :cond_114,
    (
        sig(:prefix_group_1_lock, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_3, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_4, width: 1)
        )
    )
  assign :cond_115,
    (
        (
            sig(:dec_ready_one, width: 1) &
            (
                lit(119, width: 7, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..1]
            )
        ) |
        (
            sig(:dec_ready_one_one, width: 1) &
            (
                lit(115, width: 7, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..1]
            )
        )
    )
  assign :cond_116,
    (
        sig(:dec_ready_mem_offset, width: 1) &
        (
            lit(40, width: 6, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..2]
        )
    )
  assign :cond_117,
    (
        sig(:dec_ready_one_imm, width: 1) &
        (
            lit(11, width: 4, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..4]
        )
    )
  assign :cond_119,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        (
            lit(34, width: 6, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..2]
        )
    )
  assign :cond_120,
    (
        sig(:dec_ready_modregrm_imm, width: 1) &
        (
            sig(:__VdfgRegularize_h2186f3a2_0_163, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_9, width: 1)
        )
    )
  assign :cond_121,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[159]
    )
  assign :cond_122,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[152]
    )
  assign :cond_123,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[153]
    )
  assign :cond_124,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[157]
    )
  assign :cond_125,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[250]
    )
  assign :cond_126,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[251]
    )
  assign :cond_127,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[98]
    )
  assign :cond_128,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[214]
    )
  assign :cond_129,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[141]
    )
  assign :cond_130,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_12, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_9, width: 1)
    )
  assign :cond_131,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_12, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_10, width: 1)
    )
  assign :cond_132,
    (
        sig(:dec_ready_one, width: 1) &
        (
            lit(82, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_133,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        (
            lit(91, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_134,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        (
            lit(95, width: 7, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..1]
        )
    )
  assign :cond_135,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[97]
    )
  assign :cond_136,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        (
            lit(33, width: 8, base: "h", signed: false) ==
            sig(:__VdfgRegularize_h2186f3a2_0_16, width: 8)
        )
    )
  assign :cond_137,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[215]
    )
  assign :cond_138,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[55]
    )
  assign :cond_139,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[63]
    )
  assign :cond_140,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[39]
    )
  assign :cond_141,
    (
        sig(:dec_ready_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[47]
    )
  assign :cond_142,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[188]
    )
  assign :cond_143,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[189]
    )
  assign :__VdfgRegularize_h2186f3a2_0_161,
    (
        lit(96, width: 7, base: "h", signed: false) ==
        sig(:decoder, width: 96)[7..1]
    )
  assign :__VdfgRegularize_h2186f3a2_0_4,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:decoder, width: 96)[15..14]
    )
  assign :cond_2,
    (
      ~sig(:cond_75, width: 1)
    )
  assign :cond_75,
    sig(:decoder, width: 96)[0]
  assign :cond_6,
    (
      ~sig(:cond_56, width: 1)
    )
  assign :cond_56,
    sig(:decoder, width: 96)[1]
  assign :__VdfgRegularize_h2186f3a2_0_5,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[255]
    )
  assign :__VdfgRegularize_h2186f3a2_0_6,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_7,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :cond_9,
    (
      ~sig(:decoder, width: 96)[11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_8,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[0]
    )
  assign :__VdfgRegularize_h2186f3a2_0_9,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :cond_50,
    (
      ~sig(:protected_mode, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_10,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_11,
    (
        sig(:dec_ready_modregrm_one, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_160, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_12,
    (
        sig(:dec_ready_2byte_modregrm, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[1]
    )
  assign :cond_25,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:dec_prefix_group_1_rep, width: 2)
    )
  assign :__VdfgRegularize_h2186f3a2_0_159,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..12]
    )
  assign :__VdfgRegularize_h2186f3a2_0_13,
    (
        sig(:dec_ready_2byte_modregrm_imm, width: 1) &
        sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[186]
    )
  assign :__VdfgRegularize_h2186f3a2_0_14,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_15,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[13..11]
    )
  assign :__VdfgRegularize_h2186f3a2_0_16,
    sig(:decoder, width: 96)[7..2].concat(
      sig(:cond_75, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_160,
    (
        lit(123, width: 7, base: "h", signed: false) ==
        sig(:decoder, width: 96)[7..1]
    )
  assign :__VdfgRegularize_h2186f3a2_0_17,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:decoder, width: 96)[7..6]
    )
  assign :cond_97,
    (
        sig(:cond_75, width: 1) ^
        sig(:decoder, width: 96)[2]
    )
  assign :cond_100,
    sig(:decoder, width: 96)[3]
  assign :__VdfgRegularize_h2186f3a2_0_163,
    (
        lit(99, width: 7, base: "h", signed: false) ==
        sig(:decoder, width: 96)[7..1]
    )
  assign :consume_mem_offset,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_116, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_18,
    (
      ~sig(:prefix_group_1_lock, width: 1)
    )
  assign :dec_cmd,
    mux(
      sig(:__VdfgRegularize_h2186f3a2_0_158, width: 1),
      lit(1, width: 7, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_h2186f3a2_0_157, width: 1),
        lit(2, width: 7, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_h2186f3a2_0_156, width: 1),
          lit(3, width: 7, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_h2186f3a2_0_155, width: 1),
            lit(3, width: 7, base: "h", signed: false),
            mux(
              sig(:__VdfgRegularize_h2186f3a2_0_154, width: 1),
              lit(6, width: 7, base: "h", signed: false),
              mux(
                sig(:__VdfgRegularize_h2186f3a2_0_153, width: 1),
                lit(6, width: 7, base: "h", signed: false),
                mux(
                  sig(:__VdfgRegularize_h2186f3a2_0_152, width: 1),
                  lit(6, width: 7, base: "h", signed: false),
                  mux(
                    sig(:__VdfgRegularize_h2186f3a2_0_151, width: 1),
                    lit(6, width: 7, base: "h", signed: false),
                    mux(
                      sig(:__VdfgRegularize_h2186f3a2_0_150, width: 1),
                      lit(7, width: 7, base: "h", signed: false),
                      mux(
                        sig(:__VdfgRegularize_h2186f3a2_0_149, width: 1),
                        lit(8, width: 7, base: "h", signed: false),
                        mux(
                          sig(:__VdfgRegularize_h2186f3a2_0_148, width: 1),
                          lit(9, width: 7, base: "h", signed: false),
                          mux(
                            sig(:__VdfgRegularize_h2186f3a2_0_147, width: 1),
                            lit(10, width: 7, base: "h", signed: false),
                            mux(
                              sig(:__VdfgRegularize_h2186f3a2_0_146, width: 1),
                              lit(12, width: 7, base: "h", signed: false),
                              mux(
                                sig(:__VdfgRegularize_h2186f3a2_0_145, width: 1),
                                lit(13, width: 7, base: "h", signed: false),
                                mux(
                                  sig(:__VdfgRegularize_h2186f3a2_0_144, width: 1),
                                  lit(14, width: 7, base: "h", signed: false),
                                  mux(
                                    sig(:__VdfgRegularize_h2186f3a2_0_143, width: 1),
                                    lit(14, width: 7, base: "h", signed: false),
                                    mux(
                                      sig(:__VdfgRegularize_h2186f3a2_0_142, width: 1),
                                      lit(15, width: 7, base: "h", signed: false),
                                      mux(
                                        sig(:__VdfgRegularize_h2186f3a2_0_141, width: 1),
                                        lit(16, width: 7, base: "h", signed: false),
                                        mux(
                                          sig(:__VdfgRegularize_h2186f3a2_0_140, width: 1),
                                          lit(17, width: 7, base: "h", signed: false),
                                          mux(
                                            sig(:__VdfgRegularize_h2186f3a2_0_139, width: 1),
                                            lit(18, width: 7, base: "h", signed: false),
                                            mux(
                                              sig(:__VdfgRegularize_h2186f3a2_0_138, width: 1),
                                              lit(19, width: 7, base: "h", signed: false),
                                              mux(
                                                sig(:__VdfgRegularize_h2186f3a2_0_137, width: 1),
                                                lit(20, width: 7, base: "h", signed: false),
                                                mux(
                                                  sig(:__VdfgRegularize_h2186f3a2_0_136, width: 1),
                                                  lit(21, width: 7, base: "h", signed: false),
                                                  mux(
                                                    sig(:__VdfgRegularize_h2186f3a2_0_135, width: 1),
                                                    lit(22, width: 7, base: "h", signed: false),
                                                    mux(
                                                      sig(:__VdfgRegularize_h2186f3a2_0_134, width: 1),
                                                      lit(23, width: 7, base: "h", signed: false),
                                                      mux(
                                                        sig(:__VdfgRegularize_h2186f3a2_0_133, width: 1),
                                                        lit(24, width: 7, base: "h", signed: false),
                                                        mux(
                                                          sig(:__VdfgRegularize_h2186f3a2_0_132, width: 1),
                                                          lit(25, width: 7, base: "h", signed: false),
                                                          mux(
                                                            sig(:__VdfgRegularize_h2186f3a2_0_131, width: 1),
                                                            lit(26, width: 7, base: "h", signed: false),
                                                            mux(
                                                              sig(:__VdfgRegularize_h2186f3a2_0_130, width: 1),
                                                              lit(27, width: 7, base: "h", signed: false),
                                                              mux(
                                                                sig(:__VdfgRegularize_h2186f3a2_0_129, width: 1),
                                                                lit(31, width: 7, base: "h", signed: false),
                                                                mux(
                                                                  sig(:__VdfgRegularize_h2186f3a2_0_128, width: 1),
                                                                  lit(32, width: 7, base: "h", signed: false),
                                                                  mux(
                                                                    sig(:__VdfgRegularize_h2186f3a2_0_127, width: 1),
                                                                    lit(34, width: 7, base: "h", signed: false),
                                                                    mux(
                                                                      sig(:__VdfgRegularize_h2186f3a2_0_126, width: 1),
                                                                      lit(36, width: 7, base: "h", signed: false),
                                                                      mux(
                                                                        sig(:__VdfgRegularize_h2186f3a2_0_125, width: 1),
                                                                        lit(38, width: 7, base: "h", signed: false),
                                                                        mux(
                                                                          sig(:__VdfgRegularize_h2186f3a2_0_124, width: 1),
                                                                          lit(37, width: 7, base: "h", signed: false),
                                                                          mux(
                                                                            sig(:__VdfgRegularize_h2186f3a2_0_123, width: 1),
                                                                            lit(39, width: 7, base: "h", signed: false),
                                                                            mux(
                                                                              sig(:__VdfgRegularize_h2186f3a2_0_122, width: 1),
                                                                              lit(35, width: 7, base: "h", signed: false),
                                                                              mux(
                                                                                sig(:__VdfgRegularize_h2186f3a2_0_121, width: 1),
                                                                                lit(41, width: 7, base: "h", signed: false),
                                                                                mux(
                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_120, width: 1),
                                                                                  lit(41, width: 7, base: "h", signed: false),
                                                                                  mux(
                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_119, width: 1),
                                                                                    lit(42, width: 7, base: "h", signed: false),
                                                                                    mux(
                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_118, width: 1),
                                                                                      lit(43, width: 7, base: "h", signed: false),
                                                                                      mux(
                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_117, width: 1),
                                                                                        lit(44, width: 7, base: "h", signed: false),
                                                                                        mux(
                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_116, width: 1),
                                                                                          lit(44, width: 7, base: "h", signed: false),
                                                                                          mux(
                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_115, width: 1),
                                                                                            lit(45, width: 7, base: "h", signed: false),
                                                                                            mux(
                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_114, width: 1),
                                                                                              lit(46, width: 7, base: "h", signed: false),
                                                                                              mux(
                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_113, width: 1),
                                                                                                lit(46, width: 7, base: "h", signed: false),
                                                                                                mux(
                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_112, width: 1),
                                                                                                  lit(46, width: 7, base: "h", signed: false),
                                                                                                  mux(
                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_111, width: 1),
                                                                                                    lit(47, width: 7, base: "h", signed: false),
                                                                                                    mux(
                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_110, width: 1),
                                                                                                      lit(48, width: 7, base: "h", signed: false),
                                                                                                      mux(
                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_109, width: 1),
                                                                                                        lit(49, width: 7, base: "h", signed: false),
                                                                                                        mux(
                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_108, width: 1),
                                                                                                          lit(50, width: 7, base: "h", signed: false),
                                                                                                          mux(
                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_107, width: 1),
                                                                                                            lit(50, width: 7, base: "h", signed: false),
                                                                                                            mux(
                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_106, width: 1),
                                                                                                              lit(51, width: 7, base: "h", signed: false),
                                                                                                              mux(
                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_105, width: 1),
                                                                                                                lit(52, width: 7, base: "h", signed: false),
                                                                                                                mux(
                                                                                                                  sig(:consume_one_three, width: 1),
                                                                                                                  lit(53, width: 7, base: "h", signed: false),
                                                                                                                  mux(
                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_104, width: 1),
                                                                                                                    lit(54, width: 7, base: "h", signed: false),
                                                                                                                    mux(
                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_103, width: 1),
                                                                                                                      lit(54, width: 7, base: "h", signed: false),
                                                                                                                      mux(
                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_102, width: 1),
                                                                                                                        lit(55, width: 7, base: "h", signed: false),
                                                                                                                        mux(
                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_101, width: 1),
                                                                                                                          lit(56, width: 7, base: "h", signed: false),
                                                                                                                          mux(
                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_100, width: 1),
                                                                                                                            lit(57, width: 7, base: "h", signed: false),
                                                                                                                            mux(
                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_99, width: 1),
                                                                                                                              lit(58, width: 7, base: "h", signed: false),
                                                                                                                              mux(
                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_98, width: 1),
                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_97, width: 7),
                                                                                                                                mux(
                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_96, width: 1),
                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_97, width: 7),
                                                                                                                                  mux(
                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_95, width: 1),
                                                                                                                                    lit(8, width: 4, base: "h", signed: false).concat(
                                                                                                                                      sig(:decoder, width: 96)[13..11]
                                                                                                                                    ),
                                                                                                                                    mux(
                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_94, width: 1),
                                                                                                                                      lit(59, width: 7, base: "h", signed: false),
                                                                                                                                      mux(
                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_93, width: 1),
                                                                                                                                        lit(60, width: 7, base: "h", signed: false),
                                                                                                                                        mux(
                                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_92, width: 1),
                                                                                                                                          lit(61, width: 7, base: "h", signed: false),
                                                                                                                                          mux(
                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_91, width: 1),
                                                                                                                                            lit(61, width: 7, base: "h", signed: false),
                                                                                                                                            mux(
                                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_90, width: 1),
                                                                                                                                              lit(61, width: 7, base: "h", signed: false),
                                                                                                                                              mux(
                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_89, width: 1),
                                                                                                                                                lit(62, width: 7, base: "h", signed: false),
                                                                                                                                                mux(
                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_88, width: 1),
                                                                                                                                                  lit(63, width: 7, base: "h", signed: false),
                                                                                                                                                  mux(
                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_87, width: 1),
                                                                                                                                                    lit(72, width: 7, base: "h", signed: false),
                                                                                                                                                    mux(
                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_86, width: 1),
                                                                                                                                                      lit(73, width: 7, base: "h", signed: false),
                                                                                                                                                      mux(
                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_85, width: 1),
                                                                                                                                                        lit(73, width: 7, base: "h", signed: false),
                                                                                                                                                        mux(
                                                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_84, width: 1),
                                                                                                                                                          lit(74, width: 7, base: "h", signed: false),
                                                                                                                                                          mux(
                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_83, width: 1),
                                                                                                                                                            lit(74, width: 7, base: "h", signed: false),
                                                                                                                                                            mux(
                                                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_82, width: 1),
                                                                                                                                                              lit(74, width: 7, base: "h", signed: false),
                                                                                                                                                              mux(
                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_81, width: 1),
                                                                                                                                                                lit(75, width: 7, base: "h", signed: false),
                                                                                                                                                                mux(
                                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_80, width: 1),
                                                                                                                                                                  lit(76, width: 7, base: "h", signed: false),
                                                                                                                                                                  mux(
                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_79, width: 1),
                                                                                                                                                                    lit(77, width: 7, base: "h", signed: false),
                                                                                                                                                                    mux(
                                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_78, width: 1),
                                                                                                                                                                      lit(78, width: 7, base: "h", signed: false),
                                                                                                                                                                      mux(
                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_77, width: 1),
                                                                                                                                                                        lit(81, width: 7, base: "h", signed: false),
                                                                                                                                                                        mux(
                                                                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_76, width: 1),
                                                                                                                                                                          lit(82, width: 7, base: "h", signed: false),
                                                                                                                                                                          mux(
                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_75, width: 1),
                                                                                                                                                                            lit(79, width: 7, base: "h", signed: false),
                                                                                                                                                                            mux(
                                                                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_74, width: 1),
                                                                                                                                                                              lit(80, width: 7, base: "h", signed: false),
                                                                                                                                                                              mux(
                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_73, width: 1),
                                                                                                                                                                                lit(83, width: 7, base: "h", signed: false),
                                                                                                                                                                                mux(
                                                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_72, width: 1),
                                                                                                                                                                                  lit(84, width: 7, base: "h", signed: false),
                                                                                                                                                                                  mux(
                                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_71, width: 1),
                                                                                                                                                                                    lit(85, width: 7, base: "h", signed: false),
                                                                                                                                                                                    mux(
                                                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_70, width: 1),
                                                                                                                                                                                      lit(86, width: 7, base: "h", signed: false),
                                                                                                                                                                                      mux(
                                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_69, width: 1),
                                                                                                                                                                                        lit(87, width: 7, base: "h", signed: false),
                                                                                                                                                                                        mux(
                                                                                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_68, width: 1),
                                                                                                                                                                                          lit(87, width: 7, base: "h", signed: false),
                                                                                                                                                                                          mux(
                                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_67, width: 1),
                                                                                                                                                                                            lit(89, width: 7, base: "h", signed: false),
                                                                                                                                                                                            mux(
                                                                                                                                                                                              sig(:consume_mem_offset, width: 1),
                                                                                                                                                                                              lit(90, width: 7, base: "h", signed: false),
                                                                                                                                                                                              mux(
                                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_66, width: 1),
                                                                                                                                                                                                lit(90, width: 7, base: "h", signed: false),
                                                                                                                                                                                                mux(
                                                                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_65, width: 1),
                                                                                                                                                                                                  lit(90, width: 7, base: "h", signed: false),
                                                                                                                                                                                                  mux(
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :__VdfgRegularize_h2186f3a2_0_64,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    lit(
                                                                                                                                                                                                      90,
                                                                                                                                                                                                      width: 7,
                                                                                                                                                                                                      base: "h",
                                                                                                                                                                                                      signed: false
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    mux(
                                                                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_63, width: 1),
                                                                                                                                                                                                      lit(91, width: 7, base: "h", signed: false),
                                                                                                                                                                                                      mux(sig(:__VdfgRegularize_h2186f3a2_0_62, width: 1), lit(92, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_61, width: 1), lit(93, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_60, width: 1), lit(94, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_59, width: 1), lit(95, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_58, width: 1), lit(96, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_57, width: 1), lit(97, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_56, width: 1), lit(98, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_55, width: 1), lit(103, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_54, width: 1), lit(104, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_53, width: 1), lit(105, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_52, width: 1), lit(106, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_51, width: 1), lit(107, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_50, width: 1), lit(108, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_49, width: 1), lit(109, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_48, width: 1), lit(110, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_47, width: 1), lit(111, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_46, width: 1), lit(112, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_45, width: 1), lit(113, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_44, width: 1), lit(114, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_43, width: 1), lit(115, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_42, width: 1), lit(116, width: 7, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_41, width: 1), lit(117, width: 7, base: "h", signed: false), lit(0, width: 7, base: "h", signed: false)))))))))))))))))))))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                  )
                                                                                                                                                                                                )
                                                                                                                                                                                              )
                                                                                                                                                                                            )
                                                                                                                                                                                          )
                                                                                                                                                                                        )
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            )
                                                                                                                          )
                                                                                                                        )
                                                                                                                      )
                                                                                                                    )
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h2186f3a2_0_158,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_0, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_157,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_156,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_5, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_155,
    (
        (
          ~sig(:cond_8, width: 1)
        ) &
        sig(:cond_7, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_154,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_10, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_153,
    (
        (
          ~sig(:cond_12, width: 1)
        ) &
        sig(:cond_11, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_152,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_13, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_151,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_15, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_150,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_16, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_149,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_17, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_148,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_20, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_147,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_21, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_146,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_23, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_145,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_24, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_144,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_143,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_27, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_142,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_28, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_141,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_29, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_140,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_30, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_139,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_31, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_138,
    (
        (
          ~sig(:cond_33, width: 1)
        ) &
        sig(:cond_32, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_137,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_34, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_136,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_35, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_135,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_36, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_134,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_37, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_133,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_38, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_132,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_39, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_131,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_40, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_130,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_41, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_129,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_42, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_128,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_43, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_127,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_44, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_126,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_45, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_125,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_46, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_124,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_47, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_123,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_48, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_122,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_49, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_121,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_51, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_120,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_52, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_119,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_53, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_118,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_54, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_117,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_55, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_116,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_57, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_115,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_58, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_114,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_59, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_113,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_60, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_112,
    (
        (
          ~sig(:cond_62, width: 1)
        ) &
        sig(:cond_61, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_111,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_63, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_110,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_64, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_109,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_65, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_108,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_66, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_107,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_67, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_106,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_68, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_105,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_69, width: 1)
    )
  assign :consume_one_three,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_70, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_104,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_71, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_103,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_72, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_102,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_73, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_101,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_74, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_100,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_76, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_99,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_77, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_98,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_78, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_97,
    lit(8, width: 4, base: "h", signed: false).concat(
      sig(:decoder, width: 96)[5..3]
    )
  assign :__VdfgRegularize_h2186f3a2_0_96,
    (
        (
          ~sig(:cond_80, width: 1)
        ) &
        sig(:cond_79, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_95,
    (
        (
          ~sig(:cond_82, width: 1)
        ) &
        sig(:cond_81, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_94,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_83, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_93,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_84, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_92,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_85, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_91,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_86, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_90,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_87, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_89,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_88, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_88,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_89, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_87,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_90, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_86,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_91, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_85,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_92, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_84,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_93, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_83,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_94, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_82,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_95, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_81,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_96, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_80,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_98, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_79,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_99, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_78,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_19, width: 1) &
        sig(:cond_102, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_77,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_103, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_76,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_104, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_75,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_105, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_74,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_20, width: 1) &
        sig(:cond_106, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_73,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_107, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_72,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_108, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_71,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_109, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_70,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_110, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_69,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_111, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_68,
    (
        (
          ~sig(:cond_114, width: 1)
        ) &
        sig(:cond_113, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_67,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_115, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_66,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_117, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_65,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_119, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_64,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_120, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_63,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_121, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_62,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_122, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_61,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_123, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_60,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_124, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_59,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_125, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_58,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_126, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_57,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_127, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_56,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_128, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_55,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_129, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_54,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_130, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_53,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_21, width: 1) &
        sig(:cond_131, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_52,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_132, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_51,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_133, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_50,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_134, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_49,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_135, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_48,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_136, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_47,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_137, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_46,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_138, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_45,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_139, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_44,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_140, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_43,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_141, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_42,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_142, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_41,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_18, width: 1) &
        sig(:cond_143, width: 1)
    )
  assign :dec_is_complex,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_158, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_156, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_155, width: 1) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_148, width: 1) |
                    (
                        sig(:__VdfgRegularize_h2186f3a2_0_147, width: 1) |
                        (
                            sig(:__VdfgRegularize_h2186f3a2_0_146, width: 1) |
                            (
                                (
                                    sig(:__VdfgRegularize_h2186f3a2_0_145, width: 1) &
                                    sig(:cond_25, width: 1)
                                ) |
                                (
                                    sig(:__VdfgRegularize_h2186f3a2_0_142, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h2186f3a2_0_139, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h2186f3a2_0_138, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h2186f3a2_0_137, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h2186f3a2_0_136, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h2186f3a2_0_127, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h2186f3a2_0_122, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h2186f3a2_0_120, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h2186f3a2_0_115, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h2186f3a2_0_113, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h2186f3a2_0_22, width: 1) |
                                                                            (
                                                                                sig(:__VdfgRegularize_h2186f3a2_0_111, width: 1) |
                                                                                (
                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_110, width: 1) |
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_109, width: 1) |
                                                                                        (
                                                                                            sig(:consume_one_three, width: 1) |
                                                                                            (
                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_99, width: 1) |
                                                                                                (
                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_89, width: 1) |
                                                                                                    (
                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_88, width: 1) |
                                                                                                        (
                                                                                                            (
                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_87, width: 1) &
                                                                                                                sig(:cond_25, width: 1)
                                                                                                            ) |
                                                                                                            (
                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_85, width: 1) |
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_81, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_80, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_79, width: 1) |
                                                                                                                            (
                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_77, width: 1) |
                                                                                                                                (
                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_76, width: 1) |
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_75, width: 1) |
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_74, width: 1) |
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_73, width: 1) &
                                                                                                                                                    sig(:cond_25, width: 1)
                                                                                                                                                ) |
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_72, width: 1) |
                                                                                                                                                    (
                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_71, width: 1) |
                                                                                                                                                        (
                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_69, width: 1) |
                                                                                                                                                            (
                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_68, width: 1) |
                                                                                                                                                                (
                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_67, width: 1) |
                                                                                                                                                                    (
                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_60, width: 1) |
                                                                                                                                                                        (
                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_57, width: 1) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_54, width: 1) |
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_53, width: 1) |
                                                                                                                                                                                    (
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_52, width: 1) &
                                                                                                                                                                                            sig(:cond_25, width: 1)
                                                                                                                                                                                        ) |
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_49, width: 1) |
                                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_23, width: 1)
                                                                                                                                                                                        )
                                                                                                                                                                                    )
                                                                                                                                                                                )
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    )
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h2186f3a2_0_22,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_112, width: 1) &
        sig(:cond_56, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_23,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_48, width: 1) &
        sig(:cond_56, width: 1)
    )
  assign :consume_one_two,
    (
        sig(:cond_2, width: 1) &
        (
            sig(:__VdfgRegularize_h2186f3a2_0_142, width: 1) |
            sig(:__VdfgRegularize_h2186f3a2_0_88, width: 1)
        )
    )
  assign :consume_modregrm_imm,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_40, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_39, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_38, width: 1) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_37, width: 1) |
                    (
                        sig(:__VdfgRegularize_h2186f3a2_0_116, width: 1) |
                        (
                            sig(:__VdfgRegularize_h2186f3a2_0_103, width: 1) |
                            (
                                sig(:__VdfgRegularize_h2186f3a2_0_36, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h2186f3a2_0_35, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h2186f3a2_0_95, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h2186f3a2_0_90, width: 1) |
                                            sig(:__VdfgRegularize_h2186f3a2_0_64, width: 1)
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h2186f3a2_0_40,
    (
        sig(:cond_2, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_126, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_39,
    (
        sig(:cond_2, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_125, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_38,
    (
        sig(:cond_2, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_124, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_37,
    (
        sig(:cond_2, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_123, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_36,
    (
        sig(:cond_2, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_101, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_35,
    (
        sig(:cond_2, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_100, width: 1)
    )
  assign :consume_one,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_154, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_148, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_146, width: 1) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_145, width: 1) |
                    (
                        sig(:__VdfgRegularize_h2186f3a2_0_144, width: 1) |
                        (
                            sig(:__VdfgRegularize_h2186f3a2_0_34, width: 1) |
                            (
                                sig(:__VdfgRegularize_h2186f3a2_0_140, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h2186f3a2_0_135, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h2186f3a2_0_134, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h2186f3a2_0_133, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h2186f3a2_0_132, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h2186f3a2_0_131, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h2186f3a2_0_130, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h2186f3a2_0_127, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h2186f3a2_0_122, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h2186f3a2_0_121, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h2186f3a2_0_115, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h2186f3a2_0_109, width: 1) |
                                                                            (
                                                                                sig(:__VdfgRegularize_h2186f3a2_0_108, width: 1) |
                                                                                (
                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_102, width: 1) |
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_99, width: 1) |
                                                                                        (
                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_89, width: 1) |
                                                                                            (
                                                                                                (
                                                                                                    sig(:cond_75, width: 1) &
                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_88, width: 1)
                                                                                                ) |
                                                                                                (
                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_87, width: 1) |
                                                                                                    (
                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_86, width: 1) |
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_84, width: 1) |
                                                                                                            (
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_81, width: 1) &
                                                                                                                    sig(:cond_97, width: 1)
                                                                                                                ) |
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_80, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_24, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_73, width: 1) |
                                                                                                                            (
                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_72, width: 1) |
                                                                                                                                (
                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_71, width: 1) |
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_70, width: 1) |
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_25, width: 1) |
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_63, width: 1) |
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_62, width: 1) |
                                                                                                                                                    (
                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_61, width: 1) |
                                                                                                                                                        (
                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_60, width: 1) |
                                                                                                                                                            (
                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_59, width: 1) |
                                                                                                                                                                (
                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_58, width: 1) |
                                                                                                                                                                    (
                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_56, width: 1) |
                                                                                                                                                                        (
                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_52, width: 1) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_49, width: 1) |
                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_26, width: 1)
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    )
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h2186f3a2_0_34,
    (
        sig(:cond_75, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_142, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_24,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_79, width: 1) &
        sig(:cond_100, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_25,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_67, width: 1) &
        sig(:cond_100, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_26,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_47, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_46, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_45, width: 1) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_44, width: 1) |
                    sig(:__VdfgRegularize_h2186f3a2_0_43, width: 1)
                )
            )
        )
    )
  assign :consume_one_one,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_157, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_33, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_129, width: 1) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_128, width: 1) |
                    (
                        sig(:__VdfgRegularize_h2186f3a2_0_93, width: 1) |
                        (
                            (
                                (
                                  ~sig(:cond_97, width: 1)
                                ) &
                                sig(:__VdfgRegularize_h2186f3a2_0_81, width: 1)
                            ) |
                            (
                                sig(:__VdfgRegularize_h2186f3a2_0_32, width: 1) |
                                sig(:__VdfgRegularize_h2186f3a2_0_31, width: 1)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h2186f3a2_0_33,
    (
        (
          ~sig(:dec_prefix_2byte, width: 1)
        ) &
        sig(:__VdfgRegularize_h2186f3a2_0_149, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_32,
    (
        sig(:cond_118, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_79, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_31,
    (
        sig(:cond_118, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_67, width: 1)
    )
  assign :consume_one_imm,
    (
        (
            sig(:__VdfgRegularize_h2186f3a2_0_149, width: 1) &
            sig(:dec_prefix_2byte, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_98, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_92, width: 1) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_83, width: 1) |
                    sig(:__VdfgRegularize_h2186f3a2_0_66, width: 1)
                )
            )
        )
    )
  assign :consume_call_jmp_imm,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_156, width: 1) |
        sig(:__VdfgRegularize_h2186f3a2_0_69, width: 1)
    )
  assign :consume_modregrm_one,
    (
        sig(:__VdfgRegularize_h2186f3a2_0_158, width: 1) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_155, width: 1) |
            (
                sig(:__VdfgRegularize_h2186f3a2_0_153, width: 1) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_152, width: 1) |
                    (
                        sig(:__VdfgRegularize_h2186f3a2_0_151, width: 1) |
                        (
                            sig(:__VdfgRegularize_h2186f3a2_0_150, width: 1) |
                            (
                                sig(:__VdfgRegularize_h2186f3a2_0_147, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h2186f3a2_0_143, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h2186f3a2_0_141, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h2186f3a2_0_139, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h2186f3a2_0_138, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h2186f3a2_0_137, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h2186f3a2_0_136, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h2186f3a2_0_30, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h2186f3a2_0_29, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h2186f3a2_0_28, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h2186f3a2_0_27, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h2186f3a2_0_120, width: 1) |
                                                                            (
                                                                                sig(:__VdfgRegularize_h2186f3a2_0_119, width: 1) |
                                                                                (
                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_118, width: 1) |
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_117, width: 1) |
                                                                                        (
                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_114, width: 1) |
                                                                                            (
                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_113, width: 1) |
                                                                                                (
                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_112, width: 1) |
                                                                                                    (
                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_111, width: 1) |
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_110, width: 1) |
                                                                                                            (
                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_107, width: 1) |
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_106, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_105, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_104, width: 1) |
                                                                                                                            (
                                                                                                                                (
                                                                                                                                    sig(:cond_75, width: 1) &
                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_101, width: 1)
                                                                                                                                ) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:cond_75, width: 1) &
                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_100, width: 1)
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_96, width: 1) |
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_94, width: 1) |
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_91, width: 1) |
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_85, width: 1) |
                                                                                                                                                    (
                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_82, width: 1) |
                                                                                                                                                        (
                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_78, width: 1) |
                                                                                                                                                            (
                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_77, width: 1) |
                                                                                                                                                                (
                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_76, width: 1) |
                                                                                                                                                                    (
                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_75, width: 1) |
                                                                                                                                                                        (
                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_74, width: 1) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_68, width: 1) |
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_65, width: 1) |
                                                                                                                                                                                    (
                                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_57, width: 1) |
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_55, width: 1) |
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_54, width: 1) |
                                                                                                                                                                                                (
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :__VdfgRegularize_h2186f3a2_0_53,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ) |
                                                                                                                                                                                                    (
                                                                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_51, width: 1) |
                                                                                                                                                                                                      (sig(:__VdfgRegularize_h2186f3a2_0_50, width: 1) | (sig(:__VdfgRegularize_h2186f3a2_0_48, width: 1) | (sig(:__VdfgRegularize_h2186f3a2_0_42, width: 1) | sig(:__VdfgRegularize_h2186f3a2_0_41, width: 1))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                )
                                                                                                                                                                                            )
                                                                                                                                                                                        )
                                                                                                                                                                                    )
                                                                                                                                                                                )
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    )
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h2186f3a2_0_30,
    (
        sig(:cond_75, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_126, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_29,
    (
        sig(:cond_75, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_125, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_28,
    (
        sig(:cond_75, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_124, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_27,
    (
        sig(:cond_75, width: 1) &
        sig(:__VdfgRegularize_h2186f3a2_0_123, width: 1)
    )
  assign :dec_is_8bit,
    (
        (
            sig(:cond_2, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_158, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_h2186f3a2_0_157, width: 1) |
            (
                (
                    sig(:cond_2, width: 1) &
                    sig(:__VdfgRegularize_h2186f3a2_0_150, width: 1)
                ) |
                (
                    sig(:__VdfgRegularize_h2186f3a2_0_33, width: 1) |
                    (
                        (
                            sig(:cond_2, width: 1) &
                            sig(:__VdfgRegularize_h2186f3a2_0_145, width: 1)
                        ) |
                        (
                            (
                                sig(:cond_2, width: 1) &
                                sig(:__VdfgRegularize_h2186f3a2_0_143, width: 1)
                            ) |
                            (
                                sig(:__VdfgRegularize_h2186f3a2_0_129, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h2186f3a2_0_128, width: 1) |
                                    (
                                        (
                                            sig(:cond_2, width: 1) &
                                            sig(:__VdfgRegularize_h2186f3a2_0_119, width: 1)
                                        ) |
                                        (
                                            (
                                                sig(:cond_2, width: 1) &
                                                sig(:__VdfgRegularize_h2186f3a2_0_118, width: 1)
                                            ) |
                                            (
                                                (
                                                    sig(:cond_2, width: 1) &
                                                    sig(:__VdfgRegularize_h2186f3a2_0_117, width: 1)
                                                ) |
                                                (
                                                    (
                                                        sig(:cond_2, width: 1) &
                                                        sig(:__VdfgRegularize_h2186f3a2_0_116, width: 1)
                                                    ) |
                                                    (
                                                        (
                                                            sig(:cond_2, width: 1) &
                                                            sig(:__VdfgRegularize_h2186f3a2_0_115, width: 1)
                                                        ) |
                                                        (
                                                            sig(:__VdfgRegularize_h2186f3a2_0_106, width: 1) |
                                                            (
                                                                (
                                                                    sig(:cond_2, width: 1) &
                                                                    sig(:__VdfgRegularize_h2186f3a2_0_105, width: 1)
                                                                ) |
                                                                (
                                                                    (
                                                                        sig(:cond_2, width: 1) &
                                                                        sig(:__VdfgRegularize_h2186f3a2_0_104, width: 1)
                                                                    ) |
                                                                    (
                                                                        (
                                                                            sig(:cond_2, width: 1) &
                                                                            sig(:__VdfgRegularize_h2186f3a2_0_98, width: 1)
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:cond_2, width: 1) &
                                                                                sig(:__VdfgRegularize_h2186f3a2_0_96, width: 1)
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    sig(:cond_2, width: 1) &
                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_95, width: 1)
                                                                                ) |
                                                                                (
                                                                                    (
                                                                                        sig(:cond_2, width: 1) &
                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_94, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_93, width: 1) |
                                                                                        (
                                                                                            (
                                                                                                sig(:cond_2, width: 1) &
                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_92, width: 1)
                                                                                            ) |
                                                                                            (
                                                                                                (
                                                                                                    sig(:cond_2, width: 1) &
                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_91, width: 1)
                                                                                                ) |
                                                                                                (
                                                                                                    (
                                                                                                        sig(:cond_2, width: 1) &
                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_90, width: 1)
                                                                                                    ) |
                                                                                                    (
                                                                                                        (
                                                                                                            sig(:cond_2, width: 1) &
                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_87, width: 1)
                                                                                                        ) |
                                                                                                        (
                                                                                                            (
                                                                                                                sig(:cond_2, width: 1) &
                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_85, width: 1)
                                                                                                            ) |
                                                                                                            (
                                                                                                                (
                                                                                                                    sig(:cond_2, width: 1) &
                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_79, width: 1)
                                                                                                                ) |
                                                                                                                (
                                                                                                                    (
                                                                                                                        sig(:cond_2, width: 1) &
                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_78, width: 1)
                                                                                                                    ) |
                                                                                                                    (
                                                                                                                        (
                                                                                                                            sig(:cond_2, width: 1) &
                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_73, width: 1)
                                                                                                                        ) |
                                                                                                                        (
                                                                                                                            (
                                                                                                                                sig(:cond_2, width: 1) &
                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_72, width: 1)
                                                                                                                            ) |
                                                                                                                            (
                                                                                                                                (
                                                                                                                                    sig(:cond_2, width: 1) &
                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_71, width: 1)
                                                                                                                                ) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_69, width: 1) &
                                                                                                                                        (
                                                                                                                                            lit(11, width: 4, base: "h", signed: false) ==
                                                                                                                                            sig(:decoder, width: 96)[3..0]
                                                                                                                                        )
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:cond_2, width: 1) &
                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_67, width: 1)
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            (
                                                                                                                                                sig(:cond_2, width: 1) &
                                                                                                                                                sig(:consume_mem_offset, width: 1)
                                                                                                                                            ) |
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    sig(:cond_118, width: 1) &
                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_66, width: 1)
                                                                                                                                                ) |
                                                                                                                                                (
                                                                                                                                                    (
                                                                                                                                                        sig(:cond_2, width: 1) &
                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_65, width: 1)
                                                                                                                                                    ) |
                                                                                                                                                    (
                                                                                                                                                        (
                                                                                                                                                            sig(:cond_2, width: 1) &
                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_64, width: 1)
                                                                                                                                                        ) |
                                                                                                                                                        (
                                                                                                                                                            (
                                                                                                                                                                sig(:cond_2, width: 1) &
                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_52, width: 1)
                                                                                                                                                            ) |
                                                                                                                                                            (
                                                                                                                                                                (
                                                                                                                                                                    sig(:cond_2, width: 1) &
                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_51, width: 1)
                                                                                                                                                                ) |
                                                                                                                                                                (
                                                                                                                                                                    (
                                                                                                                                                                        sig(:cond_2, width: 1) &
                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_50, width: 1)
                                                                                                                                                                    ) |
                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_26, width: 1)
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :dec_cmdex,
    mux(
      (
          sig(:cond_6, width: 1) &
          sig(:__VdfgRegularize_h2186f3a2_0_156, width: 1)
      ),
      lit(1, width: 4, base: "h", signed: false),
      mux(
        (
            sig(:cond_56, width: 1) &
            sig(:__VdfgRegularize_h2186f3a2_0_156, width: 1)
        ),
        lit(3, width: 4, base: "h", signed: false),
        mux(
          (
              sig(:cond_9, width: 1) &
              sig(:__VdfgRegularize_h2186f3a2_0_155, width: 1)
          ),
          lit(0, width: 4, base: "h", signed: false),
          mux(
            (
                sig(:decoder, width: 96)[11] &
                sig(:__VdfgRegularize_h2186f3a2_0_155, width: 1)
            ),
            lit(2, width: 4, base: "h", signed: false),
            mux(
              sig(:__VdfgRegularize_h2186f3a2_0_154, width: 1),
              lit(0, width: 1, base: "d", signed: false).concat(
                sig(:decoder, width: 96)[5..3]
              ),
              mux(
                sig(:__VdfgRegularize_h2186f3a2_0_153, width: 1),
                lit(1, width: 1, base: "h", signed: false).concat(
                  sig(:decoder, width: 96)[13..11]
                ),
                mux(
                  sig(:__VdfgRegularize_h2186f3a2_0_152, width: 1),
                  lit(14, width: 4, base: "h", signed: false),
                  mux(
                    sig(:__VdfgRegularize_h2186f3a2_0_151, width: 1),
                    lit(15, width: 4, base: "h", signed: false),
                    mux(
                      sig(:__VdfgRegularize_h2186f3a2_0_148, width: 1),
                      lit(0, width: 4, base: "h", signed: false),
                      mux(
                        sig(:__VdfgRegularize_h2186f3a2_0_147, width: 1),
                        lit(0, width: 4, base: "h", signed: false),
                        mux(
                          sig(:__VdfgRegularize_h2186f3a2_0_146, width: 1),
                          lit(0, width: 4, base: "h", signed: false),
                          mux(
                            sig(:__VdfgRegularize_h2186f3a2_0_145, width: 1),
                            lit(0, width: 4, base: "h", signed: false),
                            mux(
                              sig(:__VdfgRegularize_h2186f3a2_0_144, width: 1),
                              sig(:cond_100, width: 1),
                              mux(
                                sig(:__VdfgRegularize_h2186f3a2_0_143, width: 1),
                                lit(1, width: 3, base: "h", signed: false).concat(
                                  sig(:decoder, width: 96)[11]
                                ),
                                mux(
                                  (
                                      sig(:cond_2, width: 1) &
                                      sig(:__VdfgRegularize_h2186f3a2_0_142, width: 1)
                                  ),
                                  lit(1, width: 4, base: "h", signed: false),
                                  mux(
                                    sig(:__VdfgRegularize_h2186f3a2_0_34, width: 1),
                                    lit(0, width: 4, base: "h", signed: false),
                                    mux(
                                      sig(:__VdfgRegularize_h2186f3a2_0_139, width: 1),
                                      lit(0, width: 4, base: "h", signed: false),
                                      mux(
                                        sig(:__VdfgRegularize_h2186f3a2_0_138, width: 1),
                                        lit(0, width: 4, base: "h", signed: false),
                                        mux(
                                          sig(:__VdfgRegularize_h2186f3a2_0_137, width: 1),
                                          lit(0, width: 4, base: "h", signed: false),
                                          mux(
                                            sig(:__VdfgRegularize_h2186f3a2_0_136, width: 1),
                                            lit(0, width: 4, base: "h", signed: false),
                                            mux(
                                              sig(:__VdfgRegularize_h2186f3a2_0_127, width: 1),
                                              lit(0, width: 4, base: "h", signed: false),
                                              mux(
                                                sig(:__VdfgRegularize_h2186f3a2_0_40, width: 1),
                                                lit(0, width: 4, base: "h", signed: false),
                                                mux(
                                                  sig(:__VdfgRegularize_h2186f3a2_0_30, width: 1),
                                                  lit(1, width: 4, base: "h", signed: false),
                                                  mux(
                                                    sig(:__VdfgRegularize_h2186f3a2_0_39, width: 1),
                                                    lit(0, width: 4, base: "h", signed: false),
                                                    mux(
                                                      sig(:__VdfgRegularize_h2186f3a2_0_29, width: 1),
                                                      lit(1, width: 4, base: "h", signed: false),
                                                      mux(
                                                        sig(:__VdfgRegularize_h2186f3a2_0_38, width: 1),
                                                        lit(0, width: 4, base: "h", signed: false),
                                                        mux(
                                                          sig(:__VdfgRegularize_h2186f3a2_0_28, width: 1),
                                                          lit(1, width: 4, base: "h", signed: false),
                                                          mux(
                                                            sig(:__VdfgRegularize_h2186f3a2_0_37, width: 1),
                                                            lit(0, width: 4, base: "h", signed: false),
                                                            mux(
                                                              sig(:__VdfgRegularize_h2186f3a2_0_27, width: 1),
                                                              lit(1, width: 4, base: "h", signed: false),
                                                              mux(
                                                                (
                                                                    sig(:cond_50, width: 1) &
                                                                    sig(:__VdfgRegularize_h2186f3a2_0_122, width: 1)
                                                                ),
                                                                lit(0, width: 4, base: "h", signed: false),
                                                                mux(
                                                                  (
                                                                      sig(:protected_mode, width: 1) &
                                                                      sig(:__VdfgRegularize_h2186f3a2_0_122, width: 1)
                                                                  ),
                                                                  lit(4, width: 4, base: "h", signed: false),
                                                                  mux(
                                                                    sig(:__VdfgRegularize_h2186f3a2_0_121, width: 1),
                                                                    lit(0, width: 4, base: "h", signed: false),
                                                                    mux(
                                                                      sig(:__VdfgRegularize_h2186f3a2_0_120, width: 1),
                                                                      lit(1, width: 4, base: "h", signed: false),
                                                                      mux(
                                                                        (
                                                                            sig(:__VdfgRegularize_h2186f3a2_0_117, width: 1) &
                                                                            sig(:cond_56, width: 1)
                                                                        ),
                                                                        lit(0, width: 4, base: "h", signed: false),
                                                                        mux(
                                                                          (
                                                                              sig(:cond_6, width: 1) &
                                                                              sig(:__VdfgRegularize_h2186f3a2_0_117, width: 1)
                                                                          ),
                                                                          lit(1, width: 4, base: "h", signed: false),
                                                                          mux(
                                                                            sig(:__VdfgRegularize_h2186f3a2_0_116, width: 1),
                                                                            lit(2, width: 4, base: "h", signed: false),
                                                                            mux(
                                                                              sig(:__VdfgRegularize_h2186f3a2_0_115, width: 1),
                                                                              lit(0, width: 4, base: "h", signed: false),
                                                                              mux(
                                                                                sig(:__VdfgRegularize_h2186f3a2_0_114, width: 1),
                                                                                lit(0, width: 4, base: "h", signed: false),
                                                                                mux(
                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_113, width: 1),
                                                                                  lit(1, width: 4, base: "h", signed: false),
                                                                                  mux(
                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_22, width: 1),
                                                                                    lit(4, width: 4, base: "h", signed: false),
                                                                                    mux(
                                                                                      (
                                                                                          sig(:cond_6, width: 1) &
                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_112, width: 1)
                                                                                      ),
                                                                                      lit(3, width: 4, base: "h", signed: false),
                                                                                      mux(
                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_111, width: 1),
                                                                                        lit(8, width: 4, base: "h", signed: false),
                                                                                        mux(
                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_110, width: 1),
                                                                                          lit(8, width: 4, base: "h", signed: false),
                                                                                          mux(
                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_109, width: 1),
                                                                                            lit(0, width: 4, base: "h", signed: false),
                                                                                            mux(
                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_108, width: 1),
                                                                                              lit(0, width: 4, base: "h", signed: false),
                                                                                              mux(
                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_107, width: 1),
                                                                                                lit(1, width: 4, base: "h", signed: false),
                                                                                                mux(
                                                                                                  sig(:consume_one_three, width: 1),
                                                                                                  lit(0, width: 4, base: "h", signed: false),
                                                                                                  mux(
                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_104, width: 1),
                                                                                                    lit(0, width: 4, base: "h", signed: false),
                                                                                                    mux(
                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_103, width: 1),
                                                                                                      lit(1, width: 4, base: "h", signed: false),
                                                                                                      mux(
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_101, width: 1) &
                                                                                                            sig(:cond_75, width: 1)
                                                                                                        ),
                                                                                                        lit(0, width: 4, base: "h", signed: false),
                                                                                                        mux(
                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_36, width: 1),
                                                                                                          lit(1, width: 4, base: "h", signed: false),
                                                                                                          mux(
                                                                                                            (
                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_100, width: 1) &
                                                                                                                sig(:cond_75, width: 1)
                                                                                                            ),
                                                                                                            lit(0, width: 4, base: "h", signed: false),
                                                                                                            mux(
                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_35, width: 1),
                                                                                                              lit(1, width: 4, base: "h", signed: false),
                                                                                                              mux(
                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_99, width: 1),
                                                                                                                lit(0, width: 4, base: "h", signed: false),
                                                                                                                mux(
                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_98, width: 1),
                                                                                                                  lit(0, width: 4, base: "h", signed: false),
                                                                                                                  mux(
                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_96, width: 1),
                                                                                                                    lit(1, width: 4, base: "h", signed: false),
                                                                                                                    mux(
                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_95, width: 1),
                                                                                                                      lit(2, width: 4, base: "h", signed: false),
                                                                                                                      mux(
                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_93, width: 1),
                                                                                                                        case_select(
                                                                                                                          sig(:decoder, width: 96)[1..0],
                                                                                                                          cases: {
                                                                                                                            0 => lit(0, width: 4, base: "h", signed: false),
                                                                                                                            1 => lit(1, width: 4, base: "h", signed: false)
                                                                                                                          },
                                                                                                                          default: lit(2, width: 4, base: "h", signed: false)
                                                                                                                        ),
                                                                                                                        mux(
                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_92, width: 1),
                                                                                                                          lit(0, width: 4, base: "h", signed: false),
                                                                                                                          mux(
                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_91, width: 1),
                                                                                                                            lit(1, width: 4, base: "h", signed: false),
                                                                                                                            mux(
                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_90, width: 1),
                                                                                                                              lit(2, width: 4, base: "h", signed: false),
                                                                                                                              mux(
                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_89, width: 1),
                                                                                                                                lit(0, width: 4, base: "h", signed: false),
                                                                                                                                mux(
                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_88, width: 1),
                                                                                                                                  lit(1, width: 4, base: "h", signed: false),
                                                                                                                                  mux(
                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_87, width: 1),
                                                                                                                                    lit(0, width: 4, base: "h", signed: false),
                                                                                                                                    mux(
                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_86, width: 1),
                                                                                                                                      lit(0, width: 4, base: "h", signed: false),
                                                                                                                                      mux(
                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_85, width: 1),
                                                                                                                                        lit(1, width: 4, base: "h", signed: false),
                                                                                                                                        mux(
                                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_84, width: 1),
                                                                                                                                          lit(0, width: 4, base: "h", signed: false),
                                                                                                                                          mux(
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_83, width: 1) &
                                                                                                                                                sig(:cond_56, width: 1)
                                                                                                                                            ),
                                                                                                                                            lit(1, width: 4, base: "h", signed: false),
                                                                                                                                            mux(
                                                                                                                                              (
                                                                                                                                                  sig(:cond_6, width: 1) &
                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_83, width: 1)
                                                                                                                                              ),
                                                                                                                                              lit(2, width: 4, base: "h", signed: false),
                                                                                                                                              mux(
                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_82, width: 1),
                                                                                                                                                lit(3, width: 4, base: "h", signed: false),
                                                                                                                                                mux(
                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_81, width: 1),
                                                                                                                                                  case_select(
                                                                                                                                                    sig(:decoder, width: 96)[2..0],
                                                                                                                                                    cases: {
                                                                                                                                                      4 => lit(1, width: 4, base: "h", signed: false),
                                                                                                                                                      5 => lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                      6 => lit(2, width: 4, base: "h", signed: false)
                                                                                                                                                    },
                                                                                                                                                    default: lit(3, width: 4, base: "h", signed: false)
                                                                                                                                                  ),
                                                                                                                                                  mux(
                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_80, width: 1),
                                                                                                                                                    lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                    mux(
                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_24, width: 1),
                                                                                                                                                      lit(1, width: 4, base: "h", signed: false),
                                                                                                                                                      mux(
                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_32, width: 1),
                                                                                                                                                        lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                        mux(
                                                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_77, width: 1),
                                                                                                                                                          lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                          mux(
                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_76, width: 1),
                                                                                                                                                            lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                            mux(
                                                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_75, width: 1),
                                                                                                                                                              lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                              mux(
                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_74, width: 1),
                                                                                                                                                                lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                mux(
                                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_73, width: 1),
                                                                                                                                                                  lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                  mux(
                                                                                                                                                                    sig(:__VdfgRegularize_h2186f3a2_0_72, width: 1),
                                                                                                                                                                    lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                    mux(
                                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_71, width: 1),
                                                                                                                                                                      lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                      mux(
                                                                                                                                                                        (
                                                                                                                                                                            sig(:cond_2, width: 1) &
                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_69, width: 1)
                                                                                                                                                                        ),
                                                                                                                                                                        lit(3, width: 4, base: "h", signed: false),
                                                                                                                                                                        mux(
                                                                                                                                                                          (
                                                                                                                                                                              sig(:cond_75, width: 1) &
                                                                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_69, width: 1)
                                                                                                                                                                          ),
                                                                                                                                                                          lit(1, width: 4, base: "h", signed: false),
                                                                                                                                                                          mux(
                                                                                                                                                                            (
                                                                                                                                                                                sig(:cond_9, width: 1) &
                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_68, width: 1)
                                                                                                                                                                            ),
                                                                                                                                                                            lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                            mux(
                                                                                                                                                                              (
                                                                                                                                                                                  sig(:decoder, width: 96)[11] &
                                                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_68, width: 1)
                                                                                                                                                                              ),
                                                                                                                                                                              lit(2, width: 4, base: "h", signed: false),
                                                                                                                                                                              mux(
                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_25, width: 1),
                                                                                                                                                                                lit(1, width: 4, base: "h", signed: false),
                                                                                                                                                                                mux(
                                                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_31, width: 1),
                                                                                                                                                                                  lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                  mux(
                                                                                                                                                                                    sig(:consume_mem_offset, width: 1),
                                                                                                                                                                                    lit(3, width: 4, base: "h", signed: false),
                                                                                                                                                                                    mux(
                                                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_66, width: 1),
                                                                                                                                                                                      lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                      mux(
                                                                                                                                                                                        sig(:__VdfgRegularize_h2186f3a2_0_65, width: 1),
                                                                                                                                                                                        lit(1, width: 4, base: "h", signed: false),
                                                                                                                                                                                        mux(
                                                                                                                                                                                          sig(:__VdfgRegularize_h2186f3a2_0_64, width: 1),
                                                                                                                                                                                          lit(2, width: 4, base: "h", signed: false),
                                                                                                                                                                                          mux(
                                                                                                                                                                                            sig(:__VdfgRegularize_h2186f3a2_0_60, width: 1),
                                                                                                                                                                                            lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                            mux(
                                                                                                                                                                                              sig(:__VdfgRegularize_h2186f3a2_0_57, width: 1),
                                                                                                                                                                                              lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                              mux(
                                                                                                                                                                                                sig(:__VdfgRegularize_h2186f3a2_0_56, width: 1),
                                                                                                                                                                                                lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                                mux(
                                                                                                                                                                                                  sig(:__VdfgRegularize_h2186f3a2_0_54, width: 1),
                                                                                                                                                                                                  lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                                  mux(
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :__VdfgRegularize_h2186f3a2_0_53,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    lit(
                                                                                                                                                                                                      0,
                                                                                                                                                                                                      width: 4,
                                                                                                                                                                                                      base: "h",
                                                                                                                                                                                                      signed: false
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    mux(
                                                                                                                                                                                                      sig(:__VdfgRegularize_h2186f3a2_0_52, width: 1),
                                                                                                                                                                                                      lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                                      mux(sig(:__VdfgRegularize_h2186f3a2_0_49, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:__VdfgRegularize_h2186f3a2_0_23, width: 1), lit(1, width: 4, base: "h", signed: false), lit(0, width: 4, base: "h", signed: false)))
                                                                                                                                                                                                    )
                                                                                                                                                                                                  )
                                                                                                                                                                                                )
                                                                                                                                                                                              )
                                                                                                                                                                                            )
                                                                                                                                                                                          )
                                                                                                                                                                                        )
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            )
                                                                                                                          )
                                                                                                                        )
                                                                                                                      )
                                                                                                                    )
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgBinToOneHot_Idx_h2af0f070_0_0,
    sig(:decoder, width: 96)[7..0]
  assign :__VdfgRegularize_h2186f3a2_0_19,
    (
      ~sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_20,
    (
      ~sig(:cond_14, width: 1)
    )
  assign :__VdfgRegularize_h2186f3a2_0_21,
    (
      ~sig(:cond_22, width: 1)
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

  process :initial_block_1,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :__VdfgBinToOneHot_Pre_h2af0f070_0_0,
      lit(0, width: 8, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :combinational_logic_2,
    sensitivity: [
    ],
    clocked: false,
    initial: false do
    assign(
      sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[sig(:__VdfgBinToOneHot_Pre_h2af0f070_0_0, width: 8)],
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      sig(:__VdfgBinToOneHot_Tab_h2af0f070_0_0, width: 256)[sig(:__VdfgBinToOneHot_Idx_h2af0f070_0_0, width: 8)],
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      :__VdfgBinToOneHot_Pre_h2af0f070_0_0,
      sig(:__VdfgBinToOneHot_Idx_h2af0f070_0_0, width: 8),
      kind: :blocking
    )
  end

end
