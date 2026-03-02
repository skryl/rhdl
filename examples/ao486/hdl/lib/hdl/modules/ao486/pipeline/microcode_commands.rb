# frozen_string_literal: true

class MicrocodeCommands < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: microcode_commands

  def self._import_decl_kinds
    {
      __VdfgRegularize_hca2350fd_0_0: :logic,
      __VdfgRegularize_hca2350fd_0_1: :logic,
      __VdfgRegularize_hca2350fd_0_10: :logic,
      __VdfgRegularize_hca2350fd_0_100: :logic,
      __VdfgRegularize_hca2350fd_0_101: :logic,
      __VdfgRegularize_hca2350fd_0_102: :logic,
      __VdfgRegularize_hca2350fd_0_103: :logic,
      __VdfgRegularize_hca2350fd_0_104: :logic,
      __VdfgRegularize_hca2350fd_0_106: :logic,
      __VdfgRegularize_hca2350fd_0_107: :logic,
      __VdfgRegularize_hca2350fd_0_108: :logic,
      __VdfgRegularize_hca2350fd_0_11: :logic,
      __VdfgRegularize_hca2350fd_0_12: :logic,
      __VdfgRegularize_hca2350fd_0_13: :logic,
      __VdfgRegularize_hca2350fd_0_14: :logic,
      __VdfgRegularize_hca2350fd_0_15: :logic,
      __VdfgRegularize_hca2350fd_0_16: :logic,
      __VdfgRegularize_hca2350fd_0_17: :logic,
      __VdfgRegularize_hca2350fd_0_18: :logic,
      __VdfgRegularize_hca2350fd_0_19: :logic,
      __VdfgRegularize_hca2350fd_0_2: :logic,
      __VdfgRegularize_hca2350fd_0_20: :logic,
      __VdfgRegularize_hca2350fd_0_21: :logic,
      __VdfgRegularize_hca2350fd_0_22: :logic,
      __VdfgRegularize_hca2350fd_0_23: :logic,
      __VdfgRegularize_hca2350fd_0_24: :logic,
      __VdfgRegularize_hca2350fd_0_25: :logic,
      __VdfgRegularize_hca2350fd_0_26: :logic,
      __VdfgRegularize_hca2350fd_0_27: :logic,
      __VdfgRegularize_hca2350fd_0_28: :logic,
      __VdfgRegularize_hca2350fd_0_29: :logic,
      __VdfgRegularize_hca2350fd_0_3: :logic,
      __VdfgRegularize_hca2350fd_0_30: :logic,
      __VdfgRegularize_hca2350fd_0_31: :logic,
      __VdfgRegularize_hca2350fd_0_32: :logic,
      __VdfgRegularize_hca2350fd_0_33: :logic,
      __VdfgRegularize_hca2350fd_0_34: :logic,
      __VdfgRegularize_hca2350fd_0_35: :logic,
      __VdfgRegularize_hca2350fd_0_36: :logic,
      __VdfgRegularize_hca2350fd_0_37: :logic,
      __VdfgRegularize_hca2350fd_0_38: :logic,
      __VdfgRegularize_hca2350fd_0_39: :logic,
      __VdfgRegularize_hca2350fd_0_4: :logic,
      __VdfgRegularize_hca2350fd_0_40: :logic,
      __VdfgRegularize_hca2350fd_0_41: :logic,
      __VdfgRegularize_hca2350fd_0_42: :logic,
      __VdfgRegularize_hca2350fd_0_43: :logic,
      __VdfgRegularize_hca2350fd_0_44: :logic,
      __VdfgRegularize_hca2350fd_0_45: :logic,
      __VdfgRegularize_hca2350fd_0_46: :logic,
      __VdfgRegularize_hca2350fd_0_47: :logic,
      __VdfgRegularize_hca2350fd_0_48: :logic,
      __VdfgRegularize_hca2350fd_0_49: :logic,
      __VdfgRegularize_hca2350fd_0_5: :logic,
      __VdfgRegularize_hca2350fd_0_50: :logic,
      __VdfgRegularize_hca2350fd_0_51: :logic,
      __VdfgRegularize_hca2350fd_0_52: :logic,
      __VdfgRegularize_hca2350fd_0_53: :logic,
      __VdfgRegularize_hca2350fd_0_54: :logic,
      __VdfgRegularize_hca2350fd_0_55: :logic,
      __VdfgRegularize_hca2350fd_0_56: :logic,
      __VdfgRegularize_hca2350fd_0_57: :logic,
      __VdfgRegularize_hca2350fd_0_58: :logic,
      __VdfgRegularize_hca2350fd_0_59: :logic,
      __VdfgRegularize_hca2350fd_0_6: :logic,
      __VdfgRegularize_hca2350fd_0_60: :logic,
      __VdfgRegularize_hca2350fd_0_61: :logic,
      __VdfgRegularize_hca2350fd_0_62: :logic,
      __VdfgRegularize_hca2350fd_0_63: :logic,
      __VdfgRegularize_hca2350fd_0_64: :logic,
      __VdfgRegularize_hca2350fd_0_65: :logic,
      __VdfgRegularize_hca2350fd_0_66: :logic,
      __VdfgRegularize_hca2350fd_0_67: :logic,
      __VdfgRegularize_hca2350fd_0_68: :logic,
      __VdfgRegularize_hca2350fd_0_69: :logic,
      __VdfgRegularize_hca2350fd_0_7: :logic,
      __VdfgRegularize_hca2350fd_0_70: :logic,
      __VdfgRegularize_hca2350fd_0_71: :logic,
      __VdfgRegularize_hca2350fd_0_72: :logic,
      __VdfgRegularize_hca2350fd_0_73: :logic,
      __VdfgRegularize_hca2350fd_0_74: :logic,
      __VdfgRegularize_hca2350fd_0_75: :logic,
      __VdfgRegularize_hca2350fd_0_76: :logic,
      __VdfgRegularize_hca2350fd_0_77: :logic,
      __VdfgRegularize_hca2350fd_0_78: :logic,
      __VdfgRegularize_hca2350fd_0_79: :logic,
      __VdfgRegularize_hca2350fd_0_8: :logic,
      __VdfgRegularize_hca2350fd_0_80: :logic,
      __VdfgRegularize_hca2350fd_0_81: :logic,
      __VdfgRegularize_hca2350fd_0_82: :logic,
      __VdfgRegularize_hca2350fd_0_83: :logic,
      __VdfgRegularize_hca2350fd_0_84: :logic,
      __VdfgRegularize_hca2350fd_0_85: :logic,
      __VdfgRegularize_hca2350fd_0_86: :logic,
      __VdfgRegularize_hca2350fd_0_87: :logic,
      __VdfgRegularize_hca2350fd_0_88: :logic,
      __VdfgRegularize_hca2350fd_0_89: :logic,
      __VdfgRegularize_hca2350fd_0_9: :logic,
      __VdfgRegularize_hca2350fd_0_90: :logic,
      __VdfgRegularize_hca2350fd_0_91: :logic,
      __VdfgRegularize_hca2350fd_0_92: :logic,
      __VdfgRegularize_hca2350fd_0_93: :logic,
      __VdfgRegularize_hca2350fd_0_94: :logic,
      __VdfgRegularize_hca2350fd_0_95: :logic,
      __VdfgRegularize_hca2350fd_0_96: :logic,
      __VdfgRegularize_hca2350fd_0_97: :logic,
      __VdfgRegularize_hca2350fd_0_98: :logic,
      __VdfgRegularize_hca2350fd_0_99: :logic,
      __VdfgRegularize_hca2350fd_1_0: :logic,
      _unused_ok: :wire,
      cond_0: :wire,
      cond_1: :wire,
      cond_10: :wire,
      cond_100: :wire,
      cond_101: :wire,
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
      cond_112: :wire,
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
      cond_144: :wire,
      cond_145: :wire,
      cond_146: :wire,
      cond_147: :wire,
      cond_148: :wire,
      cond_149: :wire,
      cond_15: :wire,
      cond_150: :wire,
      cond_151: :wire,
      cond_152: :wire,
      cond_153: :wire,
      cond_154: :wire,
      cond_155: :wire,
      cond_156: :wire,
      cond_157: :wire,
      cond_158: :wire,
      cond_159: :wire,
      cond_16: :wire,
      cond_160: :wire,
      cond_161: :wire,
      cond_162: :wire,
      cond_163: :wire,
      cond_164: :wire,
      cond_165: :wire,
      cond_166: :wire,
      cond_167: :wire,
      cond_168: :wire,
      cond_169: :wire,
      cond_17: :wire,
      cond_170: :wire,
      cond_171: :wire,
      cond_172: :wire,
      cond_173: :wire,
      cond_174: :wire,
      cond_175: :wire,
      cond_176: :wire,
      cond_177: :wire,
      cond_178: :wire,
      cond_179: :wire,
      cond_18: :wire,
      cond_180: :wire,
      cond_181: :wire,
      cond_182: :wire,
      cond_183: :wire,
      cond_184: :wire,
      cond_185: :wire,
      cond_186: :wire,
      cond_187: :wire,
      cond_188: :wire,
      cond_189: :wire,
      cond_19: :wire,
      cond_190: :wire,
      cond_191: :wire,
      cond_192: :wire,
      cond_193: :wire,
      cond_194: :wire,
      cond_195: :wire,
      cond_196: :wire,
      cond_197: :wire,
      cond_198: :wire,
      cond_199: :wire,
      cond_2: :wire,
      cond_20: :wire,
      cond_200: :wire,
      cond_201: :wire,
      cond_202: :wire,
      cond_203: :wire,
      cond_204: :wire,
      cond_205: :wire,
      cond_206: :wire,
      cond_207: :wire,
      cond_208: :wire,
      cond_209: :wire,
      cond_21: :wire,
      cond_210: :wire,
      cond_211: :wire,
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
      cond_4: :wire,
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
      cond_99: :wire,
      mc_saved_cmdex: :reg,
      mc_saved_cmdex_to_reg: :wire,
      mc_saved_command: :reg,
      mc_saved_command_to_reg: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :protected_mode
  input :real_mode
  input :v8086_mode
  input :io_allow_check_needed
  input :exc_push_error
  input :cr0_pg
  input :oflag
  input :ntflag
  input :cpl, width: 2
  input :glob_param_1, width: 32
  input :glob_param_3, width: 32
  input :glob_descriptor, width: 64
  input :mc_operand_32bit
  input :mc_cmd, width: 7
  input :mc_decoder, width: 88
  input :mc_step, width: 6
  input :mc_cmdex_last, width: 4
  output :mc_cmd_next, width: 7
  output :mc_cmd_current, width: 7
  output :mc_cmdex_current, width: 4

  # Signals

  signal :__VdfgRegularize_hca2350fd_0_0
  signal :__VdfgRegularize_hca2350fd_0_1
  signal :__VdfgRegularize_hca2350fd_0_10
  signal :__VdfgRegularize_hca2350fd_0_100
  signal :__VdfgRegularize_hca2350fd_0_101, width: 7
  signal :__VdfgRegularize_hca2350fd_0_102, width: 4
  signal :__VdfgRegularize_hca2350fd_0_103
  signal :__VdfgRegularize_hca2350fd_0_104
  signal :__VdfgRegularize_hca2350fd_0_106
  signal :__VdfgRegularize_hca2350fd_0_107
  signal :__VdfgRegularize_hca2350fd_0_108
  signal :__VdfgRegularize_hca2350fd_0_11
  signal :__VdfgRegularize_hca2350fd_0_12
  signal :__VdfgRegularize_hca2350fd_0_13
  signal :__VdfgRegularize_hca2350fd_0_14
  signal :__VdfgRegularize_hca2350fd_0_15
  signal :__VdfgRegularize_hca2350fd_0_16
  signal :__VdfgRegularize_hca2350fd_0_17
  signal :__VdfgRegularize_hca2350fd_0_18
  signal :__VdfgRegularize_hca2350fd_0_19
  signal :__VdfgRegularize_hca2350fd_0_2
  signal :__VdfgRegularize_hca2350fd_0_20
  signal :__VdfgRegularize_hca2350fd_0_21
  signal :__VdfgRegularize_hca2350fd_0_22
  signal :__VdfgRegularize_hca2350fd_0_23
  signal :__VdfgRegularize_hca2350fd_0_24
  signal :__VdfgRegularize_hca2350fd_0_25
  signal :__VdfgRegularize_hca2350fd_0_26
  signal :__VdfgRegularize_hca2350fd_0_27
  signal :__VdfgRegularize_hca2350fd_0_28
  signal :__VdfgRegularize_hca2350fd_0_29
  signal :__VdfgRegularize_hca2350fd_0_3
  signal :__VdfgRegularize_hca2350fd_0_30
  signal :__VdfgRegularize_hca2350fd_0_31
  signal :__VdfgRegularize_hca2350fd_0_32
  signal :__VdfgRegularize_hca2350fd_0_33
  signal :__VdfgRegularize_hca2350fd_0_34
  signal :__VdfgRegularize_hca2350fd_0_35
  signal :__VdfgRegularize_hca2350fd_0_36
  signal :__VdfgRegularize_hca2350fd_0_37
  signal :__VdfgRegularize_hca2350fd_0_38
  signal :__VdfgRegularize_hca2350fd_0_39
  signal :__VdfgRegularize_hca2350fd_0_4
  signal :__VdfgRegularize_hca2350fd_0_40
  signal :__VdfgRegularize_hca2350fd_0_41
  signal :__VdfgRegularize_hca2350fd_0_42
  signal :__VdfgRegularize_hca2350fd_0_43
  signal :__VdfgRegularize_hca2350fd_0_44
  signal :__VdfgRegularize_hca2350fd_0_45
  signal :__VdfgRegularize_hca2350fd_0_46
  signal :__VdfgRegularize_hca2350fd_0_47
  signal :__VdfgRegularize_hca2350fd_0_48
  signal :__VdfgRegularize_hca2350fd_0_49
  signal :__VdfgRegularize_hca2350fd_0_5
  signal :__VdfgRegularize_hca2350fd_0_50
  signal :__VdfgRegularize_hca2350fd_0_51
  signal :__VdfgRegularize_hca2350fd_0_52
  signal :__VdfgRegularize_hca2350fd_0_53
  signal :__VdfgRegularize_hca2350fd_0_54
  signal :__VdfgRegularize_hca2350fd_0_55
  signal :__VdfgRegularize_hca2350fd_0_56
  signal :__VdfgRegularize_hca2350fd_0_57
  signal :__VdfgRegularize_hca2350fd_0_58
  signal :__VdfgRegularize_hca2350fd_0_59
  signal :__VdfgRegularize_hca2350fd_0_6
  signal :__VdfgRegularize_hca2350fd_0_60
  signal :__VdfgRegularize_hca2350fd_0_61
  signal :__VdfgRegularize_hca2350fd_0_62
  signal :__VdfgRegularize_hca2350fd_0_63
  signal :__VdfgRegularize_hca2350fd_0_64
  signal :__VdfgRegularize_hca2350fd_0_65
  signal :__VdfgRegularize_hca2350fd_0_66
  signal :__VdfgRegularize_hca2350fd_0_67
  signal :__VdfgRegularize_hca2350fd_0_68
  signal :__VdfgRegularize_hca2350fd_0_69
  signal :__VdfgRegularize_hca2350fd_0_7
  signal :__VdfgRegularize_hca2350fd_0_70
  signal :__VdfgRegularize_hca2350fd_0_71
  signal :__VdfgRegularize_hca2350fd_0_72
  signal :__VdfgRegularize_hca2350fd_0_73
  signal :__VdfgRegularize_hca2350fd_0_74
  signal :__VdfgRegularize_hca2350fd_0_75
  signal :__VdfgRegularize_hca2350fd_0_76
  signal :__VdfgRegularize_hca2350fd_0_77
  signal :__VdfgRegularize_hca2350fd_0_78
  signal :__VdfgRegularize_hca2350fd_0_79
  signal :__VdfgRegularize_hca2350fd_0_8
  signal :__VdfgRegularize_hca2350fd_0_80
  signal :__VdfgRegularize_hca2350fd_0_81
  signal :__VdfgRegularize_hca2350fd_0_82
  signal :__VdfgRegularize_hca2350fd_0_83
  signal :__VdfgRegularize_hca2350fd_0_84
  signal :__VdfgRegularize_hca2350fd_0_85
  signal :__VdfgRegularize_hca2350fd_0_86
  signal :__VdfgRegularize_hca2350fd_0_87
  signal :__VdfgRegularize_hca2350fd_0_88
  signal :__VdfgRegularize_hca2350fd_0_89
  signal :__VdfgRegularize_hca2350fd_0_9
  signal :__VdfgRegularize_hca2350fd_0_90
  signal :__VdfgRegularize_hca2350fd_0_91
  signal :__VdfgRegularize_hca2350fd_0_92
  signal :__VdfgRegularize_hca2350fd_0_93
  signal :__VdfgRegularize_hca2350fd_0_94
  signal :__VdfgRegularize_hca2350fd_0_95
  signal :__VdfgRegularize_hca2350fd_0_96
  signal :__VdfgRegularize_hca2350fd_0_97
  signal :__VdfgRegularize_hca2350fd_0_98
  signal :__VdfgRegularize_hca2350fd_0_99
  signal :__VdfgRegularize_hca2350fd_1_0
  signal :_unused_ok
  signal :cond_0
  signal :cond_1
  signal :cond_10
  signal :cond_100
  signal :cond_101
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
  signal :cond_112
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
  signal :cond_144
  signal :cond_145
  signal :cond_146
  signal :cond_147
  signal :cond_148
  signal :cond_149
  signal :cond_15
  signal :cond_150
  signal :cond_151
  signal :cond_152
  signal :cond_153
  signal :cond_154
  signal :cond_155
  signal :cond_156
  signal :cond_157
  signal :cond_158
  signal :cond_159
  signal :cond_16
  signal :cond_160
  signal :cond_161
  signal :cond_162
  signal :cond_163
  signal :cond_164
  signal :cond_165
  signal :cond_166
  signal :cond_167
  signal :cond_168
  signal :cond_169
  signal :cond_17
  signal :cond_170
  signal :cond_171
  signal :cond_172
  signal :cond_173
  signal :cond_174
  signal :cond_175
  signal :cond_176
  signal :cond_177
  signal :cond_178
  signal :cond_179
  signal :cond_18
  signal :cond_180
  signal :cond_181
  signal :cond_182
  signal :cond_183
  signal :cond_184
  signal :cond_185
  signal :cond_186
  signal :cond_187
  signal :cond_188
  signal :cond_189
  signal :cond_19
  signal :cond_190
  signal :cond_191
  signal :cond_192
  signal :cond_193
  signal :cond_194
  signal :cond_195
  signal :cond_196
  signal :cond_197
  signal :cond_198
  signal :cond_199
  signal :cond_2
  signal :cond_20
  signal :cond_200
  signal :cond_201
  signal :cond_202
  signal :cond_203
  signal :cond_204
  signal :cond_205
  signal :cond_206
  signal :cond_207
  signal :cond_208
  signal :cond_209
  signal :cond_21
  signal :cond_210
  signal :cond_211
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
  signal :cond_4
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
  signal :mc_saved_cmdex, width: 4
  signal :mc_saved_cmdex_to_reg, width: 4
  signal :mc_saved_command, width: 7
  signal :mc_saved_command_to_reg, width: 7

  # Assignments

  assign :cond_0,
    (
        (
            lit(1, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_0,
    (
        lit(0, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_1,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_1,
    (
        lit(3, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_2,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_2,
    (
        lit(1, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_3,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_3,
    (
        lit(2, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_4,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_4,
    (
        lit(3, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_5,
    (
        sig(:__VdfgRegularize_hca2350fd_0_8, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_9, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_8,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_7, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_9,
    (
        sig(:real_mode, width: 1) |
        sig(:v8086_mode, width: 1)
    )
  assign :cond_6,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_10,
    (
        lit(7, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_7,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_11,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_8,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_12,
    (
        lit(9, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_9,
    (
        sig(:__VdfgRegularize_hca2350fd_0_8, width: 1) &
        sig(:protected_mode, width: 1)
    )
  assign :cond_10,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_13, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_13,
    (
        lit(11, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_11,
    (
        sig(:__VdfgRegularize_hca2350fd_0_15, width: 1) &
        sig(:glob_descriptor, width: 64)[44]
    )
  assign :__VdfgRegularize_hca2350fd_0_15,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_14, width: 1)
    )
  assign :cond_12,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_16, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_16,
    (
        lit(13, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_13,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_17, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_17,
    (
        lit(14, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_14,
    (
        sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_18, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_18,
    (
        lit(15, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_15,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_19,
    (
        lit(4, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_16,
    (
        sig(:__VdfgRegularize_hca2350fd_0_108, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_21, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_108,
    (
        sig(:__VdfgRegularize_hca2350fd_0_20, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_15, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_21,
    (
        (
            lit(9, width: 4, base: "h", signed: false) ==
            sig(:glob_descriptor, width: 64)[43..40]
        ) |
        (
            lit(1, width: 4, base: "h", signed: false) ==
            sig(:glob_descriptor, width: 64)[43..40]
        )
    )
  assign :cond_17,
    (
        sig(:__VdfgRegularize_hca2350fd_0_22, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_23, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_22,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_23,
    (
        lit(0, width: 4, base: "h", signed: false) ==
        sig(:glob_param_3, width: 32)[21..18]
    )
  assign :cond_18,
    (
        sig(:__VdfgRegularize_hca2350fd_0_22, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_24, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_24,
    (
        lit(0, width: 4, base: "h", signed: false) !=
        sig(:glob_param_3, width: 32)[21..18]
    )
  assign :cond_19,
    (
        sig(:__VdfgRegularize_hca2350fd_0_108, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_25, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_25,
    (
        lit(5, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :cond_20,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_21,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_26,
    (
        lit(4, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_22,
    (
        sig(:__VdfgRegularize_hca2350fd_0_108, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_27, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_27,
    (
        (
            lit(12, width: 4, base: "h", signed: false) ==
            sig(:glob_descriptor, width: 64)[43..40]
        ) |
        (
            lit(4, width: 4, base: "h", signed: false) ==
            sig(:glob_descriptor, width: 64)[43..40]
        )
    )
  assign :cond_23,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_5,
    (
        lit(5, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_24,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_6,
    (
        lit(6, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_25,
    (
        sig(:__VdfgRegularize_hca2350fd_0_28, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_107, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_28,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_107,
    (
        (
          ~sig(:glob_descriptor, width: 64)[42]
        ) &
        (
            sig(:glob_descriptor, width: 64)[43] &
            (
                sig(:glob_descriptor, width: 64)[46..45] <
                sig(:cpl, width: 2)
            )
        )
    )
  assign :cond_26,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_14, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_14,
    (
        lit(12, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_27,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_16, width: 1)
    )
  assign :cond_28,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_17, width: 1)
    )
  assign :cond_29,
    (
        sig(:__VdfgRegularize_hca2350fd_0_29, width: 1) &
        (
            lit(0, width: 5, base: "h", signed: false) !=
            sig(:glob_param_3, width: 32)[24..20]
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_29,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_18, width: 1)
    )
  assign :cond_30,
    (
        sig(:__VdfgRegularize_hca2350fd_0_31, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_32, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_31,
    (
        sig(:__VdfgRegularize_hca2350fd_0_30, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_32,
    (
        lit(1, width: 5, base: "h", signed: false) ==
        sig(:glob_param_3, width: 32)[24..20]
    )
  assign :cond_31,
    (
        sig(:__VdfgRegularize_hca2350fd_0_31, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_33, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_33,
    (
        lit(1, width: 5, base: "h", signed: false) !=
        sig(:glob_param_3, width: 32)[24..20]
    )
  assign :cond_32,
    (
        sig(:__VdfgRegularize_hca2350fd_0_34, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_32, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_34,
    (
        sig(:__VdfgRegularize_hca2350fd_0_30, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_33,
    (
        sig(:__VdfgRegularize_hca2350fd_0_34, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_33, width: 1)
    )
  assign :cond_34,
    (
        sig(:__VdfgRegularize_hca2350fd_0_29, width: 1) &
        (
            lit(0, width: 5, base: "h", signed: false) ==
            sig(:glob_param_3, width: 32)[24..20]
        )
    )
  assign :cond_35,
    (
        sig(:__VdfgRegularize_hca2350fd_0_30, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_30,
    (
        lit(5, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_36,
    (
        sig(:__VdfgRegularize_hca2350fd_0_30, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_37,
    (
        sig(:__VdfgRegularize_hca2350fd_0_30, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_38,
    (
        sig(:__VdfgRegularize_hca2350fd_0_30, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
    )
  assign :cond_39,
    (
        sig(:__VdfgRegularize_hca2350fd_0_35, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_28, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_35,
    (
      ~sig(:__VdfgRegularize_hca2350fd_0_107, width: 1)
    )
  assign :cond_40,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :cond_41,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_42,
    (
        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_36,
    (
        lit(10, width: 4, base: "h", signed: false) ==
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_43,
    (
        sig(:__VdfgRegularize_hca2350fd_0_37, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_37,
    (
        lit(9, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_44,
    (
        sig(:__VdfgRegularize_hca2350fd_0_37, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_45,
    (
        sig(:__VdfgRegularize_hca2350fd_0_38, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_38,
    (
        lit(10, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_46,
    (
        sig(:__VdfgRegularize_hca2350fd_0_38, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_47,
    (
        sig(:__VdfgRegularize_hca2350fd_0_39, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_39,
    (
        lit(11, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_48,
    (
        sig(:__VdfgRegularize_hca2350fd_0_39, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_49,
    (
        sig(:__VdfgRegularize_hca2350fd_0_40, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_40,
    (
        lit(15, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_50,
    (
        sig(:__VdfgRegularize_hca2350fd_0_40, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :cond_51,
    (
        sig(:__VdfgRegularize_hca2350fd_0_41, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_41,
    (
        lit(18, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_52,
    (
        sig(:__VdfgRegularize_hca2350fd_0_41, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_53,
    (
        sig(:__VdfgRegularize_hca2350fd_0_41, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_54,
    (
        sig(:__VdfgRegularize_hca2350fd_0_106, width: 1) &
        (
            lit(1, width: 4, base: "h", signed: false) !=
            sig(:mc_cmdex_last, width: 4)
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_106,
    (
        (
            lit(19, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) |
        (
            (
                lit(20, width: 7, base: "h", signed: false) ==
                sig(:mc_cmd, width: 7)
            ) |
            (
                lit(21, width: 7, base: "h", signed: false) ==
                sig(:mc_cmd, width: 7)
            )
        )
    )
  assign :cond_55,
    (
        sig(:__VdfgRegularize_hca2350fd_0_106, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_56,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_42,
    (
        lit(28, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_57,
    (
        sig(:__VdfgRegularize_hca2350fd_0_43, width: 1) &
        sig(:real_mode, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_43,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_58,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_59,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_60,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_61,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
    )
  assign :cond_62,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
    )
  assign :cond_63,
    (
        (
          ~sig(:real_mode, width: 1)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_43, width: 1)
    )
  assign :cond_64,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :cond_65,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_66,
    (
        sig(:__VdfgRegularize_hca2350fd_0_44, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_25, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_44,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
    )
  assign :cond_67,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_13, width: 1)
    )
  assign :cond_68,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_14, width: 1)
    )
  assign :cond_69,
    (
        sig(:__VdfgRegularize_hca2350fd_0_44, width: 1) &
        (
            lit(5, width: 4, base: "h", signed: false) !=
            sig(:glob_descriptor, width: 64)[43..40]
        )
    )
  assign :cond_70,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_16, width: 1)
    )
  assign :cond_71,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_17, width: 1)
    )
  assign :cond_72,
    (
        sig(:__VdfgRegularize_hca2350fd_0_45, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_107, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_45,
    (
        sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_18, width: 1)
    )
  assign :cond_73,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_46,
    (
        lit(29, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_74,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
    )
  assign :cond_75,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :cond_76,
    (
        sig(:__VdfgRegularize_hca2350fd_0_47, width: 1) &
        sig(:v8086_mode, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_47,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_77,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
    )
  assign :cond_78,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_13, width: 1)
    )
  assign :cond_79,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_14, width: 1)
    )
  assign :cond_80,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_16, width: 1)
    )
  assign :cond_81,
    (
        (
          ~sig(:v8086_mode, width: 1)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_47, width: 1)
    )
  assign :cond_82,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_17, width: 1)
    )
  assign :cond_83,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_18, width: 1)
    )
  assign :cond_84,
    (
        sig(:__VdfgRegularize_hca2350fd_0_48, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_48,
    (
        lit(30, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_85,
    (
        sig(:__VdfgRegularize_hca2350fd_0_48, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_86,
    (
        sig(:__VdfgRegularize_hca2350fd_0_49, width: 1) &
        sig(:exc_push_error, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_49,
    (
        sig(:__VdfgRegularize_hca2350fd_0_48, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_87,
    (
        sig(:__VdfgRegularize_hca2350fd_0_48, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_88,
    (
        sig(:__VdfgRegularize_hca2350fd_0_50, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_49, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_50,
    (
      ~sig(:exc_push_error, width: 1)
    )
  assign :cond_89,
    (
        sig(:__VdfgRegularize_hca2350fd_0_48, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_90,
    (
        sig(:__VdfgRegularize_hca2350fd_0_48, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
    )
  assign :cond_91,
    (
        sig(:__VdfgRegularize_hca2350fd_0_35, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_45, width: 1)
    )
  assign :cond_92,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :cond_93,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_94,
    (
        sig(:__VdfgRegularize_hca2350fd_0_51, width: 1) &
        sig(:exc_push_error, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_51,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_95,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_96,
    (
        sig(:__VdfgRegularize_hca2350fd_0_50, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_51, width: 1)
    )
  assign :cond_97,
    (
        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_98,
    (
        sig(:__VdfgRegularize_hca2350fd_0_52, width: 1) &
        (
            (
              ~sig(:protected_mode, width: 1)
            ) |
            (
                sig(:protected_mode, width: 1) &
                sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_52,
    (
        lit(33, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_99,
    (
        sig(:__VdfgRegularize_hca2350fd_0_52, width: 1) &
        (
            sig(:protected_mode, width: 1) &
            sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
        )
    )
  assign :cond_100,
    (
        sig(:__VdfgRegularize_hca2350fd_0_53, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_53,
    (
        lit(34, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_101,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_54,
    (
        lit(35, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_102,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_103,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_104,
    (
        sig(:__VdfgRegularize_hca2350fd_0_55, width: 1) &
        sig(:ntflag, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_55,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_105,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
    )
  assign :cond_106,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
    )
  assign :cond_107,
    (
        (
          ~sig(:ntflag, width: 1)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_55, width: 1)
    )
  assign :cond_108,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
    )
  assign :cond_109,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :cond_110,
    (
        sig(:__VdfgRegularize_hca2350fd_0_56, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_1_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_56,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_111,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        (
            (
                lit(10, width: 4, base: "h", signed: false) <=
                sig(:mc_cmdex_last, width: 4)
            ) &
            sig(:__VdfgRegularize_hca2350fd_0_57, width: 1)
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_57,
    (
        lit(15, width: 4, base: "h", signed: false) >
        sig(:mc_cmdex_last, width: 4)
    )
  assign :cond_112,
    (
        sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_18, width: 1)
    )
  assign :cond_113,
    (
        sig(:__VdfgRegularize_hca2350fd_0_58, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_58,
    (
        lit(40, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_114,
    (
        (
          ~sig(:__VdfgRegularize_hca2350fd_1_0, width: 1)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_56, width: 1)
    )
  assign :cond_115,
    (
        sig(:__VdfgRegularize_hca2350fd_0_58, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_116,
    (
        sig(:__VdfgRegularize_hca2350fd_0_58, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_117,
    (
        sig(:__VdfgRegularize_hca2350fd_0_58, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_118,
    (
        sig(:__VdfgRegularize_hca2350fd_0_58, width: 1) &
        (
            (
                lit(4, width: 4, base: "h", signed: false) <=
                sig(:mc_cmdex_last, width: 4)
            ) &
            (
                lit(9, width: 4, base: "h", signed: false) >
                sig(:mc_cmdex_last, width: 4)
            )
        )
    )
  assign :cond_119,
    (
        sig(:__VdfgRegularize_hca2350fd_0_58, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_120,
    (
        (
            lit(41, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_121,
    (
        sig(:__VdfgRegularize_hca2350fd_0_59, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_59,
    (
        lit(45, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_122,
    (
        sig(:__VdfgRegularize_hca2350fd_0_59, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_123,
    (
        sig(:__VdfgRegularize_hca2350fd_0_60, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_60,
    (
        lit(46, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_124,
    (
        sig(:__VdfgRegularize_hca2350fd_0_60, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_125,
    (
        sig(:__VdfgRegularize_hca2350fd_0_61, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_61,
    (
        (
            lit(47, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) |
        (
            lit(48, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        )
    )
  assign :cond_126,
    (
        sig(:__VdfgRegularize_hca2350fd_0_61, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_127,
    (
        sig(:__VdfgRegularize_hca2350fd_0_61, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
    )
  assign :cond_128,
    (
        sig(:__VdfgRegularize_hca2350fd_0_62, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_63, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_62,
    (
        lit(49, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :__VdfgRegularize_hca2350fd_0_63,
    (
        lit(7, width: 6, base: "h", signed: false) >
        sig(:mc_step, width: 6)
    )
  assign :cond_129,
    (
        sig(:__VdfgRegularize_hca2350fd_0_62, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_64, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_64,
    (
        lit(7, width: 6, base: "h", signed: false) ==
        sig(:mc_step, width: 6)
    )
  assign :cond_130,
    (
        sig(:__VdfgRegularize_hca2350fd_0_65, width: 1) &
        (
            (
                sig(:__VdfgRegularize_hca2350fd_0_66, width: 1) &
                (
                    lit(0, width: 5, base: "h", signed: false) ==
                    sig(:mc_decoder, width: 88)[28..24]
                )
            ) |
            (
                (
                    (
                        lit(2, width: 6, base: "h", signed: false) ==
                        sig(:mc_step, width: 6)
                    ) &
                    sig(:__VdfgRegularize_hca2350fd_0_67, width: 1)
                ) |
                (
                    (
                        sig(:mc_step, width: 6) >
                        lit(0, width: 1, base: "d", signed: false).concat(
                        sig(:mc_decoder, width: 88)[28..24]
                      )
                    ) &
                    sig(:__VdfgRegularize_hca2350fd_0_68, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_65,
    (
        lit(53, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :__VdfgRegularize_hca2350fd_0_66,
    (
        lit(1, width: 6, base: "h", signed: false) ==
        sig(:mc_step, width: 6)
    )
  assign :__VdfgRegularize_hca2350fd_0_67,
    (
        lit(1, width: 5, base: "h", signed: false) ==
        sig(:mc_decoder, width: 88)[28..24]
    )
  assign :__VdfgRegularize_hca2350fd_0_68,
    (
        lit(1, width: 5, base: "h", signed: false) <
        sig(:mc_decoder, width: 88)[28..24]
    )
  assign :cond_131,
    (
        sig(:__VdfgRegularize_hca2350fd_0_65, width: 1) &
        (
            (
                sig(:__VdfgRegularize_hca2350fd_0_66, width: 1) &
                sig(:__VdfgRegularize_hca2350fd_0_67, width: 1)
            ) |
            (
                (
                    sig(:mc_step, width: 6) ==
                    lit(0, width: 1, base: "d", signed: false).concat(
                    sig(:mc_decoder, width: 88)[28..24]
                  )
                ) &
                sig(:__VdfgRegularize_hca2350fd_0_68, width: 1)
            )
        )
    )
  assign :cond_132,
    (
        sig(:__VdfgRegularize_hca2350fd_0_65, width: 1) &
        (
            (
                sig(:mc_step, width: 6) <
                lit(0, width: 1, base: "d", signed: false).concat(
                sig(:mc_decoder, width: 88)[28..24]
              )
            ) &
            sig(:__VdfgRegularize_hca2350fd_0_68, width: 1)
        )
    )
  assign :cond_133,
    (
        sig(:__VdfgRegularize_hca2350fd_0_69, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_69,
    (
        lit(58, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_134,
    (
        sig(:__VdfgRegularize_hca2350fd_0_69, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_135,
    (
        sig(:__VdfgRegularize_hca2350fd_0_70, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_70,
    (
        lit(62, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_136,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_71,
    (
        lit(63, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_137,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_138,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_139,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_140,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
    )
  assign :cond_141,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
    )
  assign :cond_142,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :cond_143,
    (
        sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_144,
    (
        (
            lit(73, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_145,
    (
        sig(:__VdfgRegularize_hca2350fd_0_72, width: 1) &
        (
            sig(:__VdfgRegularize_hca2350fd_0_73, width: 1) |
            sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_72,
    (
        lit(75, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :__VdfgRegularize_hca2350fd_0_73,
    (
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1) |
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_146,
    (
        sig(:__VdfgRegularize_hca2350fd_0_74, width: 1) &
        sig(:oflag, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_74,
    (
        sig(:__VdfgRegularize_hca2350fd_0_72, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_147,
    (
        (
          ~sig(:oflag, width: 1)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_74, width: 1)
    )
  assign :cond_148,
    (
        sig(:__VdfgRegularize_hca2350fd_0_77, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_76, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_77,
    (
      ~sig(:io_allow_check_needed, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_76,
    (
        sig(:__VdfgRegularize_hca2350fd_0_75, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_73, width: 1)
    )
  assign :cond_149,
    (
        sig(:__VdfgRegularize_hca2350fd_0_76, width: 1) &
        sig(:io_allow_check_needed, width: 1)
    )
  assign :cond_150,
    (
        sig(:__VdfgRegularize_hca2350fd_0_75, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_75,
    (
        lit(77, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_151,
    (
        sig(:__VdfgRegularize_hca2350fd_0_104, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_104,
    (
        (
            lit(79, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) |
        (
            (
                lit(80, width: 7, base: "h", signed: false) ==
                sig(:mc_cmd, width: 7)
            ) |
            (
                (
                    lit(81, width: 7, base: "h", signed: false) ==
                    sig(:mc_cmd, width: 7)
                ) |
                (
                    lit(82, width: 7, base: "h", signed: false) ==
                    sig(:mc_cmd, width: 7)
                )
            )
        )
    )
  assign :cond_152,
    (
        sig(:__VdfgRegularize_hca2350fd_0_104, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_153,
    (
        sig(:__VdfgRegularize_hca2350fd_0_77, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_79, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_79,
    (
        sig(:__VdfgRegularize_hca2350fd_0_78, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :cond_154,
    (
        sig(:__VdfgRegularize_hca2350fd_0_78, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_78,
    (
        lit(84, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_155,
    (
        sig(:__VdfgRegularize_hca2350fd_0_79, width: 1) &
        sig(:io_allow_check_needed, width: 1)
    )
  assign :cond_156,
    (
        sig(:__VdfgRegularize_hca2350fd_0_78, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_157,
    (
        sig(:__VdfgRegularize_hca2350fd_0_78, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_158,
    (
        sig(:__VdfgRegularize_hca2350fd_0_77, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_81, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_81,
    (
        sig(:__VdfgRegularize_hca2350fd_0_80, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :cond_159,
    (
        sig(:__VdfgRegularize_hca2350fd_0_81, width: 1) &
        sig(:io_allow_check_needed, width: 1)
    )
  assign :cond_160,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_82,
    (
        lit(87, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_161,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :cond_162,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_163,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :cond_164,
    (
        sig(:__VdfgRegularize_hca2350fd_0_83, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_9, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_83,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_7, width: 1)
    )
  assign :cond_165,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
    )
  assign :cond_166,
    (
        sig(:__VdfgRegularize_hca2350fd_0_83, width: 1) &
        sig(:protected_mode, width: 1)
    )
  assign :cond_167,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_168,
    (
        sig(:__VdfgRegularize_hca2350fd_0_84, width: 1) &
        sig(:glob_descriptor, width: 64)[44]
    )
  assign :__VdfgRegularize_hca2350fd_0_84,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
    )
  assign :cond_169,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_13, width: 1)
    )
  assign :cond_170,
    (
        sig(:__VdfgRegularize_hca2350fd_0_103, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_21, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_103,
    (
        sig(:__VdfgRegularize_hca2350fd_0_20, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_84, width: 1)
    )
  assign :cond_171,
    (
        sig(:__VdfgRegularize_hca2350fd_0_85, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_23, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_85,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_16, width: 1)
    )
  assign :cond_172,
    (
        sig(:__VdfgRegularize_hca2350fd_0_85, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_24, width: 1)
    )
  assign :cond_173,
    (
        sig(:__VdfgRegularize_hca2350fd_0_103, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_25, width: 1)
    )
  assign :cond_174,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_17, width: 1)
    )
  assign :cond_175,
    (
        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_18, width: 1)
    )
  assign :cond_176,
    (
        sig(:__VdfgRegularize_hca2350fd_0_103, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_27, width: 1)
    )
  assign :cond_177,
    (
        sig(:__VdfgRegularize_hca2350fd_0_86, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_86,
    (
        lit(88, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_178,
    (
        sig(:__VdfgRegularize_hca2350fd_0_86, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_179,
    (
        sig(:__VdfgRegularize_hca2350fd_0_86, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :cond_180,
    (
        sig(:__VdfgRegularize_hca2350fd_0_77, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_88, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_88,
    (
        sig(:__VdfgRegularize_hca2350fd_0_87, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_73, width: 1)
    )
  assign :cond_181,
    (
        sig(:__VdfgRegularize_hca2350fd_0_88, width: 1) &
        sig(:io_allow_check_needed, width: 1)
    )
  assign :cond_182,
    (
        sig(:__VdfgRegularize_hca2350fd_0_87, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_87,
    (
        lit(89, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_183,
    (
        sig(:__VdfgRegularize_hca2350fd_0_89, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_89,
    (
        lit(94, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_184,
    (
        (
            lit(97, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
    )
  assign :cond_185,
    (
        sig(:__VdfgRegularize_hca2350fd_0_91, width: 1) &
        sig(:cr0_pg, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_91,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :cond_186,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_90,
    (
        lit(99, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_187,
    (
        sig(:__VdfgRegularize_hca2350fd_0_92, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_93, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_92,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_93,
    (
        (
            lit(2, width: 2, base: "h", signed: false) ==
            sig(:glob_param_1, width: 32)[17..16]
        ) |
        (
            lit(1, width: 2, base: "h", signed: false) ==
            sig(:glob_param_1, width: 32)[17..16]
        )
    )
  assign :cond_188,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
    )
  assign :cond_189,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
    )
  assign :cond_190,
    (
        (
          ~sig(:__VdfgRegularize_hca2350fd_0_93, width: 1)
        ) &
        sig(:__VdfgRegularize_hca2350fd_0_92, width: 1)
    )
  assign :cond_191,
    (
        sig(:__VdfgRegularize_hca2350fd_0_94, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_91, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_94,
    (
      ~sig(:cr0_pg, width: 1)
    )
  assign :cond_192,
    (
        sig(:__VdfgRegularize_hca2350fd_0_95, width: 1) &
        sig(:cr0_pg, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_95,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
    )
  assign :cond_193,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
    )
  assign :cond_194,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
    )
  assign :cond_195,
    (
        sig(:__VdfgRegularize_hca2350fd_0_94, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_95, width: 1)
    )
  assign :cond_196,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_12, width: 1)
    )
  assign :cond_197,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
    )
  assign :cond_198,
    (
        sig(:__VdfgRegularize_hca2350fd_0_96, width: 1) &
        (
            lit(13, width: 4, base: "h", signed: false) >
            sig(:mc_cmdex_last, width: 4)
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_96,
    (
        lit(100, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_199,
    (
        sig(:__VdfgRegularize_hca2350fd_0_96, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_16, width: 1)
    )
  assign :cond_200,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_13, width: 1)
    )
  assign :cond_201,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_14, width: 1)
    )
  assign :cond_202,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_16, width: 1)
    )
  assign :cond_203,
    (
        sig(:__VdfgRegularize_hca2350fd_0_90, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_17, width: 1)
    )
  assign :cond_204,
    (
        sig(:__VdfgRegularize_hca2350fd_0_97, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_57, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_97,
    (
        lit(101, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_205,
    (
        sig(:__VdfgRegularize_hca2350fd_0_97, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_18, width: 1)
    )
  assign :cond_206,
    (
        (
            lit(102, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) &
        (
            lit(10, width: 4, base: "h", signed: false) >
            sig(:mc_cmdex_last, width: 4)
        )
    )
  assign :cond_207,
    (
        (
            lit(104, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        ) |
        (
            lit(105, width: 7, base: "h", signed: false) ==
            sig(:mc_cmd, width: 7)
        )
    )
  assign :cond_208,
    (
        sig(:__VdfgRegularize_hca2350fd_0_98, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_63, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_98,
    (
        lit(109, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_209,
    (
        sig(:__VdfgRegularize_hca2350fd_0_98, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_64, width: 1)
    )
  assign :cond_210,
    (
        sig(:__VdfgRegularize_hca2350fd_0_99, width: 1) &
        sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_99,
    (
        lit(110, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :cond_211,
    (
        (
            sig(:__VdfgRegularize_hca2350fd_0_1, width: 1) &
            (
                sig(:__VdfgRegularize_hca2350fd_0_26, width: 1) |
                sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
            )
        ) |
        (
            (
                sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
                sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
            ) |
            (
                (
                    sig(:__VdfgRegularize_hca2350fd_0_30, width: 1) &
                    sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgRegularize_hca2350fd_0_19, width: 1) &
                        sig(:__VdfgRegularize_hca2350fd_0_13, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_hca2350fd_0_37, width: 1) &
                            sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
                        ) |
                        (
                            (
                                sig(:__VdfgRegularize_hca2350fd_0_38, width: 1) &
                                sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
                            ) |
                            (
                                (
                                    (
                                        lit(12, width: 7, base: "h", signed: false) ==
                                        sig(:mc_cmd, width: 7)
                                    ) &
                                    sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
                                ) |
                                (
                                    (
                                        (
                                            lit(13, width: 7, base: "h", signed: false) ==
                                            sig(:mc_cmd, width: 7)
                                        ) &
                                        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
                                    ) |
                                    (
                                        (
                                            sig(:__VdfgRegularize_hca2350fd_0_41, width: 1) &
                                            sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
                                        ) |
                                        (
                                            (
                                                sig(:__VdfgRegularize_hca2350fd_0_42, width: 1) &
                                                sig(:__VdfgRegularize_hca2350fd_0_10, width: 1)
                                            ) |
                                            (
                                                (
                                                    sig(:__VdfgRegularize_hca2350fd_0_48, width: 1) &
                                                    sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
                                                ) |
                                                (
                                                    (
                                                        sig(:__VdfgRegularize_hca2350fd_0_46, width: 1) &
                                                        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
                                                    ) |
                                                    (
                                                        (
                                                            sig(:__VdfgRegularize_hca2350fd_0_53, width: 1) &
                                                            sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
                                                        ) |
                                                        (
                                                            (
                                                                sig(:__VdfgRegularize_hca2350fd_0_54, width: 1) &
                                                                sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
                                                            ) |
                                                            (
                                                                (
                                                                    sig(:__VdfgRegularize_hca2350fd_0_58, width: 1) &
                                                                    sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
                                                                ) |
                                                                (
                                                                    (
                                                                        sig(:__VdfgRegularize_hca2350fd_0_60, width: 1) &
                                                                        sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
                                                                    ) |
                                                                    (
                                                                        (
                                                                            sig(:__VdfgRegularize_hca2350fd_0_60, width: 1) &
                                                                            sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:__VdfgRegularize_hca2350fd_0_69, width: 1) &
                                                                                sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    sig(:__VdfgRegularize_hca2350fd_0_70, width: 1) &
                                                                                    sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
                                                                                ) |
                                                                                (
                                                                                    sig(:cond_138, width: 1) |
                                                                                    (
                                                                                        (
                                                                                            sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
                                                                                            sig(:__VdfgRegularize_hca2350fd_0_5, width: 1)
                                                                                        ) |
                                                                                        (
                                                                                            (
                                                                                                sig(:__VdfgRegularize_hca2350fd_0_71, width: 1) &
                                                                                                sig(:__VdfgRegularize_hca2350fd_0_36, width: 1)
                                                                                            ) |
                                                                                            (
                                                                                                (
                                                                                                    (
                                                                                                        lit(72, width: 7, base: "h", signed: false) ==
                                                                                                        sig(:mc_cmd, width: 7)
                                                                                                    ) &
                                                                                                    sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
                                                                                                ) |
                                                                                                (
                                                                                                    (
                                                                                                        (
                                                                                                            lit(76, width: 7, base: "h", signed: false) ==
                                                                                                            sig(:mc_cmd, width: 7)
                                                                                                        ) &
                                                                                                        sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
                                                                                                    ) |
                                                                                                    (
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_hca2350fd_0_75, width: 1) &
                                                                                                            sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
                                                                                                        ) |
                                                                                                        (
                                                                                                            (
                                                                                                                (
                                                                                                                    lit(83, width: 7, base: "h", signed: false) ==
                                                                                                                    sig(:mc_cmd, width: 7)
                                                                                                                ) &
                                                                                                                sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
                                                                                                            ) |
                                                                                                            (
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_hca2350fd_0_80, width: 1) &
                                                                                                                    sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
                                                                                                                ) |
                                                                                                                (
                                                                                                                    (
                                                                                                                        sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
                                                                                                                        sig(:__VdfgRegularize_hca2350fd_0_26, width: 1)
                                                                                                                    ) |
                                                                                                                    (
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
                                                                                                                            sig(:__VdfgRegularize_hca2350fd_0_11, width: 1)
                                                                                                                        ) |
                                                                                                                        (
                                                                                                                            (
                                                                                                                                sig(:__VdfgRegularize_hca2350fd_0_82, width: 1) &
                                                                                                                                sig(:__VdfgRegularize_hca2350fd_0_14, width: 1)
                                                                                                                            ) |
                                                                                                                            (
                                                                                                                                (
                                                                                                                                    sig(:__VdfgRegularize_hca2350fd_0_86, width: 1) &
                                                                                                                                    sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
                                                                                                                                ) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgRegularize_hca2350fd_0_87, width: 1) &
                                                                                                                                        sig(:__VdfgRegularize_hca2350fd_0_4, width: 1)
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgRegularize_hca2350fd_0_89, width: 1) &
                                                                                                                                            sig(:__VdfgRegularize_hca2350fd_0_2, width: 1)
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    lit(106, width: 7, base: "h", signed: false) ==
                                                                                                                                                    sig(:mc_cmd, width: 7)
                                                                                                                                                ) &
                                                                                                                                                sig(:__VdfgRegularize_hca2350fd_0_0, width: 1)
                                                                                                                                            ) |
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgRegularize_hca2350fd_0_99, width: 1) &
                                                                                                                                                sig(:__VdfgRegularize_hca2350fd_0_3, width: 1)
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_hca2350fd_0_80,
    (
        lit(85, width: 7, base: "h", signed: false) ==
        sig(:mc_cmd, width: 7)
    )
  assign :mc_saved_command_to_reg,
    mux(
      sig(:cond_8, width: 1),
      lit(3, width: 7, base: "h", signed: false),
      mux(
        sig(:cond_53, width: 1),
        lit(18, width: 7, base: "h", signed: false),
        mux(
          sig(:cond_54, width: 1),
          lit(19, width: 7, base: "h", signed: false),
          mux(
            sig(:cond_62, width: 1),
            lit(28, width: 7, base: "h", signed: false),
            mux(
              sig(:cond_100, width: 1),
              lit(34, width: 7, base: "h", signed: false),
              mux(
                sig(:cond_103, width: 1),
                lit(35, width: 7, base: "h", signed: false),
                mux(
                  sig(:cond_114, width: 1),
                  lit(40, width: 7, base: "h", signed: false),
                  mux(
                    sig(:cond_117, width: 1),
                    lit(40, width: 7, base: "h", signed: false),
                    mux(
                      sig(:cond_137, width: 1),
                      lit(63, width: 7, base: "h", signed: false),
                      mux(
                        sig(:cond_141, width: 1),
                        lit(63, width: 7, base: "h", signed: false),
                        mux(
                          sig(:cond_149, width: 1),
                          lit(77, width: 7, base: "h", signed: false),
                          mux(
                            sig(:cond_155, width: 1),
                            lit(84, width: 7, base: "h", signed: false),
                            mux(
                              sig(:cond_159, width: 1),
                              lit(85, width: 7, base: "h", signed: false),
                              mux(
                                sig(:cond_165, width: 1),
                                lit(87, width: 7, base: "h", signed: false),
                                mux(
                                  sig(:cond_181, width: 1),
                                  lit(89, width: 7, base: "h", signed: false),
                                  sig(:mc_saved_command, width: 7)
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :mc_saved_cmdex_to_reg,
    mux(
      sig(:cond_8, width: 1),
      lit(10, width: 4, base: "h", signed: false),
      mux(
        sig(:cond_53, width: 1),
        lit(3, width: 4, base: "h", signed: false),
        mux(
          sig(:cond_54, width: 1),
          lit(1, width: 4, base: "h", signed: false),
          mux(
            sig(:cond_62, width: 1),
            lit(7, width: 4, base: "h", signed: false),
            mux(
              sig(:cond_100, width: 1),
              lit(1, width: 4, base: "h", signed: false),
              mux(
                sig(:cond_103, width: 1),
                lit(3, width: 4, base: "h", signed: false),
                mux(
                  sig(:cond_114, width: 1),
                  mux(
                    sig(:__VdfgRegularize_hca2350fd_0_100, width: 1),
                    lit(1, width: 4, base: "h", signed: false),
                    lit(3, width: 4, base: "h", signed: false)
                  ),
                  mux(
                    sig(:cond_117, width: 1),
                    lit(4, width: 4, base: "h", signed: false),
                    mux(
                      sig(:cond_137, width: 1),
                      mux(
                        sig(:__VdfgRegularize_hca2350fd_0_9, width: 1),
                        lit(3, width: 4, base: "h", signed: false),
                        mux(
                          sig(:__VdfgRegularize_hca2350fd_0_100, width: 1),
                          lit(4, width: 4, base: "h", signed: false),
                          lit(6, width: 4, base: "h", signed: false)
                        )
                      ),
                      mux(
                        sig(:cond_141, width: 1),
                        lit(8, width: 4, base: "h", signed: false),
                        mux(
                          sig(:cond_149, width: 1),
                          lit(2, width: 4, base: "h", signed: false),
                          mux(
                            sig(:cond_155, width: 1),
                            lit(2, width: 4, base: "h", signed: false),
                            mux(
                              sig(:cond_159, width: 1),
                              lit(1, width: 4, base: "h", signed: false),
                              mux(
                                sig(:cond_165, width: 1),
                                lit(8, width: 4, base: "h", signed: false),
                                mux(
                                  sig(:cond_181, width: 1),
                                  lit(2, width: 4, base: "h", signed: false),
                                  sig(:mc_saved_cmdex, width: 4)
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hca2350fd_0_100,
    (
        sig(:glob_param_1, width: 32)[1..0] ==
        sig(:cpl, width: 2)
    )
  assign :mc_cmd_next,
    mux(
      sig(:cond_1, width: 1),
      lit(3, width: 7, base: "h", signed: false),
      mux(
        sig(:cond_2, width: 1),
        lit(3, width: 7, base: "h", signed: false),
        mux(
          sig(:cond_3, width: 1),
          lit(3, width: 7, base: "h", signed: false),
          mux(
            sig(:cond_4, width: 1),
            lit(3, width: 7, base: "h", signed: false),
            mux(
              sig(:cond_5, width: 1),
              lit(3, width: 7, base: "h", signed: false),
              mux(
                sig(:cond_6, width: 1),
                lit(3, width: 7, base: "h", signed: false),
                mux(
                  sig(:cond_7, width: 1),
                  lit(3, width: 7, base: "h", signed: false),
                  mux(
                    sig(:cond_8, width: 1),
                    lit(33, width: 7, base: "h", signed: false),
                    mux(
                      sig(:cond_9, width: 1),
                      lit(3, width: 7, base: "h", signed: false),
                      mux(
                        sig(:cond_10, width: 1),
                        lit(3, width: 7, base: "h", signed: false),
                        mux(
                          sig(:cond_11, width: 1),
                          lit(3, width: 7, base: "h", signed: false),
                          mux(
                            sig(:cond_12, width: 1),
                            lit(3, width: 7, base: "h", signed: false),
                            mux(
                              sig(:cond_13, width: 1),
                              lit(3, width: 7, base: "h", signed: false),
                              mux(
                                sig(:cond_14, width: 1),
                                lit(4, width: 7, base: "h", signed: false),
                                mux(
                                  sig(:cond_15, width: 1),
                                  lit(4, width: 7, base: "h", signed: false),
                                  mux(
                                    sig(:cond_16, width: 1),
                                    lit(4, width: 7, base: "h", signed: false),
                                    mux(
                                      sig(:cond_17, width: 1),
                                      lit(4, width: 7, base: "h", signed: false),
                                      mux(
                                        sig(:cond_18, width: 1),
                                        lit(99, width: 7, base: "h", signed: false),
                                        mux(
                                          sig(:cond_19, width: 1),
                                          lit(4, width: 7, base: "h", signed: false),
                                          mux(
                                            sig(:cond_20, width: 1),
                                            lit(4, width: 7, base: "h", signed: false),
                                            mux(
                                              sig(:cond_21, width: 1),
                                              lit(99, width: 7, base: "h", signed: false),
                                              mux(
                                                sig(:cond_22, width: 1),
                                                lit(4, width: 7, base: "h", signed: false),
                                                mux(
                                                  sig(:cond_23, width: 1),
                                                  lit(4, width: 7, base: "h", signed: false),
                                                  mux(
                                                    sig(:cond_24, width: 1),
                                                    lit(4, width: 7, base: "h", signed: false),
                                                    mux(
                                                      sig(:cond_25, width: 1),
                                                      lit(4, width: 7, base: "h", signed: false),
                                                      mux(
                                                        sig(:cond_26, width: 1),
                                                        lit(4, width: 7, base: "h", signed: false),
                                                        mux(
                                                          sig(:cond_27, width: 1),
                                                          lit(4, width: 7, base: "h", signed: false),
                                                          mux(
                                                            sig(:cond_28, width: 1),
                                                            lit(4, width: 7, base: "h", signed: false),
                                                            mux(
                                                              sig(:cond_29, width: 1),
                                                              lit(5, width: 7, base: "h", signed: false),
                                                              mux(
                                                                sig(:cond_30, width: 1),
                                                                lit(5, width: 7, base: "h", signed: false),
                                                                mux(
                                                                  sig(:cond_31, width: 1),
                                                                  lit(5, width: 7, base: "h", signed: false),
                                                                  mux(
                                                                    sig(:cond_32, width: 1),
                                                                    lit(5, width: 7, base: "h", signed: false),
                                                                    mux(
                                                                      sig(:cond_33, width: 1),
                                                                      lit(5, width: 7, base: "h", signed: false),
                                                                      mux(
                                                                        sig(:cond_34, width: 1),
                                                                        lit(5, width: 7, base: "h", signed: false),
                                                                        mux(
                                                                          sig(:cond_35, width: 1),
                                                                          lit(5, width: 7, base: "h", signed: false),
                                                                          mux(
                                                                            sig(:cond_36, width: 1),
                                                                            lit(5, width: 7, base: "h", signed: false),
                                                                            mux(
                                                                              sig(:cond_37, width: 1),
                                                                              lit(5, width: 7, base: "h", signed: false),
                                                                              mux(
                                                                                sig(:cond_38, width: 1),
                                                                                lit(5, width: 7, base: "h", signed: false),
                                                                                mux(
                                                                                  sig(:cond_39, width: 1),
                                                                                  lit(4, width: 7, base: "h", signed: false),
                                                                                  mux(
                                                                                    sig(:cond_40, width: 1),
                                                                                    lit(4, width: 7, base: "h", signed: false),
                                                                                    mux(
                                                                                      sig(:cond_41, width: 1),
                                                                                      lit(4, width: 7, base: "h", signed: false),
                                                                                      mux(
                                                                                        sig(:cond_42, width: 1),
                                                                                        lit(4, width: 7, base: "h", signed: false),
                                                                                        mux(
                                                                                          sig(:cond_43, width: 1),
                                                                                          lit(9, width: 7, base: "h", signed: false),
                                                                                          mux(
                                                                                            sig(:cond_44, width: 1),
                                                                                            lit(9, width: 7, base: "h", signed: false),
                                                                                            mux(
                                                                                              sig(:cond_45, width: 1),
                                                                                              lit(10, width: 7, base: "h", signed: false),
                                                                                              mux(
                                                                                                sig(:cond_46, width: 1),
                                                                                                lit(10, width: 7, base: "h", signed: false),
                                                                                                mux(
                                                                                                  sig(:cond_47, width: 1),
                                                                                                  lit(11, width: 7, base: "h", signed: false),
                                                                                                  mux(
                                                                                                    sig(:cond_48, width: 1),
                                                                                                    sig(:mc_saved_command, width: 7),
                                                                                                    mux(
                                                                                                      sig(:cond_51, width: 1),
                                                                                                      lit(18, width: 7, base: "h", signed: false),
                                                                                                      mux(
                                                                                                        sig(:cond_52, width: 1),
                                                                                                        lit(18, width: 7, base: "h", signed: false),
                                                                                                        mux(
                                                                                                          sig(:cond_53, width: 1),
                                                                                                          lit(33, width: 7, base: "h", signed: false),
                                                                                                          mux(
                                                                                                            sig(:cond_54, width: 1),
                                                                                                            lit(33, width: 7, base: "h", signed: false),
                                                                                                            mux(
                                                                                                              sig(:cond_55, width: 1),
                                                                                                              lit(19, width: 7, base: "h", signed: false),
                                                                                                              mux(
                                                                                                                sig(:cond_56, width: 1),
                                                                                                                lit(28, width: 7, base: "h", signed: false),
                                                                                                                mux(
                                                                                                                  sig(:cond_57, width: 1),
                                                                                                                  lit(28, width: 7, base: "h", signed: false),
                                                                                                                  mux(
                                                                                                                    sig(:cond_58, width: 1),
                                                                                                                    lit(28, width: 7, base: "h", signed: false),
                                                                                                                    mux(
                                                                                                                      sig(:cond_59, width: 1),
                                                                                                                      lit(28, width: 7, base: "h", signed: false),
                                                                                                                      mux(
                                                                                                                        sig(:cond_60, width: 1),
                                                                                                                        lit(28, width: 7, base: "h", signed: false),
                                                                                                                        mux(
                                                                                                                          sig(:cond_61, width: 1),
                                                                                                                          lit(28, width: 7, base: "h", signed: false),
                                                                                                                          mux(
                                                                                                                            sig(:cond_62, width: 1),
                                                                                                                            lit(33, width: 7, base: "h", signed: false),
                                                                                                                            mux(
                                                                                                                              sig(:cond_63, width: 1),
                                                                                                                              lit(28, width: 7, base: "h", signed: false),
                                                                                                                              mux(
                                                                                                                                sig(:cond_64, width: 1),
                                                                                                                                lit(28, width: 7, base: "h", signed: false),
                                                                                                                                mux(
                                                                                                                                  sig(:cond_65, width: 1),
                                                                                                                                  lit(28, width: 7, base: "h", signed: false),
                                                                                                                                  mux(
                                                                                                                                    sig(:cond_66, width: 1),
                                                                                                                                    lit(28, width: 7, base: "h", signed: false),
                                                                                                                                    mux(
                                                                                                                                      sig(:cond_67, width: 1),
                                                                                                                                      lit(28, width: 7, base: "h", signed: false),
                                                                                                                                      mux(
                                                                                                                                        sig(:cond_68, width: 1),
                                                                                                                                        lit(99, width: 7, base: "h", signed: false),
                                                                                                                                        mux(
                                                                                                                                          sig(:cond_69, width: 1),
                                                                                                                                          lit(28, width: 7, base: "h", signed: false),
                                                                                                                                          mux(
                                                                                                                                            sig(:cond_70, width: 1),
                                                                                                                                            lit(28, width: 7, base: "h", signed: false),
                                                                                                                                            mux(
                                                                                                                                              sig(:cond_71, width: 1),
                                                                                                                                              lit(28, width: 7, base: "h", signed: false),
                                                                                                                                              mux(
                                                                                                                                                sig(:cond_72, width: 1),
                                                                                                                                                lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                mux(
                                                                                                                                                  sig(:cond_73, width: 1),
                                                                                                                                                  lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                  mux(
                                                                                                                                                    sig(:cond_74, width: 1),
                                                                                                                                                    lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                    mux(
                                                                                                                                                      sig(:cond_75, width: 1),
                                                                                                                                                      lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                      mux(
                                                                                                                                                        sig(:cond_76, width: 1),
                                                                                                                                                        lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                        mux(
                                                                                                                                                          sig(:cond_77, width: 1),
                                                                                                                                                          lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                          mux(
                                                                                                                                                            sig(:cond_78, width: 1),
                                                                                                                                                            lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                            mux(
                                                                                                                                                              sig(:cond_79, width: 1),
                                                                                                                                                              lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                              mux(
                                                                                                                                                                sig(:cond_80, width: 1),
                                                                                                                                                                lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                mux(
                                                                                                                                                                  sig(:cond_81, width: 1),
                                                                                                                                                                  lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                  mux(
                                                                                                                                                                    sig(:cond_82, width: 1),
                                                                                                                                                                    lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                    mux(
                                                                                                                                                                      sig(:cond_83, width: 1),
                                                                                                                                                                      lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                      mux(
                                                                                                                                                                        sig(:cond_84, width: 1),
                                                                                                                                                                        lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                        mux(
                                                                                                                                                                          sig(:cond_85, width: 1),
                                                                                                                                                                          lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                          mux(
                                                                                                                                                                            sig(:cond_86, width: 1),
                                                                                                                                                                            lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                            mux(
                                                                                                                                                                              sig(:cond_87, width: 1),
                                                                                                                                                                              lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                              mux(
                                                                                                                                                                                sig(:cond_88, width: 1),
                                                                                                                                                                                lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                mux(
                                                                                                                                                                                  sig(:cond_89, width: 1),
                                                                                                                                                                                  lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                  mux(
                                                                                                                                                                                    sig(:cond_90, width: 1),
                                                                                                                                                                                    lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                    mux(
                                                                                                                                                                                      sig(:cond_91, width: 1),
                                                                                                                                                                                      lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                      mux(
                                                                                                                                                                                        sig(:cond_92, width: 1),
                                                                                                                                                                                        lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                        mux(
                                                                                                                                                                                          sig(:cond_93, width: 1),
                                                                                                                                                                                          lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                          mux(
                                                                                                                                                                                            sig(:cond_94, width: 1),
                                                                                                                                                                                            lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                            mux(
                                                                                                                                                                                              sig(:cond_95, width: 1),
                                                                                                                                                                                              lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                              mux(
                                                                                                                                                                                                sig(:cond_96, width: 1),
                                                                                                                                                                                                lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                                mux(
                                                                                                                                                                                                  sig(:cond_97, width: 1),
                                                                                                                                                                                                  lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                                  mux(
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :cond_98,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :mc_saved_command,
                                                                                                                                                                                                      width: 7
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    mux(
                                                                                                                                                                                                      sig(:cond_99, width: 1),
                                                                                                                                                                                                      lit(33, width: 7, base: "h", signed: false),
                                                                                                                                                                                                      mux(sig(:cond_100, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_101, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_102, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_103, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_104, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_105, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_106, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_107, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_108, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_109, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_110, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_111, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_112, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_113, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_114, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_115, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_116, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_117, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_118, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_119, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_121, width: 1), lit(45, width: 7, base: "h", signed: false), mux(sig(:cond_122, width: 1), lit(45, width: 7, base: "h", signed: false), mux(sig(:cond_123, width: 1), lit(46, width: 7, base: "h", signed: false), mux(sig(:cond_124, width: 1), lit(46, width: 7, base: "h", signed: false), mux(sig(:cond_125, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_126, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_127, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_128, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_131, width: 1), lit(53, width: 7, base: "h", signed: false), mux(sig(:cond_132, width: 1), lit(53, width: 7, base: "h", signed: false), mux(sig(:cond_133, width: 1), lit(58, width: 7, base: "h", signed: false), mux(sig(:cond_134, width: 1), lit(58, width: 7, base: "h", signed: false), mux(sig(:cond_135, width: 1), lit(62, width: 7, base: "h", signed: false), mux(sig(:cond_136, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_137, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_138, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_139, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_140, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_141, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_142, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_143, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_145, width: 1), lit(28, width: 7, base: "h", signed: false), mux(sig(:cond_146, width: 1), lit(28, width: 7, base: "h", signed: false), mux(sig(:cond_147, width: 1), lit(75, width: 7, base: "h", signed: false), mux(sig(:cond_148, width: 1), lit(77, width: 7, base: "h", signed: false), mux(sig(:cond_149, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_150, width: 1), lit(77, width: 7, base: "h", signed: false), mux(sig(:cond_151, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_153, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_154, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_155, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_156, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_157, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_158, width: 1), lit(85, width: 7, base: "h", signed: false), mux(sig(:cond_159, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_160, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_161, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_162, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_163, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_164, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_165, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_166, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_167, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_168, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_169, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_170, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_171, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_172, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_173, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_174, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_175, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_176, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_177, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_178, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_179, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_180, width: 1), lit(89, width: 7, base: "h", signed: false), mux(sig(:cond_181, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_182, width: 1), lit(89, width: 7, base: "h", signed: false), mux(sig(:cond_183, width: 1), lit(94, width: 7, base: "h", signed: false), mux(sig(:cond_185, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_186, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_187, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_188, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_189, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_190, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_191, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_192, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_193, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_194, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_195, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_196, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_197, width: 1), lit(100, width: 7, base: "h", signed: false), mux(sig(:cond_198, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_199, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_200, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_201, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_202, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_203, width: 1), lit(101, width: 7, base: "h", signed: false), mux(sig(:cond_204, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_205, width: 1), lit(102, width: 7, base: "h", signed: false), mux(sig(:cond_206, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_208, width: 1), sig(:mc_cmd, width: 7), sig(:__VdfgRegularize_hca2350fd_0_101, width: 7)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                  )
                                                                                                                                                                                                )
                                                                                                                                                                                              )
                                                                                                                                                                                            )
                                                                                                                                                                                          )
                                                                                                                                                                                        )
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            )
                                                                                                                          )
                                                                                                                        )
                                                                                                                      )
                                                                                                                    )
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hca2350fd_0_101,
    mux(
      sig(:cond_210, width: 1),
      lit(110, width: 7, base: "h", signed: false),
      mux(
        sig(:cond_211, width: 1),
        sig(:mc_cmd, width: 7),
        lit(0, width: 7, base: "h", signed: false)
      )
    )
  assign :mc_cmdex_current,
    mux(
      sig(:cond_0, width: 1),
      lit(1, width: 4, base: "h", signed: false),
      mux(
        sig(:cond_1, width: 1),
        lit(4, width: 4, base: "h", signed: false),
        mux(
          sig(:cond_2, width: 1),
          lit(4, width: 4, base: "h", signed: false),
          mux(
            sig(:cond_3, width: 1),
            lit(5, width: 4, base: "h", signed: false),
            mux(
              sig(:cond_4, width: 1),
              lit(6, width: 4, base: "h", signed: false),
              mux(
                sig(:cond_5, width: 1),
                lit(7, width: 4, base: "h", signed: false),
                mux(
                  sig(:cond_6, width: 1),
                  lit(8, width: 4, base: "h", signed: false),
                  mux(
                    sig(:cond_7, width: 1),
                    lit(9, width: 4, base: "h", signed: false),
                    mux(
                      sig(:cond_8, width: 1),
                      lit(0, width: 4, base: "h", signed: false),
                      mux(
                        sig(:cond_9, width: 1),
                        lit(11, width: 4, base: "h", signed: false),
                        mux(
                          sig(:cond_10, width: 1),
                          lit(12, width: 4, base: "h", signed: false),
                          mux(
                            sig(:cond_11, width: 1),
                            lit(13, width: 4, base: "h", signed: false),
                            mux(
                              sig(:cond_12, width: 1),
                              lit(14, width: 4, base: "h", signed: false),
                              mux(
                                sig(:cond_13, width: 1),
                                lit(15, width: 4, base: "h", signed: false),
                                mux(
                                  sig(:cond_14, width: 1),
                                  lit(0, width: 4, base: "h", signed: false),
                                  mux(
                                    sig(:cond_15, width: 1),
                                    lit(1, width: 4, base: "h", signed: false),
                                    mux(
                                      sig(:cond_16, width: 1),
                                      lit(2, width: 4, base: "h", signed: false),
                                      mux(
                                        sig(:cond_17, width: 1),
                                        lit(2, width: 4, base: "h", signed: false),
                                        mux(
                                          sig(:cond_18, width: 1),
                                          lit(1, width: 4, base: "h", signed: false),
                                          mux(
                                            sig(:cond_19, width: 1),
                                            lit(3, width: 4, base: "h", signed: false),
                                            mux(
                                              sig(:cond_20, width: 1),
                                              lit(4, width: 4, base: "h", signed: false),
                                              mux(
                                                sig(:cond_21, width: 1),
                                                lit(1, width: 4, base: "h", signed: false),
                                                mux(
                                                  sig(:cond_22, width: 1),
                                                  lit(5, width: 4, base: "h", signed: false),
                                                  mux(
                                                    sig(:cond_23, width: 1),
                                                    lit(6, width: 4, base: "h", signed: false),
                                                    mux(
                                                      sig(:cond_24, width: 1),
                                                      lit(7, width: 4, base: "h", signed: false),
                                                      mux(
                                                        sig(:cond_25, width: 1),
                                                        lit(12, width: 4, base: "h", signed: false),
                                                        mux(
                                                          sig(:cond_26, width: 1),
                                                          lit(13, width: 4, base: "h", signed: false),
                                                          mux(
                                                            sig(:cond_27, width: 1),
                                                            lit(14, width: 4, base: "h", signed: false),
                                                            mux(
                                                              sig(:cond_28, width: 1),
                                                              lit(15, width: 4, base: "h", signed: false),
                                                              mux(
                                                                sig(:cond_29, width: 1),
                                                                lit(0, width: 4, base: "h", signed: false),
                                                                mux(
                                                                  sig(:cond_30, width: 1),
                                                                  lit(2, width: 4, base: "h", signed: false),
                                                                  mux(
                                                                    sig(:cond_31, width: 1),
                                                                    lit(1, width: 4, base: "h", signed: false),
                                                                    mux(
                                                                      sig(:cond_32, width: 1),
                                                                      lit(2, width: 4, base: "h", signed: false),
                                                                      mux(
                                                                        sig(:cond_33, width: 1),
                                                                        lit(1, width: 4, base: "h", signed: false),
                                                                        mux(
                                                                          sig(:cond_34, width: 1),
                                                                          lit(2, width: 4, base: "h", signed: false),
                                                                          mux(
                                                                            sig(:cond_35, width: 1),
                                                                            lit(3, width: 4, base: "h", signed: false),
                                                                            mux(
                                                                              sig(:cond_36, width: 1),
                                                                              lit(4, width: 4, base: "h", signed: false),
                                                                              mux(
                                                                                sig(:cond_37, width: 1),
                                                                                lit(5, width: 4, base: "h", signed: false),
                                                                                mux(
                                                                                  sig(:cond_38, width: 1),
                                                                                  lit(6, width: 4, base: "h", signed: false),
                                                                                  mux(
                                                                                    sig(:cond_39, width: 1),
                                                                                    lit(8, width: 4, base: "h", signed: false),
                                                                                    mux(
                                                                                      sig(:cond_40, width: 1),
                                                                                      lit(9, width: 4, base: "h", signed: false),
                                                                                      mux(
                                                                                        sig(:cond_41, width: 1),
                                                                                        lit(10, width: 4, base: "h", signed: false),
                                                                                        mux(
                                                                                          sig(:cond_42, width: 1),
                                                                                          lit(11, width: 4, base: "h", signed: false),
                                                                                          mux(
                                                                                            sig(:cond_43, width: 1),
                                                                                            lit(1, width: 4, base: "h", signed: false),
                                                                                            mux(
                                                                                              sig(:cond_44, width: 1),
                                                                                              lit(2, width: 4, base: "h", signed: false),
                                                                                              mux(
                                                                                                sig(:cond_45, width: 1),
                                                                                                lit(1, width: 4, base: "h", signed: false),
                                                                                                mux(
                                                                                                  sig(:cond_46, width: 1),
                                                                                                  lit(2, width: 4, base: "h", signed: false),
                                                                                                  mux(
                                                                                                    sig(:cond_47, width: 1),
                                                                                                    lit(1, width: 4, base: "h", signed: false),
                                                                                                    mux(
                                                                                                      sig(:cond_48, width: 1),
                                                                                                      sig(:mc_saved_cmdex, width: 4),
                                                                                                      mux(
                                                                                                        sig(:cond_49, width: 1),
                                                                                                        lit(2, width: 4, base: "h", signed: false),
                                                                                                        mux(
                                                                                                          sig(:cond_50, width: 1),
                                                                                                          lit(2, width: 4, base: "h", signed: false),
                                                                                                          mux(
                                                                                                            sig(:cond_51, width: 1),
                                                                                                            lit(1, width: 4, base: "h", signed: false),
                                                                                                            mux(
                                                                                                              sig(:cond_52, width: 1),
                                                                                                              lit(2, width: 4, base: "h", signed: false),
                                                                                                              mux(
                                                                                                                sig(:cond_53, width: 1),
                                                                                                                lit(0, width: 4, base: "h", signed: false),
                                                                                                                mux(
                                                                                                                  sig(:cond_54, width: 1),
                                                                                                                  lit(0, width: 4, base: "h", signed: false),
                                                                                                                  mux(
                                                                                                                    sig(:cond_55, width: 1),
                                                                                                                    lit(1, width: 4, base: "h", signed: false),
                                                                                                                    mux(
                                                                                                                      sig(:cond_56, width: 1),
                                                                                                                      lit(1, width: 4, base: "h", signed: false),
                                                                                                                      mux(
                                                                                                                        sig(:cond_57, width: 1),
                                                                                                                        lit(2, width: 4, base: "h", signed: false),
                                                                                                                        mux(
                                                                                                                          sig(:cond_58, width: 1),
                                                                                                                          lit(3, width: 4, base: "h", signed: false),
                                                                                                                          mux(
                                                                                                                            sig(:cond_59, width: 1),
                                                                                                                            lit(4, width: 4, base: "h", signed: false),
                                                                                                                            mux(
                                                                                                                              sig(:cond_60, width: 1),
                                                                                                                              lit(5, width: 4, base: "h", signed: false),
                                                                                                                              mux(
                                                                                                                                sig(:cond_61, width: 1),
                                                                                                                                lit(6, width: 4, base: "h", signed: false),
                                                                                                                                mux(
                                                                                                                                  sig(:cond_62, width: 1),
                                                                                                                                  lit(0, width: 4, base: "h", signed: false),
                                                                                                                                  mux(
                                                                                                                                    sig(:cond_63, width: 1),
                                                                                                                                    lit(8, width: 4, base: "h", signed: false),
                                                                                                                                    mux(
                                                                                                                                      sig(:cond_64, width: 1),
                                                                                                                                      lit(9, width: 4, base: "h", signed: false),
                                                                                                                                      mux(
                                                                                                                                        sig(:cond_65, width: 1),
                                                                                                                                        lit(10, width: 4, base: "h", signed: false),
                                                                                                                                        mux(
                                                                                                                                          sig(:cond_66, width: 1),
                                                                                                                                          lit(11, width: 4, base: "h", signed: false),
                                                                                                                                          mux(
                                                                                                                                            sig(:cond_67, width: 1),
                                                                                                                                            lit(12, width: 4, base: "h", signed: false),
                                                                                                                                            mux(
                                                                                                                                              sig(:cond_68, width: 1),
                                                                                                                                              lit(1, width: 4, base: "h", signed: false),
                                                                                                                                              mux(
                                                                                                                                                sig(:cond_69, width: 1),
                                                                                                                                                lit(13, width: 4, base: "h", signed: false),
                                                                                                                                                mux(
                                                                                                                                                  sig(:cond_70, width: 1),
                                                                                                                                                  lit(14, width: 4, base: "h", signed: false),
                                                                                                                                                  mux(
                                                                                                                                                    sig(:cond_71, width: 1),
                                                                                                                                                    lit(15, width: 4, base: "h", signed: false),
                                                                                                                                                    mux(
                                                                                                                                                      sig(:cond_72, width: 1),
                                                                                                                                                      lit(6, width: 4, base: "h", signed: false),
                                                                                                                                                      mux(
                                                                                                                                                        sig(:cond_73, width: 1),
                                                                                                                                                        lit(7, width: 4, base: "h", signed: false),
                                                                                                                                                        mux(
                                                                                                                                                          sig(:cond_74, width: 1),
                                                                                                                                                          lit(8, width: 4, base: "h", signed: false),
                                                                                                                                                          mux(
                                                                                                                                                            sig(:cond_75, width: 1),
                                                                                                                                                            lit(9, width: 4, base: "h", signed: false),
                                                                                                                                                            mux(
                                                                                                                                                              sig(:cond_76, width: 1),
                                                                                                                                                              lit(10, width: 4, base: "h", signed: false),
                                                                                                                                                              mux(
                                                                                                                                                                sig(:cond_77, width: 1),
                                                                                                                                                                lit(11, width: 4, base: "h", signed: false),
                                                                                                                                                                mux(
                                                                                                                                                                  sig(:cond_78, width: 1),
                                                                                                                                                                  lit(12, width: 4, base: "h", signed: false),
                                                                                                                                                                  mux(
                                                                                                                                                                    sig(:cond_79, width: 1),
                                                                                                                                                                    lit(13, width: 4, base: "h", signed: false),
                                                                                                                                                                    mux(
                                                                                                                                                                      sig(:cond_80, width: 1),
                                                                                                                                                                      lit(14, width: 4, base: "h", signed: false),
                                                                                                                                                                      mux(
                                                                                                                                                                        sig(:cond_81, width: 1),
                                                                                                                                                                        lit(14, width: 4, base: "h", signed: false),
                                                                                                                                                                        mux(
                                                                                                                                                                          sig(:cond_82, width: 1),
                                                                                                                                                                          lit(15, width: 4, base: "h", signed: false),
                                                                                                                                                                          mux(
                                                                                                                                                                            sig(:cond_83, width: 1),
                                                                                                                                                                            lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                            mux(
                                                                                                                                                                              sig(:cond_84, width: 1),
                                                                                                                                                                              lit(1, width: 4, base: "h", signed: false),
                                                                                                                                                                              mux(
                                                                                                                                                                                sig(:cond_85, width: 1),
                                                                                                                                                                                lit(2, width: 4, base: "h", signed: false),
                                                                                                                                                                                mux(
                                                                                                                                                                                  sig(:cond_86, width: 1),
                                                                                                                                                                                  lit(3, width: 4, base: "h", signed: false),
                                                                                                                                                                                  mux(
                                                                                                                                                                                    sig(:cond_87, width: 1),
                                                                                                                                                                                    lit(4, width: 4, base: "h", signed: false),
                                                                                                                                                                                    mux(
                                                                                                                                                                                      sig(:cond_88, width: 1),
                                                                                                                                                                                      lit(4, width: 4, base: "h", signed: false),
                                                                                                                                                                                      mux(
                                                                                                                                                                                        sig(:cond_89, width: 1),
                                                                                                                                                                                        lit(5, width: 4, base: "h", signed: false),
                                                                                                                                                                                        mux(
                                                                                                                                                                                          sig(:cond_90, width: 1),
                                                                                                                                                                                          lit(6, width: 4, base: "h", signed: false),
                                                                                                                                                                                          mux(
                                                                                                                                                                                            sig(:cond_91, width: 1),
                                                                                                                                                                                            lit(0, width: 4, base: "h", signed: false),
                                                                                                                                                                                            mux(
                                                                                                                                                                                              sig(:cond_92, width: 1),
                                                                                                                                                                                              lit(1, width: 4, base: "h", signed: false),
                                                                                                                                                                                              mux(
                                                                                                                                                                                                sig(:cond_93, width: 1),
                                                                                                                                                                                                lit(2, width: 4, base: "h", signed: false),
                                                                                                                                                                                                mux(
                                                                                                                                                                                                  sig(:cond_94, width: 1),
                                                                                                                                                                                                  lit(3, width: 4, base: "h", signed: false),
                                                                                                                                                                                                  mux(
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :cond_95,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    lit(
                                                                                                                                                                                                      4,
                                                                                                                                                                                                      width: 4,
                                                                                                                                                                                                      base: "h",
                                                                                                                                                                                                      signed: false
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    mux(
                                                                                                                                                                                                      sig(:cond_96, width: 1),
                                                                                                                                                                                                      lit(4, width: 4, base: "h", signed: false),
                                                                                                                                                                                                      mux(sig(:cond_97, width: 1), lit(5, width: 4, base: "h", signed: false), mux(sig(:cond_98, width: 1), sig(:mc_saved_cmdex, width: 4), mux(sig(:cond_99, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_100, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_101, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_102, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_103, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_104, width: 1), lit(5, width: 4, base: "h", signed: false), mux(sig(:cond_105, width: 1), lit(6, width: 4, base: "h", signed: false), mux(sig(:cond_106, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_107, width: 1), lit(7, width: 4, base: "h", signed: false), mux(sig(:cond_108, width: 1), lit(8, width: 4, base: "h", signed: false), mux(sig(:cond_109, width: 1), lit(9, width: 4, base: "h", signed: false), mux(sig(:cond_110, width: 1), lit(10, width: 4, base: "h", signed: false), mux(sig(:cond_111, width: 1), sig(:__VdfgRegularize_hca2350fd_0_102, width: 4), mux(sig(:cond_112, width: 1), lit(10, width: 4, base: "h", signed: false), mux(sig(:cond_113, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_114, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_115, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_116, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_117, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_118, width: 1), sig(:__VdfgRegularize_hca2350fd_0_102, width: 4), mux(sig(:cond_119, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_120, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_121, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_122, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_123, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_124, width: 1), lit(5, width: 4, base: "h", signed: false), mux(sig(:cond_125, width: 1), lit(9, width: 4, base: "h", signed: false), mux(sig(:cond_126, width: 1), lit(10, width: 4, base: "h", signed: false), mux(sig(:cond_127, width: 1), lit(10, width: 4, base: "h", signed: false), mux(sig(:cond_128, width: 1), sig(:mc_step, width: 6)[3..0], mux(sig(:cond_129, width: 1), lit(7, width: 4, base: "h", signed: false), mux(sig(:cond_130, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_131, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_132, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_133, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_134, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_135, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_136, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_137, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_138, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_139, width: 1), lit(5, width: 4, base: "h", signed: false), mux(sig(:cond_140, width: 1), lit(7, width: 4, base: "h", signed: false), mux(sig(:cond_141, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_142, width: 1), lit(9, width: 4, base: "h", signed: false), mux(sig(:cond_143, width: 1), lit(10, width: 4, base: "h", signed: false), mux(sig(:cond_144, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_145, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_146, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_147, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_148, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_149, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_150, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_151, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_152, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_153, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_154, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_155, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_156, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_157, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_158, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_159, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_160, width: 1), lit(4, width: 4, base: "h", signed: false), mux(sig(:cond_161, width: 1), lit(4, width: 4, base: "h", signed: false), mux(sig(:cond_162, width: 1), lit(5, width: 4, base: "h", signed: false), mux(sig(:cond_163, width: 1), lit(6, width: 4, base: "h", signed: false), mux(sig(:cond_164, width: 1), lit(7, width: 4, base: "h", signed: false), mux(sig(:cond_165, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_166, width: 1), lit(9, width: 4, base: "h", signed: false), mux(sig(:cond_167, width: 1), lit(10, width: 4, base: "h", signed: false), mux(sig(:cond_168, width: 1), lit(11, width: 4, base: "h", signed: false), mux(sig(:cond_169, width: 1), lit(12, width: 4, base: "h", signed: false), mux(sig(:cond_170, width: 1), lit(13, width: 4, base: "h", signed: false), mux(sig(:cond_171, width: 1), lit(13, width: 4, base: "h", signed: false), mux(sig(:cond_172, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_173, width: 1), lit(14, width: 4, base: "h", signed: false), mux(sig(:cond_174, width: 1), lit(15, width: 4, base: "h", signed: false), mux(sig(:cond_175, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_176, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_177, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_178, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_179, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_180, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_181, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_182, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_183, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_184, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_185, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_186, width: 1), lit(3, width: 4, base: "h", signed: false), mux(sig(:cond_187, width: 1), lit(4, width: 4, base: "h", signed: false), mux(sig(:cond_188, width: 1), lit(5, width: 4, base: "h", signed: false), mux(sig(:cond_189, width: 1), lit(6, width: 4, base: "h", signed: false), mux(sig(:cond_190, width: 1), lit(6, width: 4, base: "h", signed: false), mux(sig(:cond_191, width: 1), lit(6, width: 4, base: "h", signed: false), mux(sig(:cond_192, width: 1), lit(7, width: 4, base: "h", signed: false), mux(sig(:cond_193, width: 1), lit(8, width: 4, base: "h", signed: false), mux(sig(:cond_194, width: 1), lit(9, width: 4, base: "h", signed: false), mux(sig(:cond_195, width: 1), lit(9, width: 4, base: "h", signed: false), mux(sig(:cond_196, width: 1), lit(10, width: 4, base: "h", signed: false), mux(sig(:cond_197, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_198, width: 1), sig(:__VdfgRegularize_hca2350fd_0_102, width: 4), mux(sig(:cond_199, width: 1), lit(11, width: 4, base: "h", signed: false), mux(sig(:cond_200, width: 1), lit(12, width: 4, base: "h", signed: false), mux(sig(:cond_201, width: 1), lit(13, width: 4, base: "h", signed: false), mux(sig(:cond_202, width: 1), lit(14, width: 4, base: "h", signed: false), mux(sig(:cond_203, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_204, width: 1), sig(:__VdfgRegularize_hca2350fd_0_102, width: 4), mux(sig(:cond_205, width: 1), lit(0, width: 4, base: "h", signed: false), mux(sig(:cond_206, width: 1), sig(:__VdfgRegularize_hca2350fd_0_102, width: 4), mux(sig(:cond_207, width: 1), lit(1, width: 4, base: "h", signed: false), mux(sig(:cond_208, width: 1), sig(:mc_step, width: 6)[3..0], mux(sig(:cond_209, width: 1), lit(7, width: 4, base: "h", signed: false), mux(sig(:cond_210, width: 1), lit(2, width: 4, base: "h", signed: false), mux(sig(:cond_211, width: 1), sig(:mc_cmdex_last, width: 4), lit(0, width: 4, base: "h", signed: false))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                  )
                                                                                                                                                                                                )
                                                                                                                                                                                              )
                                                                                                                                                                                            )
                                                                                                                                                                                          )
                                                                                                                                                                                        )
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            )
                                                                                                                          )
                                                                                                                        )
                                                                                                                      )
                                                                                                                    )
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hca2350fd_0_102,
    (
        lit(1, width: 4, base: "h", signed: false) +
        sig(:mc_cmdex_last, width: 4)
    )
  assign :mc_cmd_current,
    mux(
      sig(:cond_0, width: 1),
      lit(1, width: 7, base: "h", signed: false),
      mux(
        sig(:cond_1, width: 1),
        lit(3, width: 7, base: "h", signed: false),
        mux(
          sig(:cond_2, width: 1),
          lit(3, width: 7, base: "h", signed: false),
          mux(
            sig(:cond_3, width: 1),
            lit(3, width: 7, base: "h", signed: false),
            mux(
              sig(:cond_4, width: 1),
              lit(3, width: 7, base: "h", signed: false),
              mux(
                sig(:cond_5, width: 1),
                lit(3, width: 7, base: "h", signed: false),
                mux(
                  sig(:cond_6, width: 1),
                  lit(3, width: 7, base: "h", signed: false),
                  mux(
                    sig(:cond_7, width: 1),
                    lit(3, width: 7, base: "h", signed: false),
                    mux(
                      sig(:cond_8, width: 1),
                      lit(33, width: 7, base: "h", signed: false),
                      mux(
                        sig(:cond_9, width: 1),
                        lit(3, width: 7, base: "h", signed: false),
                        mux(
                          sig(:cond_10, width: 1),
                          lit(3, width: 7, base: "h", signed: false),
                          mux(
                            sig(:cond_11, width: 1),
                            lit(3, width: 7, base: "h", signed: false),
                            mux(
                              sig(:cond_12, width: 1),
                              lit(3, width: 7, base: "h", signed: false),
                              mux(
                                sig(:cond_13, width: 1),
                                lit(3, width: 7, base: "h", signed: false),
                                mux(
                                  sig(:cond_14, width: 1),
                                  lit(4, width: 7, base: "h", signed: false),
                                  mux(
                                    sig(:cond_15, width: 1),
                                    lit(4, width: 7, base: "h", signed: false),
                                    mux(
                                      sig(:cond_16, width: 1),
                                      lit(4, width: 7, base: "h", signed: false),
                                      mux(
                                        sig(:cond_17, width: 1),
                                        lit(4, width: 7, base: "h", signed: false),
                                        mux(
                                          sig(:cond_18, width: 1),
                                          lit(99, width: 7, base: "h", signed: false),
                                          mux(
                                            sig(:cond_19, width: 1),
                                            lit(4, width: 7, base: "h", signed: false),
                                            mux(
                                              sig(:cond_20, width: 1),
                                              lit(4, width: 7, base: "h", signed: false),
                                              mux(
                                                sig(:cond_21, width: 1),
                                                lit(99, width: 7, base: "h", signed: false),
                                                mux(
                                                  sig(:cond_22, width: 1),
                                                  lit(4, width: 7, base: "h", signed: false),
                                                  mux(
                                                    sig(:cond_23, width: 1),
                                                    lit(4, width: 7, base: "h", signed: false),
                                                    mux(
                                                      sig(:cond_24, width: 1),
                                                      lit(4, width: 7, base: "h", signed: false),
                                                      mux(
                                                        sig(:cond_25, width: 1),
                                                        lit(4, width: 7, base: "h", signed: false),
                                                        mux(
                                                          sig(:cond_26, width: 1),
                                                          lit(4, width: 7, base: "h", signed: false),
                                                          mux(
                                                            sig(:cond_27, width: 1),
                                                            lit(4, width: 7, base: "h", signed: false),
                                                            mux(
                                                              sig(:cond_28, width: 1),
                                                              lit(4, width: 7, base: "h", signed: false),
                                                              mux(
                                                                sig(:cond_29, width: 1),
                                                                lit(5, width: 7, base: "h", signed: false),
                                                                mux(
                                                                  sig(:cond_30, width: 1),
                                                                  lit(5, width: 7, base: "h", signed: false),
                                                                  mux(
                                                                    sig(:cond_31, width: 1),
                                                                    lit(5, width: 7, base: "h", signed: false),
                                                                    mux(
                                                                      sig(:cond_32, width: 1),
                                                                      lit(5, width: 7, base: "h", signed: false),
                                                                      mux(
                                                                        sig(:cond_33, width: 1),
                                                                        lit(5, width: 7, base: "h", signed: false),
                                                                        mux(
                                                                          sig(:cond_34, width: 1),
                                                                          lit(5, width: 7, base: "h", signed: false),
                                                                          mux(
                                                                            sig(:cond_35, width: 1),
                                                                            lit(5, width: 7, base: "h", signed: false),
                                                                            mux(
                                                                              sig(:cond_36, width: 1),
                                                                              lit(5, width: 7, base: "h", signed: false),
                                                                              mux(
                                                                                sig(:cond_37, width: 1),
                                                                                lit(5, width: 7, base: "h", signed: false),
                                                                                mux(
                                                                                  sig(:cond_38, width: 1),
                                                                                  lit(5, width: 7, base: "h", signed: false),
                                                                                  mux(
                                                                                    sig(:cond_39, width: 1),
                                                                                    lit(4, width: 7, base: "h", signed: false),
                                                                                    mux(
                                                                                      sig(:cond_40, width: 1),
                                                                                      lit(4, width: 7, base: "h", signed: false),
                                                                                      mux(
                                                                                        sig(:cond_41, width: 1),
                                                                                        lit(4, width: 7, base: "h", signed: false),
                                                                                        mux(
                                                                                          sig(:cond_42, width: 1),
                                                                                          lit(4, width: 7, base: "h", signed: false),
                                                                                          mux(
                                                                                            sig(:cond_43, width: 1),
                                                                                            lit(9, width: 7, base: "h", signed: false),
                                                                                            mux(
                                                                                              sig(:cond_44, width: 1),
                                                                                              lit(9, width: 7, base: "h", signed: false),
                                                                                              mux(
                                                                                                sig(:cond_45, width: 1),
                                                                                                lit(10, width: 7, base: "h", signed: false),
                                                                                                mux(
                                                                                                  sig(:cond_46, width: 1),
                                                                                                  lit(10, width: 7, base: "h", signed: false),
                                                                                                  mux(
                                                                                                    sig(:cond_47, width: 1),
                                                                                                    lit(11, width: 7, base: "h", signed: false),
                                                                                                    mux(
                                                                                                      sig(:cond_48, width: 1),
                                                                                                      sig(:mc_saved_command, width: 7),
                                                                                                      mux(
                                                                                                        sig(:cond_49, width: 1),
                                                                                                        lit(15, width: 7, base: "h", signed: false),
                                                                                                        mux(
                                                                                                          sig(:cond_50, width: 1),
                                                                                                          lit(15, width: 7, base: "h", signed: false),
                                                                                                          mux(
                                                                                                            sig(:cond_51, width: 1),
                                                                                                            lit(18, width: 7, base: "h", signed: false),
                                                                                                            mux(
                                                                                                              sig(:cond_52, width: 1),
                                                                                                              lit(18, width: 7, base: "h", signed: false),
                                                                                                              mux(
                                                                                                                sig(:cond_53, width: 1),
                                                                                                                lit(33, width: 7, base: "h", signed: false),
                                                                                                                mux(
                                                                                                                  sig(:cond_54, width: 1),
                                                                                                                  lit(33, width: 7, base: "h", signed: false),
                                                                                                                  mux(
                                                                                                                    sig(:cond_55, width: 1),
                                                                                                                    lit(19, width: 7, base: "h", signed: false),
                                                                                                                    mux(
                                                                                                                      sig(:cond_56, width: 1),
                                                                                                                      lit(28, width: 7, base: "h", signed: false),
                                                                                                                      mux(
                                                                                                                        sig(:cond_57, width: 1),
                                                                                                                        lit(28, width: 7, base: "h", signed: false),
                                                                                                                        mux(
                                                                                                                          sig(:cond_58, width: 1),
                                                                                                                          lit(28, width: 7, base: "h", signed: false),
                                                                                                                          mux(
                                                                                                                            sig(:cond_59, width: 1),
                                                                                                                            lit(28, width: 7, base: "h", signed: false),
                                                                                                                            mux(
                                                                                                                              sig(:cond_60, width: 1),
                                                                                                                              lit(28, width: 7, base: "h", signed: false),
                                                                                                                              mux(
                                                                                                                                sig(:cond_61, width: 1),
                                                                                                                                lit(28, width: 7, base: "h", signed: false),
                                                                                                                                mux(
                                                                                                                                  sig(:cond_62, width: 1),
                                                                                                                                  lit(33, width: 7, base: "h", signed: false),
                                                                                                                                  mux(
                                                                                                                                    sig(:cond_63, width: 1),
                                                                                                                                    lit(28, width: 7, base: "h", signed: false),
                                                                                                                                    mux(
                                                                                                                                      sig(:cond_64, width: 1),
                                                                                                                                      lit(28, width: 7, base: "h", signed: false),
                                                                                                                                      mux(
                                                                                                                                        sig(:cond_65, width: 1),
                                                                                                                                        lit(28, width: 7, base: "h", signed: false),
                                                                                                                                        mux(
                                                                                                                                          sig(:cond_66, width: 1),
                                                                                                                                          lit(28, width: 7, base: "h", signed: false),
                                                                                                                                          mux(
                                                                                                                                            sig(:cond_67, width: 1),
                                                                                                                                            lit(28, width: 7, base: "h", signed: false),
                                                                                                                                            mux(
                                                                                                                                              sig(:cond_68, width: 1),
                                                                                                                                              lit(99, width: 7, base: "h", signed: false),
                                                                                                                                              mux(
                                                                                                                                                sig(:cond_69, width: 1),
                                                                                                                                                lit(28, width: 7, base: "h", signed: false),
                                                                                                                                                mux(
                                                                                                                                                  sig(:cond_70, width: 1),
                                                                                                                                                  lit(28, width: 7, base: "h", signed: false),
                                                                                                                                                  mux(
                                                                                                                                                    sig(:cond_71, width: 1),
                                                                                                                                                    lit(28, width: 7, base: "h", signed: false),
                                                                                                                                                    mux(
                                                                                                                                                      sig(:cond_72, width: 1),
                                                                                                                                                      lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                      mux(
                                                                                                                                                        sig(:cond_73, width: 1),
                                                                                                                                                        lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                        mux(
                                                                                                                                                          sig(:cond_74, width: 1),
                                                                                                                                                          lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                          mux(
                                                                                                                                                            sig(:cond_75, width: 1),
                                                                                                                                                            lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                            mux(
                                                                                                                                                              sig(:cond_76, width: 1),
                                                                                                                                                              lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                              mux(
                                                                                                                                                                sig(:cond_77, width: 1),
                                                                                                                                                                lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                mux(
                                                                                                                                                                  sig(:cond_78, width: 1),
                                                                                                                                                                  lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                  mux(
                                                                                                                                                                    sig(:cond_79, width: 1),
                                                                                                                                                                    lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                    mux(
                                                                                                                                                                      sig(:cond_80, width: 1),
                                                                                                                                                                      lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                      mux(
                                                                                                                                                                        sig(:cond_81, width: 1),
                                                                                                                                                                        lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                        mux(
                                                                                                                                                                          sig(:cond_82, width: 1),
                                                                                                                                                                          lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                          mux(
                                                                                                                                                                            sig(:cond_83, width: 1),
                                                                                                                                                                            lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                            mux(
                                                                                                                                                                              sig(:cond_84, width: 1),
                                                                                                                                                                              lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                              mux(
                                                                                                                                                                                sig(:cond_85, width: 1),
                                                                                                                                                                                lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                mux(
                                                                                                                                                                                  sig(:cond_86, width: 1),
                                                                                                                                                                                  lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                  mux(
                                                                                                                                                                                    sig(:cond_87, width: 1),
                                                                                                                                                                                    lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                    mux(
                                                                                                                                                                                      sig(:cond_88, width: 1),
                                                                                                                                                                                      lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                      mux(
                                                                                                                                                                                        sig(:cond_89, width: 1),
                                                                                                                                                                                        lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                        mux(
                                                                                                                                                                                          sig(:cond_90, width: 1),
                                                                                                                                                                                          lit(30, width: 7, base: "h", signed: false),
                                                                                                                                                                                          mux(
                                                                                                                                                                                            sig(:cond_91, width: 1),
                                                                                                                                                                                            lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                            mux(
                                                                                                                                                                                              sig(:cond_92, width: 1),
                                                                                                                                                                                              lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                              mux(
                                                                                                                                                                                                sig(:cond_93, width: 1),
                                                                                                                                                                                                lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                                mux(
                                                                                                                                                                                                  sig(:cond_94, width: 1),
                                                                                                                                                                                                  lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                                  mux(
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :cond_95,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    lit(
                                                                                                                                                                                                      29,
                                                                                                                                                                                                      width: 7,
                                                                                                                                                                                                      base: "h",
                                                                                                                                                                                                      signed: false
                                                                                                                                                                                                    ),
                                                                                                                                                                                                    mux(
                                                                                                                                                                                                      sig(:cond_96, width: 1),
                                                                                                                                                                                                      lit(29, width: 7, base: "h", signed: false),
                                                                                                                                                                                                      mux(sig(:cond_97, width: 1), lit(29, width: 7, base: "h", signed: false), mux(sig(:cond_98, width: 1), sig(:mc_saved_command, width: 7), mux(sig(:cond_99, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_100, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_101, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_102, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_103, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_104, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_105, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_106, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_107, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_108, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_109, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_110, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_111, width: 1), lit(35, width: 7, base: "h", signed: false), mux(sig(:cond_112, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_113, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_114, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_115, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_116, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_117, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_118, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_119, width: 1), lit(40, width: 7, base: "h", signed: false), mux(sig(:cond_120, width: 1), lit(41, width: 7, base: "h", signed: false), mux(sig(:cond_121, width: 1), lit(45, width: 7, base: "h", signed: false), mux(sig(:cond_122, width: 1), lit(45, width: 7, base: "h", signed: false), mux(sig(:cond_123, width: 1), lit(46, width: 7, base: "h", signed: false), mux(sig(:cond_124, width: 1), lit(46, width: 7, base: "h", signed: false), mux(sig(:cond_125, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_126, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_127, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_128, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_129, width: 1), lit(49, width: 7, base: "h", signed: false), mux(sig(:cond_130, width: 1), lit(53, width: 7, base: "h", signed: false), mux(sig(:cond_131, width: 1), lit(53, width: 7, base: "h", signed: false), mux(sig(:cond_132, width: 1), lit(53, width: 7, base: "h", signed: false), mux(sig(:cond_133, width: 1), lit(58, width: 7, base: "h", signed: false), mux(sig(:cond_134, width: 1), lit(58, width: 7, base: "h", signed: false), mux(sig(:cond_135, width: 1), lit(62, width: 7, base: "h", signed: false), mux(sig(:cond_136, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_137, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_138, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_139, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_140, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_141, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_142, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_143, width: 1), lit(63, width: 7, base: "h", signed: false), mux(sig(:cond_144, width: 1), lit(73, width: 7, base: "h", signed: false), mux(sig(:cond_145, width: 1), lit(28, width: 7, base: "h", signed: false), mux(sig(:cond_146, width: 1), lit(28, width: 7, base: "h", signed: false), mux(sig(:cond_147, width: 1), lit(75, width: 7, base: "h", signed: false), mux(sig(:cond_148, width: 1), lit(77, width: 7, base: "h", signed: false), mux(sig(:cond_149, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_150, width: 1), lit(77, width: 7, base: "h", signed: false), mux(sig(:cond_151, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_152, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_153, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_154, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_155, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_156, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_157, width: 1), lit(84, width: 7, base: "h", signed: false), mux(sig(:cond_158, width: 1), lit(85, width: 7, base: "h", signed: false), mux(sig(:cond_159, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_160, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_161, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_162, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_163, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_164, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_165, width: 1), lit(33, width: 7, base: "h", signed: false), mux(sig(:cond_166, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_167, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_168, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_169, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_170, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_171, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_172, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_173, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_174, width: 1), lit(87, width: 7, base: "h", signed: false), mux(sig(:cond_175, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_176, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_177, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_178, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_179, width: 1), lit(88, width: 7, base: "h", signed: false), mux(sig(:cond_180, width: 1), lit(89, width: 7, base: "h", signed: false), mux(sig(:cond_181, width: 1), lit(11, width: 7, base: "h", signed: false), mux(sig(:cond_182, width: 1), lit(89, width: 7, base: "h", signed: false), mux(sig(:cond_183, width: 1), lit(94, width: 7, base: "h", signed: false), mux(sig(:cond_184, width: 1), lit(97, width: 7, base: "h", signed: false), mux(sig(:cond_185, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_186, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_187, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_188, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_189, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_190, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_191, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_192, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_193, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_194, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_195, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_196, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_197, width: 1), lit(100, width: 7, base: "h", signed: false), mux(sig(:cond_198, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_199, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_200, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_201, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_202, width: 1), lit(99, width: 7, base: "h", signed: false), mux(sig(:cond_203, width: 1), lit(101, width: 7, base: "h", signed: false), mux(sig(:cond_204, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_205, width: 1), lit(102, width: 7, base: "h", signed: false), mux(sig(:cond_206, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_207, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_208, width: 1), sig(:mc_cmd, width: 7), mux(sig(:cond_209, width: 1), lit(109, width: 7, base: "h", signed: false), sig(:__VdfgRegularize_hca2350fd_0_101, width: 7))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                  )
                                                                                                                                                                                                )
                                                                                                                                                                                              )
                                                                                                                                                                                            )
                                                                                                                                                                                          )
                                                                                                                                                                                        )
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            )
                                                                                                                          )
                                                                                                                        )
                                                                                                                      )
                                                                                                                    )
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hca2350fd_0_7,
    (
        sig(:__VdfgRegularize_hca2350fd_0_5, width: 1) |
        sig(:__VdfgRegularize_hca2350fd_0_6, width: 1)
    )
  assign :__VdfgRegularize_hca2350fd_0_20,
    (
      ~sig(:glob_descriptor, width: 64)[44]
    )
  assign :__VdfgRegularize_hca2350fd_1_0,
    (
        sig(:mc_operand_32bit, width: 1) &
        (
            sig(:glob_param_3, width: 32)[17] &
            (
                lit(0, width: 2, base: "h", signed: false) ==
                sig(:cpl, width: 2)
            )
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
    assign(
      :mc_saved_command,
      mux(
        sig(:rst_n, width: 1),
        sig(:mc_saved_command_to_reg, width: 7),
        lit(0, width: 7, base: "h", signed: false)
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
      :mc_saved_cmdex,
      mux(
        sig(:rst_n, width: 1),
        sig(:mc_saved_cmdex_to_reg, width: 4),
        lit(0, width: 4, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

end
