# frozen_string_literal: true

class ReadCommands < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: read_commands

  def self._import_decl_kinds
    {
      __VdfgBinToOneHot_Pre_hb4cc6da5_0_0: :logic,
      __VdfgBinToOneHot_Tab_hb4cc6da5_0_0: :logic,
      __VdfgRegularize_h35124d34_0_0: :logic,
      __VdfgRegularize_h35124d34_0_1: :logic,
      __VdfgRegularize_h35124d34_0_10: :logic,
      __VdfgRegularize_h35124d34_0_100: :logic,
      __VdfgRegularize_h35124d34_0_101: :logic,
      __VdfgRegularize_h35124d34_0_102: :logic,
      __VdfgRegularize_h35124d34_0_103: :logic,
      __VdfgRegularize_h35124d34_0_104: :logic,
      __VdfgRegularize_h35124d34_0_105: :logic,
      __VdfgRegularize_h35124d34_0_106: :logic,
      __VdfgRegularize_h35124d34_0_107: :logic,
      __VdfgRegularize_h35124d34_0_108: :logic,
      __VdfgRegularize_h35124d34_0_109: :logic,
      __VdfgRegularize_h35124d34_0_11: :logic,
      __VdfgRegularize_h35124d34_0_110: :logic,
      __VdfgRegularize_h35124d34_0_111: :logic,
      __VdfgRegularize_h35124d34_0_112: :logic,
      __VdfgRegularize_h35124d34_0_113: :logic,
      __VdfgRegularize_h35124d34_0_114: :logic,
      __VdfgRegularize_h35124d34_0_115: :logic,
      __VdfgRegularize_h35124d34_0_116: :logic,
      __VdfgRegularize_h35124d34_0_117: :logic,
      __VdfgRegularize_h35124d34_0_118: :logic,
      __VdfgRegularize_h35124d34_0_119: :logic,
      __VdfgRegularize_h35124d34_0_12: :logic,
      __VdfgRegularize_h35124d34_0_120: :logic,
      __VdfgRegularize_h35124d34_0_121: :logic,
      __VdfgRegularize_h35124d34_0_122: :logic,
      __VdfgRegularize_h35124d34_0_123: :logic,
      __VdfgRegularize_h35124d34_0_124: :logic,
      __VdfgRegularize_h35124d34_0_125: :logic,
      __VdfgRegularize_h35124d34_0_126: :logic,
      __VdfgRegularize_h35124d34_0_127: :logic,
      __VdfgRegularize_h35124d34_0_128: :logic,
      __VdfgRegularize_h35124d34_0_129: :logic,
      __VdfgRegularize_h35124d34_0_13: :logic,
      __VdfgRegularize_h35124d34_0_130: :logic,
      __VdfgRegularize_h35124d34_0_131: :logic,
      __VdfgRegularize_h35124d34_0_132: :logic,
      __VdfgRegularize_h35124d34_0_133: :logic,
      __VdfgRegularize_h35124d34_0_134: :logic,
      __VdfgRegularize_h35124d34_0_135: :logic,
      __VdfgRegularize_h35124d34_0_136: :logic,
      __VdfgRegularize_h35124d34_0_137: :logic,
      __VdfgRegularize_h35124d34_0_138: :logic,
      __VdfgRegularize_h35124d34_0_139: :logic,
      __VdfgRegularize_h35124d34_0_14: :logic,
      __VdfgRegularize_h35124d34_0_140: :logic,
      __VdfgRegularize_h35124d34_0_141: :logic,
      __VdfgRegularize_h35124d34_0_142: :logic,
      __VdfgRegularize_h35124d34_0_143: :logic,
      __VdfgRegularize_h35124d34_0_144: :logic,
      __VdfgRegularize_h35124d34_0_145: :logic,
      __VdfgRegularize_h35124d34_0_146: :logic,
      __VdfgRegularize_h35124d34_0_147: :logic,
      __VdfgRegularize_h35124d34_0_148: :logic,
      __VdfgRegularize_h35124d34_0_149: :logic,
      __VdfgRegularize_h35124d34_0_15: :logic,
      __VdfgRegularize_h35124d34_0_150: :logic,
      __VdfgRegularize_h35124d34_0_151: :logic,
      __VdfgRegularize_h35124d34_0_152: :logic,
      __VdfgRegularize_h35124d34_0_153: :logic,
      __VdfgRegularize_h35124d34_0_154: :logic,
      __VdfgRegularize_h35124d34_0_155: :logic,
      __VdfgRegularize_h35124d34_0_156: :logic,
      __VdfgRegularize_h35124d34_0_157: :logic,
      __VdfgRegularize_h35124d34_0_158: :logic,
      __VdfgRegularize_h35124d34_0_159: :logic,
      __VdfgRegularize_h35124d34_0_16: :logic,
      __VdfgRegularize_h35124d34_0_160: :logic,
      __VdfgRegularize_h35124d34_0_161: :logic,
      __VdfgRegularize_h35124d34_0_162: :logic,
      __VdfgRegularize_h35124d34_0_163: :logic,
      __VdfgRegularize_h35124d34_0_164: :logic,
      __VdfgRegularize_h35124d34_0_165: :logic,
      __VdfgRegularize_h35124d34_0_166: :logic,
      __VdfgRegularize_h35124d34_0_167: :logic,
      __VdfgRegularize_h35124d34_0_168: :logic,
      __VdfgRegularize_h35124d34_0_169: :logic,
      __VdfgRegularize_h35124d34_0_17: :logic,
      __VdfgRegularize_h35124d34_0_170: :logic,
      __VdfgRegularize_h35124d34_0_171: :logic,
      __VdfgRegularize_h35124d34_0_172: :logic,
      __VdfgRegularize_h35124d34_0_173: :logic,
      __VdfgRegularize_h35124d34_0_174: :logic,
      __VdfgRegularize_h35124d34_0_175: :logic,
      __VdfgRegularize_h35124d34_0_176: :logic,
      __VdfgRegularize_h35124d34_0_177: :logic,
      __VdfgRegularize_h35124d34_0_178: :logic,
      __VdfgRegularize_h35124d34_0_179: :logic,
      __VdfgRegularize_h35124d34_0_18: :logic,
      __VdfgRegularize_h35124d34_0_180: :logic,
      __VdfgRegularize_h35124d34_0_181: :logic,
      __VdfgRegularize_h35124d34_0_182: :logic,
      __VdfgRegularize_h35124d34_0_183: :logic,
      __VdfgRegularize_h35124d34_0_184: :logic,
      __VdfgRegularize_h35124d34_0_185: :logic,
      __VdfgRegularize_h35124d34_0_186: :logic,
      __VdfgRegularize_h35124d34_0_187: :logic,
      __VdfgRegularize_h35124d34_0_188: :logic,
      __VdfgRegularize_h35124d34_0_189: :logic,
      __VdfgRegularize_h35124d34_0_19: :logic,
      __VdfgRegularize_h35124d34_0_190: :logic,
      __VdfgRegularize_h35124d34_0_191: :logic,
      __VdfgRegularize_h35124d34_0_192: :logic,
      __VdfgRegularize_h35124d34_0_193: :logic,
      __VdfgRegularize_h35124d34_0_194: :logic,
      __VdfgRegularize_h35124d34_0_195: :logic,
      __VdfgRegularize_h35124d34_0_196: :logic,
      __VdfgRegularize_h35124d34_0_197: :logic,
      __VdfgRegularize_h35124d34_0_198: :logic,
      __VdfgRegularize_h35124d34_0_199: :logic,
      __VdfgRegularize_h35124d34_0_2: :logic,
      __VdfgRegularize_h35124d34_0_20: :logic,
      __VdfgRegularize_h35124d34_0_200: :logic,
      __VdfgRegularize_h35124d34_0_201: :logic,
      __VdfgRegularize_h35124d34_0_202: :logic,
      __VdfgRegularize_h35124d34_0_203: :logic,
      __VdfgRegularize_h35124d34_0_204: :logic,
      __VdfgRegularize_h35124d34_0_205: :logic,
      __VdfgRegularize_h35124d34_0_206: :logic,
      __VdfgRegularize_h35124d34_0_207: :logic,
      __VdfgRegularize_h35124d34_0_208: :logic,
      __VdfgRegularize_h35124d34_0_209: :logic,
      __VdfgRegularize_h35124d34_0_21: :logic,
      __VdfgRegularize_h35124d34_0_210: :logic,
      __VdfgRegularize_h35124d34_0_211: :logic,
      __VdfgRegularize_h35124d34_0_212: :logic,
      __VdfgRegularize_h35124d34_0_213: :logic,
      __VdfgRegularize_h35124d34_0_214: :logic,
      __VdfgRegularize_h35124d34_0_215: :logic,
      __VdfgRegularize_h35124d34_0_216: :logic,
      __VdfgRegularize_h35124d34_0_217: :logic,
      __VdfgRegularize_h35124d34_0_218: :logic,
      __VdfgRegularize_h35124d34_0_219: :logic,
      __VdfgRegularize_h35124d34_0_22: :logic,
      __VdfgRegularize_h35124d34_0_220: :logic,
      __VdfgRegularize_h35124d34_0_221: :logic,
      __VdfgRegularize_h35124d34_0_222: :logic,
      __VdfgRegularize_h35124d34_0_223: :logic,
      __VdfgRegularize_h35124d34_0_224: :logic,
      __VdfgRegularize_h35124d34_0_225: :logic,
      __VdfgRegularize_h35124d34_0_226: :logic,
      __VdfgRegularize_h35124d34_0_227: :logic,
      __VdfgRegularize_h35124d34_0_228: :logic,
      __VdfgRegularize_h35124d34_0_229: :logic,
      __VdfgRegularize_h35124d34_0_23: :logic,
      __VdfgRegularize_h35124d34_0_230: :logic,
      __VdfgRegularize_h35124d34_0_231: :logic,
      __VdfgRegularize_h35124d34_0_232: :logic,
      __VdfgRegularize_h35124d34_0_233: :logic,
      __VdfgRegularize_h35124d34_0_234: :logic,
      __VdfgRegularize_h35124d34_0_235: :logic,
      __VdfgRegularize_h35124d34_0_236: :logic,
      __VdfgRegularize_h35124d34_0_237: :logic,
      __VdfgRegularize_h35124d34_0_238: :logic,
      __VdfgRegularize_h35124d34_0_239: :logic,
      __VdfgRegularize_h35124d34_0_24: :logic,
      __VdfgRegularize_h35124d34_0_240: :logic,
      __VdfgRegularize_h35124d34_0_241: :logic,
      __VdfgRegularize_h35124d34_0_242: :logic,
      __VdfgRegularize_h35124d34_0_243: :logic,
      __VdfgRegularize_h35124d34_0_244: :logic,
      __VdfgRegularize_h35124d34_0_245: :logic,
      __VdfgRegularize_h35124d34_0_246: :logic,
      __VdfgRegularize_h35124d34_0_247: :logic,
      __VdfgRegularize_h35124d34_0_248: :logic,
      __VdfgRegularize_h35124d34_0_249: :logic,
      __VdfgRegularize_h35124d34_0_25: :logic,
      __VdfgRegularize_h35124d34_0_250: :logic,
      __VdfgRegularize_h35124d34_0_251: :logic,
      __VdfgRegularize_h35124d34_0_252: :logic,
      __VdfgRegularize_h35124d34_0_253: :logic,
      __VdfgRegularize_h35124d34_0_254: :logic,
      __VdfgRegularize_h35124d34_0_255: :logic,
      __VdfgRegularize_h35124d34_0_256: :logic,
      __VdfgRegularize_h35124d34_0_257: :logic,
      __VdfgRegularize_h35124d34_0_258: :logic,
      __VdfgRegularize_h35124d34_0_259: :logic,
      __VdfgRegularize_h35124d34_0_26: :logic,
      __VdfgRegularize_h35124d34_0_260: :logic,
      __VdfgRegularize_h35124d34_0_261: :logic,
      __VdfgRegularize_h35124d34_0_262: :logic,
      __VdfgRegularize_h35124d34_0_263: :logic,
      __VdfgRegularize_h35124d34_0_264: :logic,
      __VdfgRegularize_h35124d34_0_27: :logic,
      __VdfgRegularize_h35124d34_0_28: :logic,
      __VdfgRegularize_h35124d34_0_29: :logic,
      __VdfgRegularize_h35124d34_0_3: :logic,
      __VdfgRegularize_h35124d34_0_30: :logic,
      __VdfgRegularize_h35124d34_0_31: :logic,
      __VdfgRegularize_h35124d34_0_32: :logic,
      __VdfgRegularize_h35124d34_0_33: :logic,
      __VdfgRegularize_h35124d34_0_34: :logic,
      __VdfgRegularize_h35124d34_0_35: :logic,
      __VdfgRegularize_h35124d34_0_36: :logic,
      __VdfgRegularize_h35124d34_0_37: :logic,
      __VdfgRegularize_h35124d34_0_38: :logic,
      __VdfgRegularize_h35124d34_0_39: :logic,
      __VdfgRegularize_h35124d34_0_4: :logic,
      __VdfgRegularize_h35124d34_0_40: :logic,
      __VdfgRegularize_h35124d34_0_41: :logic,
      __VdfgRegularize_h35124d34_0_42: :logic,
      __VdfgRegularize_h35124d34_0_43: :logic,
      __VdfgRegularize_h35124d34_0_44: :logic,
      __VdfgRegularize_h35124d34_0_45: :logic,
      __VdfgRegularize_h35124d34_0_46: :logic,
      __VdfgRegularize_h35124d34_0_47: :logic,
      __VdfgRegularize_h35124d34_0_48: :logic,
      __VdfgRegularize_h35124d34_0_49: :logic,
      __VdfgRegularize_h35124d34_0_5: :logic,
      __VdfgRegularize_h35124d34_0_50: :logic,
      __VdfgRegularize_h35124d34_0_51: :logic,
      __VdfgRegularize_h35124d34_0_52: :logic,
      __VdfgRegularize_h35124d34_0_53: :logic,
      __VdfgRegularize_h35124d34_0_54: :logic,
      __VdfgRegularize_h35124d34_0_55: :logic,
      __VdfgRegularize_h35124d34_0_56: :logic,
      __VdfgRegularize_h35124d34_0_57: :logic,
      __VdfgRegularize_h35124d34_0_58: :logic,
      __VdfgRegularize_h35124d34_0_59: :logic,
      __VdfgRegularize_h35124d34_0_6: :logic,
      __VdfgRegularize_h35124d34_0_60: :logic,
      __VdfgRegularize_h35124d34_0_61: :logic,
      __VdfgRegularize_h35124d34_0_62: :logic,
      __VdfgRegularize_h35124d34_0_63: :logic,
      __VdfgRegularize_h35124d34_0_64: :logic,
      __VdfgRegularize_h35124d34_0_65: :logic,
      __VdfgRegularize_h35124d34_0_66: :logic,
      __VdfgRegularize_h35124d34_0_67: :logic,
      __VdfgRegularize_h35124d34_0_68: :logic,
      __VdfgRegularize_h35124d34_0_69: :logic,
      __VdfgRegularize_h35124d34_0_7: :logic,
      __VdfgRegularize_h35124d34_0_70: :logic,
      __VdfgRegularize_h35124d34_0_71: :logic,
      __VdfgRegularize_h35124d34_0_72: :logic,
      __VdfgRegularize_h35124d34_0_73: :logic,
      __VdfgRegularize_h35124d34_0_74: :logic,
      __VdfgRegularize_h35124d34_0_75: :logic,
      __VdfgRegularize_h35124d34_0_76: :logic,
      __VdfgRegularize_h35124d34_0_77: :logic,
      __VdfgRegularize_h35124d34_0_78: :logic,
      __VdfgRegularize_h35124d34_0_79: :logic,
      __VdfgRegularize_h35124d34_0_8: :logic,
      __VdfgRegularize_h35124d34_0_80: :logic,
      __VdfgRegularize_h35124d34_0_81: :logic,
      __VdfgRegularize_h35124d34_0_82: :logic,
      __VdfgRegularize_h35124d34_0_83: :logic,
      __VdfgRegularize_h35124d34_0_84: :logic,
      __VdfgRegularize_h35124d34_0_85: :logic,
      __VdfgRegularize_h35124d34_0_86: :logic,
      __VdfgRegularize_h35124d34_0_87: :logic,
      __VdfgRegularize_h35124d34_0_88: :logic,
      __VdfgRegularize_h35124d34_0_89: :logic,
      __VdfgRegularize_h35124d34_0_9: :logic,
      __VdfgRegularize_h35124d34_0_90: :logic,
      __VdfgRegularize_h35124d34_0_91: :logic,
      __VdfgRegularize_h35124d34_0_92: :logic,
      __VdfgRegularize_h35124d34_0_93: :logic,
      __VdfgRegularize_h35124d34_0_94: :logic,
      __VdfgRegularize_h35124d34_0_95: :logic,
      __VdfgRegularize_h35124d34_0_96: :logic,
      __VdfgRegularize_h35124d34_0_97: :logic,
      __VdfgRegularize_h35124d34_0_98: :logic,
      __VdfgRegularize_h35124d34_0_99: :logic,
      _unused_ok: :wire,
      cond_0: :wire,
      cond_1: :wire,
      cond_10: :wire,
      cond_101: :wire,
      cond_103: :wire,
      cond_104: :wire,
      cond_105: :wire,
      cond_106: :wire,
      cond_107: :wire,
      cond_109: :wire,
      cond_11: :wire,
      cond_110: :wire,
      cond_112: :wire,
      cond_113: :wire,
      cond_114: :wire,
      cond_115: :wire,
      cond_116: :wire,
      cond_118: :wire,
      cond_119: :wire,
      cond_12: :wire,
      cond_120: :wire,
      cond_121: :wire,
      cond_124: :wire,
      cond_126: :wire,
      cond_127: :wire,
      cond_131: :wire,
      cond_133: :wire,
      cond_134: :wire,
      cond_135: :wire,
      cond_137: :wire,
      cond_139: :wire,
      cond_140: :wire,
      cond_142: :wire,
      cond_143: :wire,
      cond_144: :wire,
      cond_145: :wire,
      cond_147: :wire,
      cond_148: :wire,
      cond_149: :wire,
      cond_15: :wire,
      cond_150: :wire,
      cond_152: :wire,
      cond_154: :wire,
      cond_155: :wire,
      cond_156: :wire,
      cond_159: :wire,
      cond_160: :wire,
      cond_161: :wire,
      cond_162: :wire,
      cond_163: :wire,
      cond_165: :wire,
      cond_166: :wire,
      cond_167: :wire,
      cond_169: :wire,
      cond_17: :wire,
      cond_173: :wire,
      cond_176: :wire,
      cond_177: :wire,
      cond_178: :wire,
      cond_179: :wire,
      cond_18: :wire,
      cond_180: :wire,
      cond_181: :wire,
      cond_182: :wire,
      cond_183: :wire,
      cond_185: :wire,
      cond_187: :wire,
      cond_189: :wire,
      cond_190: :wire,
      cond_191: :wire,
      cond_192: :wire,
      cond_193: :wire,
      cond_194: :wire,
      cond_195: :wire,
      cond_196: :wire,
      cond_197: :wire,
      cond_198: :wire,
      cond_2: :wire,
      cond_20: :wire,
      cond_200: :wire,
      cond_203: :wire,
      cond_205: :wire,
      cond_206: :wire,
      cond_209: :wire,
      cond_21: :wire,
      cond_210: :wire,
      cond_212: :wire,
      cond_216: :wire,
      cond_217: :wire,
      cond_219: :wire,
      cond_220: :wire,
      cond_221: :wire,
      cond_222: :wire,
      cond_224: :wire,
      cond_225: :wire,
      cond_227: :wire,
      cond_232: :wire,
      cond_237: :wire,
      cond_239: :wire,
      cond_24: :wire,
      cond_241: :wire,
      cond_242: :wire,
      cond_243: :wire,
      cond_245: :wire,
      cond_246: :wire,
      cond_249: :wire,
      cond_251: :wire,
      cond_254: :wire,
      cond_255: :wire,
      cond_257: :wire,
      cond_258: :wire,
      cond_26: :wire,
      cond_27: :wire,
      cond_28: :wire,
      cond_29: :wire,
      cond_3: :wire,
      cond_32: :wire,
      cond_33: :wire,
      cond_34: :wire,
      cond_35: :wire,
      cond_37: :wire,
      cond_38: :wire,
      cond_39: :wire,
      cond_4: :wire,
      cond_40: :wire,
      cond_41: :wire,
      cond_43: :wire,
      cond_44: :wire,
      cond_47: :wire,
      cond_48: :wire,
      cond_49: :wire,
      cond_5: :wire,
      cond_51: :wire,
      cond_53: :wire,
      cond_54: :wire,
      cond_57: :wire,
      cond_58: :wire,
      cond_59: :wire,
      cond_6: :wire,
      cond_61: :wire,
      cond_63: :wire,
      cond_64: :wire,
      cond_65: :wire,
      cond_66: :wire,
      cond_67: :wire,
      cond_69: :wire,
      cond_7: :wire,
      cond_75: :wire,
      cond_76: :wire,
      cond_78: :wire,
      cond_79: :wire,
      cond_82: :wire,
      cond_83: :wire,
      cond_84: :wire,
      cond_88: :wire,
      cond_89: :wire,
      cond_90: :wire,
      cond_91: :wire,
      cond_92: :wire,
      cond_93: :wire,
      cond_94: :wire,
      cond_98: :wire,
      cond_99: :wire,
      rd_arith_modregrm_to_reg: :wire,
      rd_arith_modregrm_to_rm: :wire,
      rd_imul_modregrm_mutex_busy: :wire,
      rd_in_condition: :wire,
      rd_io_allow_1_fault: :wire,
      rd_io_allow_2_fault: :wire,
      rd_ss_esp_from_tss_386: :wire,
      rd_task_switch_linear_next: :wire,
      rd_task_switch_linear_reg: :reg
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :glob_descriptor, width: 64
  input :glob_param_1, width: 32
  input :glob_param_2, width: 32
  input :glob_param_3, width: 32
  input :glob_desc_base, width: 32
  input :glob_desc_limit, width: 32
  input :tr, width: 16
  input :tr_base, width: 32
  input :tr_cache, width: 64
  input :tr_cache_valid
  input :tr_limit, width: 32
  input :gdtr_base, width: 32
  input :idtr_base, width: 32
  input :ecx, width: 32
  input :edx, width: 32
  input :iopl, width: 2
  input :exc_vector, width: 8
  input :io_allow_check_needed
  input :cpl, width: 2
  input :cr0_pg
  input :real_mode
  input :v8086_mode
  input :protected_mode
  input :exe_mutex, width: 11
  input :rd_decoder, width: 88
  input :rd_cmd, width: 7
  input :rd_cmdex, width: 4
  input :rd_modregrm_mod, width: 2
  input :rd_operand_16bit
  input :rd_operand_32bit
  input :rd_memory_last, width: 32
  input :rd_prefix_group_1_rep, width: 2
  input :rd_address_16bit
  input :rd_address_32bit
  input :rd_ready
  input :dst_wire, width: 32
  input :rd_descriptor_not_in_limits
  input :rd_consumed, width: 4
  input :rd_mutex_busy_active
  input :rd_mutex_busy_memory
  input :rd_mutex_busy_eflags
  input :rd_mutex_busy_ebp
  input :rd_mutex_busy_esp
  input :rd_mutex_busy_edx
  input :rd_mutex_busy_ecx
  input :rd_mutex_busy_eax
  input :rd_mutex_busy_modregrm_reg
  input :rd_mutex_busy_modregrm_rm
  input :rd_mutex_busy_implicit_reg
  output :rd_extra_wire, width: 32
  output :rd_system_linear, width: 32
  output :rd_error_code, width: 16
  output :rd_ss_esp_from_tss_fault
  output :rd_waiting
  output :rd_req_memory
  output :rd_req_eflags
  output :rd_req_all
  output :rd_req_reg
  output :rd_req_rm
  output :rd_req_implicit_reg
  output :rd_req_reg_not_8bit
  output :rd_req_edi
  output :rd_req_esi
  output :rd_req_ebp
  output :rd_req_esp
  output :rd_req_ebx
  output :rd_req_edx_eax
  output :rd_req_edx
  output :rd_req_ecx
  output :rd_req_eax
  output :address_enter_init
  output :address_enter
  output :address_enter_last
  output :address_leave
  output :address_esi
  output :address_edi
  output :address_xlat_transform
  output :address_bits_transform
  output :address_stack_pop
  output :address_stack_pop_speedup
  output :address_stack_pop_next
  output :address_stack_pop_esp_prev
  output :address_stack_pop_for_call
  output :address_stack_save
  output :address_stack_add_4_to_saved
  output :address_stack_for_ret_first
  output :address_stack_for_ret_second
  output :address_stack_for_iret_first
  output :address_stack_for_iret_second
  output :address_stack_for_iret_third
  output :address_stack_for_iret_last
  output :address_stack_for_iret_to_v86
  output :address_stack_for_call_param_first
  output :address_ea_buffer
  output :address_ea_buffer_plus_2
  output :address_memoffset
  output :read_virtual
  output :read_rmw_virtual
  output :write_virtual_check
  output :read_system_descriptor
  output :read_system_word
  output :read_system_dword
  output :read_system_qword
  output :read_rmw_system_dword
  output :read_length_word
  output :read_length_dword
  input :read_for_rd_ready
  input :write_virtual_check_ready
  input :rd_address_effective_ready
  input :read_4, width: 32
  input :read_8, width: 64
  output :rd_src_is_memory
  output :rd_src_is_io
  output :rd_src_is_modregrm_imm
  output :rd_src_is_modregrm_imm_se
  output :rd_src_is_imm
  output :rd_src_is_imm_se
  output :rd_src_is_1
  output :rd_src_is_eax
  output :rd_src_is_ecx
  output :rd_src_is_cmdex
  output :rd_src_is_implicit_reg
  output :rd_src_is_rm
  output :rd_src_is_reg
  output :rd_dst_is_0
  output :rd_dst_is_modregrm_imm_se
  output :rd_dst_is_modregrm_imm
  output :rd_dst_is_memory
  output :rd_dst_is_memory_last
  output :rd_dst_is_eip
  output :rd_dst_is_eax
  output :rd_dst_is_edx_eax
  output :rd_dst_is_implicit_reg
  output :rd_dst_is_rm
  output :rd_dst_is_reg
  output :rd_glob_descriptor_set
  output :rd_glob_descriptor_value, width: 64
  output :rd_glob_descriptor_2_set
  output :rd_glob_descriptor_2_value, width: 64
  output :rd_glob_param_1_set
  output :rd_glob_param_1_value, width: 32
  output :rd_glob_param_2_set
  output :rd_glob_param_2_value, width: 32
  output :rd_glob_param_3_set
  output :rd_glob_param_3_value, width: 32
  output :rd_glob_param_4_set
  output :rd_glob_param_4_value, width: 32
  output :rd_glob_param_5_set
  output :rd_glob_param_5_value, width: 32
  output :io_read
  output :io_read_address, width: 16
  input :rd_io_ready
  output :rd_io_allow_fault

  # Signals

  signal :__VdfgBinToOneHot_Pre_hb4cc6da5_0_0, width: 7
  signal :__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 116
  signal :__VdfgRegularize_h35124d34_0_0
  signal :__VdfgRegularize_h35124d34_0_1, width: 32
  signal :__VdfgRegularize_h35124d34_0_10
  signal :__VdfgRegularize_h35124d34_0_100
  signal :__VdfgRegularize_h35124d34_0_101
  signal :__VdfgRegularize_h35124d34_0_102
  signal :__VdfgRegularize_h35124d34_0_103
  signal :__VdfgRegularize_h35124d34_0_104
  signal :__VdfgRegularize_h35124d34_0_105
  signal :__VdfgRegularize_h35124d34_0_106
  signal :__VdfgRegularize_h35124d34_0_107
  signal :__VdfgRegularize_h35124d34_0_108
  signal :__VdfgRegularize_h35124d34_0_109
  signal :__VdfgRegularize_h35124d34_0_11
  signal :__VdfgRegularize_h35124d34_0_110
  signal :__VdfgRegularize_h35124d34_0_111
  signal :__VdfgRegularize_h35124d34_0_112
  signal :__VdfgRegularize_h35124d34_0_113
  signal :__VdfgRegularize_h35124d34_0_114
  signal :__VdfgRegularize_h35124d34_0_115
  signal :__VdfgRegularize_h35124d34_0_116
  signal :__VdfgRegularize_h35124d34_0_117
  signal :__VdfgRegularize_h35124d34_0_118
  signal :__VdfgRegularize_h35124d34_0_119
  signal :__VdfgRegularize_h35124d34_0_12
  signal :__VdfgRegularize_h35124d34_0_120
  signal :__VdfgRegularize_h35124d34_0_121
  signal :__VdfgRegularize_h35124d34_0_122
  signal :__VdfgRegularize_h35124d34_0_123
  signal :__VdfgRegularize_h35124d34_0_124
  signal :__VdfgRegularize_h35124d34_0_125
  signal :__VdfgRegularize_h35124d34_0_126
  signal :__VdfgRegularize_h35124d34_0_127
  signal :__VdfgRegularize_h35124d34_0_128
  signal :__VdfgRegularize_h35124d34_0_129
  signal :__VdfgRegularize_h35124d34_0_13
  signal :__VdfgRegularize_h35124d34_0_130
  signal :__VdfgRegularize_h35124d34_0_131
  signal :__VdfgRegularize_h35124d34_0_132
  signal :__VdfgRegularize_h35124d34_0_133
  signal :__VdfgRegularize_h35124d34_0_134
  signal :__VdfgRegularize_h35124d34_0_135
  signal :__VdfgRegularize_h35124d34_0_136
  signal :__VdfgRegularize_h35124d34_0_137
  signal :__VdfgRegularize_h35124d34_0_138
  signal :__VdfgRegularize_h35124d34_0_139
  signal :__VdfgRegularize_h35124d34_0_14
  signal :__VdfgRegularize_h35124d34_0_140
  signal :__VdfgRegularize_h35124d34_0_141
  signal :__VdfgRegularize_h35124d34_0_142
  signal :__VdfgRegularize_h35124d34_0_143
  signal :__VdfgRegularize_h35124d34_0_144
  signal :__VdfgRegularize_h35124d34_0_145
  signal :__VdfgRegularize_h35124d34_0_146
  signal :__VdfgRegularize_h35124d34_0_147
  signal :__VdfgRegularize_h35124d34_0_148, width: 2
  signal :__VdfgRegularize_h35124d34_0_149, width: 32
  signal :__VdfgRegularize_h35124d34_0_15
  signal :__VdfgRegularize_h35124d34_0_150, width: 32
  signal :__VdfgRegularize_h35124d34_0_151, width: 16
  signal :__VdfgRegularize_h35124d34_0_152, width: 32
  signal :__VdfgRegularize_h35124d34_0_153, width: 30
  signal :__VdfgRegularize_h35124d34_0_154, width: 32
  signal :__VdfgRegularize_h35124d34_0_155
  signal :__VdfgRegularize_h35124d34_0_156
  signal :__VdfgRegularize_h35124d34_0_157
  signal :__VdfgRegularize_h35124d34_0_158
  signal :__VdfgRegularize_h35124d34_0_159
  signal :__VdfgRegularize_h35124d34_0_16
  signal :__VdfgRegularize_h35124d34_0_160
  signal :__VdfgRegularize_h35124d34_0_161
  signal :__VdfgRegularize_h35124d34_0_162
  signal :__VdfgRegularize_h35124d34_0_163
  signal :__VdfgRegularize_h35124d34_0_164
  signal :__VdfgRegularize_h35124d34_0_165
  signal :__VdfgRegularize_h35124d34_0_166
  signal :__VdfgRegularize_h35124d34_0_167
  signal :__VdfgRegularize_h35124d34_0_168
  signal :__VdfgRegularize_h35124d34_0_169
  signal :__VdfgRegularize_h35124d34_0_17
  signal :__VdfgRegularize_h35124d34_0_170
  signal :__VdfgRegularize_h35124d34_0_171
  signal :__VdfgRegularize_h35124d34_0_172
  signal :__VdfgRegularize_h35124d34_0_173
  signal :__VdfgRegularize_h35124d34_0_174
  signal :__VdfgRegularize_h35124d34_0_175
  signal :__VdfgRegularize_h35124d34_0_176
  signal :__VdfgRegularize_h35124d34_0_177
  signal :__VdfgRegularize_h35124d34_0_178
  signal :__VdfgRegularize_h35124d34_0_179
  signal :__VdfgRegularize_h35124d34_0_18
  signal :__VdfgRegularize_h35124d34_0_180
  signal :__VdfgRegularize_h35124d34_0_181
  signal :__VdfgRegularize_h35124d34_0_182
  signal :__VdfgRegularize_h35124d34_0_183
  signal :__VdfgRegularize_h35124d34_0_184
  signal :__VdfgRegularize_h35124d34_0_185
  signal :__VdfgRegularize_h35124d34_0_186
  signal :__VdfgRegularize_h35124d34_0_187
  signal :__VdfgRegularize_h35124d34_0_188
  signal :__VdfgRegularize_h35124d34_0_189
  signal :__VdfgRegularize_h35124d34_0_19
  signal :__VdfgRegularize_h35124d34_0_190
  signal :__VdfgRegularize_h35124d34_0_191
  signal :__VdfgRegularize_h35124d34_0_192
  signal :__VdfgRegularize_h35124d34_0_193
  signal :__VdfgRegularize_h35124d34_0_194
  signal :__VdfgRegularize_h35124d34_0_195
  signal :__VdfgRegularize_h35124d34_0_196
  signal :__VdfgRegularize_h35124d34_0_197
  signal :__VdfgRegularize_h35124d34_0_198
  signal :__VdfgRegularize_h35124d34_0_199
  signal :__VdfgRegularize_h35124d34_0_2
  signal :__VdfgRegularize_h35124d34_0_20
  signal :__VdfgRegularize_h35124d34_0_200
  signal :__VdfgRegularize_h35124d34_0_201
  signal :__VdfgRegularize_h35124d34_0_202
  signal :__VdfgRegularize_h35124d34_0_203
  signal :__VdfgRegularize_h35124d34_0_204
  signal :__VdfgRegularize_h35124d34_0_205
  signal :__VdfgRegularize_h35124d34_0_206
  signal :__VdfgRegularize_h35124d34_0_207
  signal :__VdfgRegularize_h35124d34_0_208
  signal :__VdfgRegularize_h35124d34_0_209
  signal :__VdfgRegularize_h35124d34_0_21
  signal :__VdfgRegularize_h35124d34_0_210
  signal :__VdfgRegularize_h35124d34_0_211
  signal :__VdfgRegularize_h35124d34_0_212
  signal :__VdfgRegularize_h35124d34_0_213
  signal :__VdfgRegularize_h35124d34_0_214
  signal :__VdfgRegularize_h35124d34_0_215
  signal :__VdfgRegularize_h35124d34_0_216
  signal :__VdfgRegularize_h35124d34_0_217
  signal :__VdfgRegularize_h35124d34_0_218
  signal :__VdfgRegularize_h35124d34_0_219
  signal :__VdfgRegularize_h35124d34_0_22
  signal :__VdfgRegularize_h35124d34_0_220
  signal :__VdfgRegularize_h35124d34_0_221
  signal :__VdfgRegularize_h35124d34_0_222
  signal :__VdfgRegularize_h35124d34_0_223
  signal :__VdfgRegularize_h35124d34_0_224
  signal :__VdfgRegularize_h35124d34_0_225
  signal :__VdfgRegularize_h35124d34_0_226
  signal :__VdfgRegularize_h35124d34_0_227
  signal :__VdfgRegularize_h35124d34_0_228
  signal :__VdfgRegularize_h35124d34_0_229
  signal :__VdfgRegularize_h35124d34_0_23
  signal :__VdfgRegularize_h35124d34_0_230
  signal :__VdfgRegularize_h35124d34_0_231
  signal :__VdfgRegularize_h35124d34_0_232
  signal :__VdfgRegularize_h35124d34_0_233
  signal :__VdfgRegularize_h35124d34_0_234
  signal :__VdfgRegularize_h35124d34_0_235
  signal :__VdfgRegularize_h35124d34_0_236
  signal :__VdfgRegularize_h35124d34_0_237
  signal :__VdfgRegularize_h35124d34_0_238
  signal :__VdfgRegularize_h35124d34_0_239
  signal :__VdfgRegularize_h35124d34_0_24
  signal :__VdfgRegularize_h35124d34_0_240
  signal :__VdfgRegularize_h35124d34_0_241
  signal :__VdfgRegularize_h35124d34_0_242
  signal :__VdfgRegularize_h35124d34_0_243
  signal :__VdfgRegularize_h35124d34_0_244
  signal :__VdfgRegularize_h35124d34_0_245
  signal :__VdfgRegularize_h35124d34_0_246
  signal :__VdfgRegularize_h35124d34_0_247
  signal :__VdfgRegularize_h35124d34_0_248
  signal :__VdfgRegularize_h35124d34_0_249
  signal :__VdfgRegularize_h35124d34_0_25
  signal :__VdfgRegularize_h35124d34_0_250
  signal :__VdfgRegularize_h35124d34_0_251
  signal :__VdfgRegularize_h35124d34_0_252
  signal :__VdfgRegularize_h35124d34_0_253
  signal :__VdfgRegularize_h35124d34_0_254
  signal :__VdfgRegularize_h35124d34_0_255
  signal :__VdfgRegularize_h35124d34_0_256
  signal :__VdfgRegularize_h35124d34_0_257
  signal :__VdfgRegularize_h35124d34_0_258
  signal :__VdfgRegularize_h35124d34_0_259
  signal :__VdfgRegularize_h35124d34_0_26
  signal :__VdfgRegularize_h35124d34_0_260
  signal :__VdfgRegularize_h35124d34_0_261
  signal :__VdfgRegularize_h35124d34_0_262
  signal :__VdfgRegularize_h35124d34_0_263, width: 32
  signal :__VdfgRegularize_h35124d34_0_264, width: 32
  signal :__VdfgRegularize_h35124d34_0_27
  signal :__VdfgRegularize_h35124d34_0_28
  signal :__VdfgRegularize_h35124d34_0_29
  signal :__VdfgRegularize_h35124d34_0_3
  signal :__VdfgRegularize_h35124d34_0_30
  signal :__VdfgRegularize_h35124d34_0_31
  signal :__VdfgRegularize_h35124d34_0_32
  signal :__VdfgRegularize_h35124d34_0_33
  signal :__VdfgRegularize_h35124d34_0_34
  signal :__VdfgRegularize_h35124d34_0_35
  signal :__VdfgRegularize_h35124d34_0_36
  signal :__VdfgRegularize_h35124d34_0_37
  signal :__VdfgRegularize_h35124d34_0_38
  signal :__VdfgRegularize_h35124d34_0_39
  signal :__VdfgRegularize_h35124d34_0_4
  signal :__VdfgRegularize_h35124d34_0_40
  signal :__VdfgRegularize_h35124d34_0_41
  signal :__VdfgRegularize_h35124d34_0_42
  signal :__VdfgRegularize_h35124d34_0_43
  signal :__VdfgRegularize_h35124d34_0_44
  signal :__VdfgRegularize_h35124d34_0_45
  signal :__VdfgRegularize_h35124d34_0_46
  signal :__VdfgRegularize_h35124d34_0_47
  signal :__VdfgRegularize_h35124d34_0_48
  signal :__VdfgRegularize_h35124d34_0_49
  signal :__VdfgRegularize_h35124d34_0_5
  signal :__VdfgRegularize_h35124d34_0_50
  signal :__VdfgRegularize_h35124d34_0_51
  signal :__VdfgRegularize_h35124d34_0_52
  signal :__VdfgRegularize_h35124d34_0_53
  signal :__VdfgRegularize_h35124d34_0_54
  signal :__VdfgRegularize_h35124d34_0_55
  signal :__VdfgRegularize_h35124d34_0_56
  signal :__VdfgRegularize_h35124d34_0_57
  signal :__VdfgRegularize_h35124d34_0_58
  signal :__VdfgRegularize_h35124d34_0_59
  signal :__VdfgRegularize_h35124d34_0_6
  signal :__VdfgRegularize_h35124d34_0_60
  signal :__VdfgRegularize_h35124d34_0_61
  signal :__VdfgRegularize_h35124d34_0_62, width: 32
  signal :__VdfgRegularize_h35124d34_0_63
  signal :__VdfgRegularize_h35124d34_0_64
  signal :__VdfgRegularize_h35124d34_0_65
  signal :__VdfgRegularize_h35124d34_0_66
  signal :__VdfgRegularize_h35124d34_0_67
  signal :__VdfgRegularize_h35124d34_0_68
  signal :__VdfgRegularize_h35124d34_0_69
  signal :__VdfgRegularize_h35124d34_0_7
  signal :__VdfgRegularize_h35124d34_0_70
  signal :__VdfgRegularize_h35124d34_0_71
  signal :__VdfgRegularize_h35124d34_0_72
  signal :__VdfgRegularize_h35124d34_0_73
  signal :__VdfgRegularize_h35124d34_0_74
  signal :__VdfgRegularize_h35124d34_0_75
  signal :__VdfgRegularize_h35124d34_0_76
  signal :__VdfgRegularize_h35124d34_0_77
  signal :__VdfgRegularize_h35124d34_0_78
  signal :__VdfgRegularize_h35124d34_0_79
  signal :__VdfgRegularize_h35124d34_0_8
  signal :__VdfgRegularize_h35124d34_0_80
  signal :__VdfgRegularize_h35124d34_0_81
  signal :__VdfgRegularize_h35124d34_0_82
  signal :__VdfgRegularize_h35124d34_0_83
  signal :__VdfgRegularize_h35124d34_0_84
  signal :__VdfgRegularize_h35124d34_0_85
  signal :__VdfgRegularize_h35124d34_0_86
  signal :__VdfgRegularize_h35124d34_0_87
  signal :__VdfgRegularize_h35124d34_0_88
  signal :__VdfgRegularize_h35124d34_0_89
  signal :__VdfgRegularize_h35124d34_0_9
  signal :__VdfgRegularize_h35124d34_0_90
  signal :__VdfgRegularize_h35124d34_0_91, width: 32
  signal :__VdfgRegularize_h35124d34_0_92
  signal :__VdfgRegularize_h35124d34_0_93, width: 64
  signal :__VdfgRegularize_h35124d34_0_94
  signal :__VdfgRegularize_h35124d34_0_95
  signal :__VdfgRegularize_h35124d34_0_96
  signal :__VdfgRegularize_h35124d34_0_97
  signal :__VdfgRegularize_h35124d34_0_98
  signal :__VdfgRegularize_h35124d34_0_99
  signal :_unused_ok
  signal :cond_0
  signal :cond_1
  signal :cond_10
  signal :cond_101
  signal :cond_103
  signal :cond_104
  signal :cond_105
  signal :cond_106
  signal :cond_107
  signal :cond_109
  signal :cond_11
  signal :cond_110
  signal :cond_112
  signal :cond_113
  signal :cond_114
  signal :cond_115
  signal :cond_116
  signal :cond_118
  signal :cond_119
  signal :cond_12
  signal :cond_120
  signal :cond_121
  signal :cond_124
  signal :cond_126
  signal :cond_127
  signal :cond_131
  signal :cond_133
  signal :cond_134
  signal :cond_135
  signal :cond_137
  signal :cond_139
  signal :cond_140
  signal :cond_142
  signal :cond_143
  signal :cond_144
  signal :cond_145
  signal :cond_147
  signal :cond_148
  signal :cond_149
  signal :cond_15
  signal :cond_150
  signal :cond_152
  signal :cond_154
  signal :cond_155
  signal :cond_156
  signal :cond_159
  signal :cond_160
  signal :cond_161
  signal :cond_162
  signal :cond_163
  signal :cond_165
  signal :cond_166
  signal :cond_167
  signal :cond_169
  signal :cond_17
  signal :cond_173
  signal :cond_176
  signal :cond_177
  signal :cond_178
  signal :cond_179
  signal :cond_18
  signal :cond_180
  signal :cond_181
  signal :cond_182
  signal :cond_183
  signal :cond_185
  signal :cond_187
  signal :cond_189
  signal :cond_190
  signal :cond_191
  signal :cond_192
  signal :cond_193
  signal :cond_194
  signal :cond_195
  signal :cond_196
  signal :cond_197
  signal :cond_198
  signal :cond_2
  signal :cond_20
  signal :cond_200
  signal :cond_203
  signal :cond_205
  signal :cond_206
  signal :cond_209
  signal :cond_21
  signal :cond_210
  signal :cond_212
  signal :cond_216
  signal :cond_217
  signal :cond_219
  signal :cond_220
  signal :cond_221
  signal :cond_222
  signal :cond_224
  signal :cond_225
  signal :cond_227
  signal :cond_232
  signal :cond_237
  signal :cond_239
  signal :cond_24
  signal :cond_241
  signal :cond_242
  signal :cond_243
  signal :cond_245
  signal :cond_246
  signal :cond_249
  signal :cond_251
  signal :cond_254
  signal :cond_255
  signal :cond_257
  signal :cond_258
  signal :cond_26
  signal :cond_27
  signal :cond_28
  signal :cond_29
  signal :cond_3
  signal :cond_32
  signal :cond_33
  signal :cond_34
  signal :cond_35
  signal :cond_37
  signal :cond_38
  signal :cond_39
  signal :cond_4
  signal :cond_40
  signal :cond_41
  signal :cond_43
  signal :cond_44
  signal :cond_47
  signal :cond_48
  signal :cond_49
  signal :cond_5
  signal :cond_51
  signal :cond_53
  signal :cond_54
  signal :cond_57
  signal :cond_58
  signal :cond_59
  signal :cond_6
  signal :cond_61
  signal :cond_63
  signal :cond_64
  signal :cond_65
  signal :cond_66
  signal :cond_67
  signal :cond_69
  signal :cond_7
  signal :cond_75
  signal :cond_76
  signal :cond_78
  signal :cond_79
  signal :cond_82
  signal :cond_83
  signal :cond_84
  signal :cond_88
  signal :cond_89
  signal :cond_90
  signal :cond_91
  signal :cond_92
  signal :cond_93
  signal :cond_94
  signal :cond_98
  signal :cond_99
  signal :rd_arith_modregrm_to_reg
  signal :rd_arith_modregrm_to_rm
  signal :rd_imul_modregrm_mutex_busy
  signal :rd_in_condition
  signal :rd_io_allow_1_fault
  signal :rd_io_allow_2_fault
  signal :rd_ss_esp_from_tss_386
  signal :rd_task_switch_linear_next, width: 32
  signal :rd_task_switch_linear_reg, width: 32

  # Assignments

  assign :rd_io_allow_1_fault,
    (
        sig(:cond_33, width: 1) &
        (
            (
              ~sig(:tr_cache_valid, width: 1)
            ) |
            (
                (
                    (
                        lit(9, width: 4, base: "h", signed: false) !=
                        sig(:tr_cache, width: 64)[43..40]
                    ) &
                    (
                        lit(11, width: 4, base: "h", signed: false) !=
                        sig(:tr_cache, width: 64)[43..40]
                    )
                ) |
                (
                    lit(103, width: 32, base: "h", signed: false) >
                    sig(:tr_limit, width: 32)
                )
            )
        )
    )
  assign :cond_33,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[11] &
        sig(:cond_26, width: 1)
    )
  assign :rd_io_allow_2_fault,
    (
        sig(:cond_35, width: 1) &
        (
            sig(:__VdfgRegularize_h35124d34_0_1, width: 32) >=
            sig(:tr_limit, width: 32)
        )
    )
  assign :cond_35,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[11] &
        sig(:cond_82, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_1,
    (
        lit(0, width: 16, base: "d", signed: false).concat(
          sig(:rd_memory_last, width: 32)[15..0]
        ) +
        lit(0, width: 19, base: "d", signed: false).concat(
        sig(:glob_param_1, width: 32)[15..3]
      )
    )
  assign :rd_io_allow_fault,
    (
        sig(:rd_io_allow_1_fault, width: 1) |
        sig(:rd_io_allow_2_fault, width: 1)
    )
  assign :rd_imul_modregrm_mutex_busy,
    (
        (
            sig(:rd_decoder, width: 88)[3] &
            sig(:rd_mutex_busy_modregrm_reg, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_h35124d34_0_2, width: 1) &
            sig(:rd_mutex_busy_eax, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_2,
    (
      ~sig(:rd_decoder, width: 88)[3]
    )
  assign :rd_arith_modregrm_to_rm,
    (
      ~sig(:rd_arith_modregrm_to_reg, width: 1)
    )
  assign :rd_arith_modregrm_to_reg,
    sig(:rd_decoder, width: 88)[1]
  assign :rd_in_condition,
    (
        (
            sig(:rd_mutex_busy_active, width: 1) &
            (
                sig(:__VdfgRegularize_h35124d34_0_4, width: 1) &
                sig(:__VdfgRegularize_h35124d34_0_3, width: 1)
            )
        ) |
        (
            sig(:cond_82, width: 1) &
            sig(:rd_mutex_busy_edx, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_4,
    (
      ~sig(:io_allow_check_needed, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_3,
    (
        sig(:cond_26, width: 1) |
        sig(:cond_82, width: 1)
    )
  assign :cond_82,
    (
        lit(1, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :rd_ss_esp_from_tss_386,
    (
        (
            lit(9, width: 4, base: "h", signed: false) ==
            sig(:tr_cache, width: 64)[43..40]
        ) |
        (
            lit(11, width: 4, base: "h", signed: false) ==
            sig(:tr_cache, width: 64)[43..40]
        )
    )
  assign :rd_ss_esp_from_tss_fault,
    (
        (
            sig(:__VdfgRegularize_h35124d34_0_6, width: 1) |
            sig(:__VdfgRegularize_h35124d34_0_7, width: 1)
        ) &
        (
            mux(
              sig(:rd_ss_esp_from_tss_386, width: 1),
              (
                  lit(11, width: 32, base: "h", signed: false) +
                  sig(:__VdfgRegularize_h35124d34_0_264, width: 32)
              ),
              (
                  lit(5, width: 32, base: "h", signed: false) +
                  sig(:__VdfgRegularize_h35124d34_0_263, width: 32)
              )
            ) >
            sig(:tr_limit, width: 32)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_6,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[4] &
        sig(:__VdfgRegularize_h35124d34_0_5, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_7,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[29] &
        sig(:cond_101, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_264,
    lit(0, width: 27, base: "d", signed: false).concat(
      sig(:glob_descriptor, width: 64)[46..45].concat(
        lit(0, width: 3, base: "h", signed: false)
      )
    )
  assign :__VdfgRegularize_h35124d34_0_263,
    lit(0, width: 28, base: "d", signed: false).concat(
      sig(:glob_descriptor, width: 64)[46..45].concat(
        lit(0, width: 2, base: "h", signed: false)
      )
    )
  assign :rd_task_switch_linear_next,
    mux(
      sig(:__VdfgRegularize_h35124d34_0_8, width: 1),
      (
          lit(2, width: 32, base: "h", signed: false) +
          sig(:rd_task_switch_linear_reg, width: 32)
      ),
      (
          lit(4, width: 32, base: "h", signed: false) +
          sig(:rd_task_switch_linear_reg, width: 32)
      )
    )
  assign :__VdfgRegularize_h35124d34_0_8,
    (
        lit(3, width: 4, base: "h", signed: false) >=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :cond_0,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[1] &
        sig(:cond_26, width: 1)
    )
  assign :cond_26,
    (
        lit(0, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_1,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:rd_modregrm_mod, width: 2)
    )
  assign :cond_2,
    (
        sig(:rd_mutex_busy_modregrm_reg, width: 1) |
        sig(:rd_mutex_busy_modregrm_rm, width: 1)
    )
  assign :cond_3,
    (
        lit(3, width: 2, base: "h", signed: false) !=
        sig(:rd_modregrm_mod, width: 2)
    )
  assign :cond_4,
    (
        sig(:rd_mutex_busy_memory, width: 1) |
        sig(:rd_mutex_busy_modregrm_reg, width: 1)
    )
  assign :cond_5,
    (
      ~sig(:read_for_rd_ready, width: 1)
    )
  assign :cond_6,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[1] &
        sig(:cond_82, width: 1)
    )
  assign :cond_7,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[3] &
        sig(:cond_26, width: 1)
    )
  assign :cond_10,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[3] &
        sig(:cond_82, width: 1)
    )
  assign :cond_11,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h35124d34_0_9, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_9,
    (
        sig(:cond_83, width: 1) |
        sig(:cond_12, width: 1)
    )
  assign :cond_12,
    (
        lit(5, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_15,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h35124d34_0_11, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_11,
    (
        lit(11, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_17,
    (
        lit(0, width: 14, base: "h", signed: false) !=
        sig(:glob_param_1, width: 32)[15..2]
    )
  assign :cond_18,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[4] &
        sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_10,
    (
        lit(3, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_20,
    (
      ~sig(:glob_param_1, width: 32)[2]
    )
  assign :cond_21,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[4] &
        sig(:cond_101, width: 1)
    )
  assign :cond_101,
    (
        lit(6, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_24,
    sig(:glob_param_3, width: 32)[19]
  assign :cond_27,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[6] &
        (
          ~sig(:rd_cmdex, width: 4)[3]
        )
    )
  assign :cond_28,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[6] &
        sig(:rd_cmdex, width: 4)[3]
    )
  assign :cond_29,
    (
      ~sig(:write_virtual_check_ready, width: 1)
    )
  assign :cond_32,
    (
      ~sig(:rd_address_effective_ready, width: 1)
    )
  assign :cond_34,
    (
        sig(:rd_io_allow_1_fault, width: 1) |
        sig(:rd_mutex_busy_active, width: 1)
    )
  assign :cond_37,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[13]
  assign :cond_38,
    (
        sig(:rd_mutex_busy_memory, width: 1) |
        sig(:cond_194, width: 1)
    )
  assign :cond_194,
    (
        sig(:rd_mutex_busy_ecx, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_0, width: 1)
    )
  assign :cond_39,
    (
      ~(
          sig(:__VdfgRegularize_h35124d34_0_0, width: 1) &
          (
              (
                  sig(:rd_address_16bit, width: 1) &
                  (
                      lit(0, width: 16, base: "h", signed: false) ==
                      sig(:ecx, width: 32)[15..0]
                  )
              ) |
              (
                  sig(:rd_address_32bit, width: 1) &
                  (
                      lit(0, width: 32, base: "h", signed: false) ==
                      sig(:ecx, width: 32)
                  )
              )
          )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_0,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:rd_prefix_group_1_rep, width: 2)
    )
  assign :cond_40,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[14] &
        (
            lit(1, width: 3, base: "h", signed: false) ==
            sig(:rd_cmdex, width: 4)[3..1]
        )
    )
  assign :cond_41,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[14] &
        (
            lit(0, width: 3, base: "h", signed: false) ==
            sig(:rd_cmdex, width: 4)[3..1]
        )
    )
  assign :cond_43,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[15] &
        (
            lit(2, width: 4, base: "h", signed: false) !=
            sig(:rd_cmdex, width: 4)
        )
    )
  assign :cond_44,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[16]
  assign :cond_47,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[17]
  assign :cond_48,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[18] &
        sig(:cond_26, width: 1)
    )
  assign :cond_49,
    (
        sig(:cond_32, width: 1) |
        sig(:rd_mutex_busy_memory, width: 1)
    )
  assign :cond_51,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[18] &
        sig(:cond_82, width: 1)
    )
  assign :cond_53,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[18] &
        sig(:cond_83, width: 1)
    )
  assign :cond_83,
    (
        lit(2, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_54,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[18] &
        sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
    )
  assign :cond_57,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[19]
  assign :cond_58,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[20]
  assign :cond_59,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[21]
  assign :cond_61,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[28] &
        sig(:__VdfgRegularize_h35124d34_0_11, width: 1)
    )
  assign :cond_63,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[28] &
        sig(:__VdfgRegularize_h35124d34_0_12, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_12,
    (
        lit(14, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_64,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[28] &
        sig(:cond_12, width: 1)
    )
  assign :cond_65,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[28] &
        sig(:cond_101, width: 1)
    )
  assign :cond_66,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[28] &
        sig(:cond_94, width: 1)
    )
  assign :cond_94,
    (
        lit(9, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_67,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[32] |
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[31]
    )
  assign :cond_69,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[33] &
        sig(:cond_26, width: 1)
    )
  assign :cond_75,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[34] &
        sig(:cond_26, width: 1)
    )
  assign :cond_76,
    (
        lit(9, width: 5, base: "h", signed: false) ==
        sig(:rd_cmd, width: 7)[6..2]
    )
  assign :cond_78,
    (
        sig(:rd_mutex_busy_memory, width: 1) |
        sig(:__VdfgRegularize_h35124d34_0_14, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_14,
    (
        sig(:cond_82, width: 1) &
        sig(:rd_mutex_busy_modregrm_reg, width: 1)
    )
  assign :cond_79,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[35] &
        (
            lit(2, width: 4, base: "h", signed: false) >=
            sig(:rd_cmdex, width: 4)
        )
    )
  assign :cond_84,
    (
        sig(:rd_mutex_busy_memory, width: 1) |
        (
            sig(:rd_mutex_busy_eflags, width: 1) &
            sig(:v8086_mode, width: 1)
        )
    )
  assign :cond_88,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[35] &
        sig(:cond_12, width: 1)
    )
  assign :cond_89,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[35] &
        sig(:cond_101, width: 1)
    )
  assign :cond_90,
    (
      ~sig(:rd_descriptor_not_in_limits, width: 1)
    )
  assign :cond_91,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[35] &
        (
            (
                lit(7, width: 4, base: "h", signed: false) <=
                sig(:rd_cmdex, width: 4)
            ) &
            (
                lit(9, width: 4, base: "h", signed: false) >=
                sig(:rd_cmdex, width: 4)
            )
        )
    )
  assign :cond_92,
    (
        lit(7, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_93,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_98,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[40] &
        (
            (
                lit(4, width: 4, base: "h", signed: false) <=
                sig(:rd_cmdex, width: 4)
            ) &
            (
                lit(6, width: 4, base: "h", signed: false) >=
                sig(:rd_cmdex, width: 4)
            )
        )
    )
  assign :cond_99,
    (
        lit(4, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_103,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[41] &
        sig(:cond_26, width: 1)
    )
  assign :cond_104,
    (
        sig(:rd_mutex_busy_esp, width: 1) |
        sig(:rd_mutex_busy_memory, width: 1)
    )
  assign :cond_105,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[41] &
        sig(:cond_82, width: 1)
    )
  assign :cond_106,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[41] &
        sig(:cond_83, width: 1)
    )
  assign :cond_107,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[43] |
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[42]
    )
  assign :cond_109,
    (
        sig(:__VdfgRegularize_h35124d34_0_16, width: 1) |
        sig(:rd_mutex_busy_memory, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_16,
    (
        sig(:rd_mutex_busy_eax, width: 1) |
        (
            sig(:rd_decoder, width: 88)[0] &
            sig(:rd_mutex_busy_edx, width: 1)
        )
    )
  assign :cond_110,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[44] &
        sig(:__VdfgRegularize_h35124d34_0_17, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_17,
    (
        lit(0, width: 4, base: "h", signed: false) !=
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_112,
    (
        sig(:rd_mutex_busy_ecx, width: 1) |
        sig(:rd_mutex_busy_modregrm_rm, width: 1)
    )
  assign :cond_113,
    (
        sig(:rd_mutex_busy_ecx, width: 1) |
        sig(:rd_mutex_busy_memory, width: 1)
    )
  assign :cond_114,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[45] &
        sig(:cond_26, width: 1)
    )
  assign :cond_115,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[45] &
        sig(:cond_82, width: 1)
    )
  assign :cond_116,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[46] &
        sig(:cond_26, width: 1)
    )
  assign :cond_118,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:cpl, width: 2)
    )
  assign :cond_119,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[46] &
        sig(:cond_99, width: 1)
    )
  assign :cond_120,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[46] &
        sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
    )
  assign :cond_121,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[47] |
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[48]
        ) &
        (
            sig(:cond_93, width: 1) |
            sig(:cond_94, width: 1)
        )
    )
  assign :cond_124,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[49]
  assign :cond_126,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[51]
  assign :cond_127,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[52]
  assign :cond_131,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[53] &
        sig(:cond_83, width: 1)
    )
  assign :cond_133,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[54] &
        sig(:cond_82, width: 1)
    )
  assign :cond_134,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[1..0]
    )
  assign :cond_135,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[54] &
        sig(:cond_26, width: 1)
    )
  assign :cond_137,
    (
        sig(:rd_imul_modregrm_mutex_busy, width: 1) |
        sig(:rd_mutex_busy_memory, width: 1)
    )
  assign :cond_139,
    (
        sig(:__VdfgRegularize_h35124d34_0_262, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_17, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_262,
    (
        lit(28, width: 6, base: "h", signed: false) ==
        sig(:rd_cmd, width: 7)[6..1]
    )
  assign :cond_140,
    (
        sig(:__VdfgRegularize_h35124d34_0_262, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :cond_142,
    (
        sig(:cond_113, width: 1) |
        sig(:rd_mutex_busy_modregrm_reg, width: 1)
    )
  assign :cond_143,
    (
        sig(:__VdfgRegularize_h35124d34_0_261, width: 1) &
        sig(:cond_82, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_261,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:rd_cmd, width: 7)[6..3]
    )
  assign :cond_144,
    (
        lit(7, width: 3, base: "h", signed: false) !=
        sig(:rd_decoder, width: 88)[5..3]
    )
  assign :cond_145,
    (
        sig(:rd_arith_modregrm_to_rm, width: 1) &
        sig(:cond_144, width: 1)
    )
  assign :cond_147,
    (
        sig(:__VdfgRegularize_h35124d34_0_261, width: 1) &
        sig(:cond_83, width: 1)
    )
  assign :cond_148,
    (
        lit(7, width: 3, base: "h", signed: false) !=
        sig(:rd_decoder, width: 88)[13..11]
    )
  assign :cond_149,
    (
        sig(:__VdfgRegularize_h35124d34_0_261, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :cond_150,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[59]
  assign :cond_152,
    (
        sig(:rd_mutex_busy_eax, width: 1) |
        sig(:rd_mutex_busy_memory, width: 1)
    )
  assign :cond_154,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[61] &
        sig(:cond_82, width: 1)
    )
  assign :cond_155,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[61] &
        sig(:cond_83, width: 1)
    )
  assign :cond_156,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[61] &
        sig(:cond_26, width: 1)
    )
  assign :cond_159,
    (
        sig(:real_mode, width: 1) |
        sig(:v8086_mode, width: 1)
    )
  assign :cond_160,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[63] &
        sig(:cond_83, width: 1)
    )
  assign :cond_161,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[63] &
        sig(:cond_92, width: 1)
    )
  assign :cond_162,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[72]
  assign :cond_163,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[73] &
        sig(:cond_26, width: 1)
    )
  assign :cond_165,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[73] &
        sig(:cond_82, width: 1)
    )
  assign :cond_166,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[73] &
        sig(:cond_83, width: 1)
    )
  assign :cond_167,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[74] &
        (
            sig(:cond_83, width: 1) |
            sig(:cond_82, width: 1)
        )
    )
  assign :cond_169,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[74] &
        sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
    )
  assign :cond_173,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[77] &
        (
            lit(3, width: 4, base: "h", signed: false) !=
            sig(:rd_cmdex, width: 4)
        )
    )
  assign :cond_176,
    (
      ~sig(:rd_io_ready, width: 1)
    )
  assign :cond_177,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[78]
  assign :cond_178,
    (
        sig(:__VdfgRegularize_h35124d34_0_260, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_260,
    (
        sig(:__VdfgRegularize_h35124d34_0_18, width: 1) |
        sig(:__VdfgRegularize_h35124d34_0_20, width: 1)
    )
  assign :cond_179,
    (
        sig(:__VdfgRegularize_h35124d34_0_260, width: 1) &
        sig(:cond_82, width: 1)
    )
  assign :cond_180,
    (
        sig(:cond_90, width: 1) &
        sig(:cond_17, width: 1)
    )
  assign :cond_181,
    (
        sig(:__VdfgRegularize_h35124d34_0_18, width: 1) &
        sig(:cond_83, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_18,
    (
        sig(:cond_182, width: 1) |
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[80]
    )
  assign :cond_182,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[79]
  assign :cond_183,
    sig(:exe_mutex, width: 11)[10]
  assign :cond_185,
    (
        sig(:__VdfgRegularize_h35124d34_0_20, width: 1) &
        sig(:cond_83, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_20,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[81] |
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[82]
    )
  assign :cond_187,
    (
        sig(:__VdfgRegularize_h35124d34_0_7, width: 1) |
        sig(:__VdfgRegularize_h35124d34_0_6, width: 1)
    )
  assign :cond_189,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[29] &
            sig(:cond_92, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[4] &
            sig(:__VdfgRegularize_h35124d34_0_21, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_21,
    (
        lit(13, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :cond_190,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[29] &
            sig(:cond_93, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[4] &
            sig(:__VdfgRegularize_h35124d34_0_12, width: 1)
        )
    )
  assign :cond_191,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[83]
  assign :cond_192,
    (
        sig(:rd_mutex_busy_eax, width: 1) |
        sig(:cond_194, width: 1)
    )
  assign :cond_193,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[84] &
        (
            sig(:cond_26, width: 1) |
            sig(:cond_83, width: 1)
        )
    )
  assign :cond_195,
    (
        sig(:cond_39, width: 1) &
        (
          ~(
              sig(:io_allow_check_needed, width: 1) &
              sig(:cond_26, width: 1)
          )
        )
    )
  assign :cond_196,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[84] &
        (
            sig(:cond_82, width: 1) |
            sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
        )
    )
  assign :cond_197,
    (
        sig(:rd_mutex_busy_edx, width: 1) |
        sig(:cond_194, width: 1)
    )
  assign :cond_198,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[85]
  assign :cond_200,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[86]
  assign :cond_203,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[88] &
        sig(:cond_26, width: 1)
    )
  assign :cond_205,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
        sig(:cond_26, width: 1)
    )
  assign :cond_206,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
        sig(:__VdfgRegularize_h35124d34_0_9, width: 1)
    )
  assign :cond_209,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
        sig(:cond_94, width: 1)
    )
  assign :cond_210,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
        sig(:__VdfgRegularize_h35124d34_0_12, width: 1)
    )
  assign :cond_212,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[89]
  assign :cond_216,
    (
        sig(:__VdfgRegularize_h35124d34_0_22, width: 1) &
        sig(:rd_arith_modregrm_to_reg, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_22,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[90] &
        sig(:cond_82, width: 1)
    )
  assign :cond_217,
    (
        sig(:rd_arith_modregrm_to_rm, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_22, width: 1)
    )
  assign :cond_219,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[90] &
        sig(:cond_83, width: 1)
    )
  assign :cond_220,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[90] &
        sig(:cond_26, width: 1)
    )
  assign :cond_221,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[91] |
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[92] |
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[93]
        )
    )
  assign :cond_222,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[94] &
        sig(:cond_26, width: 1)
    )
  assign :cond_224,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[97] &
        sig(:cond_26, width: 1)
    )
  assign :cond_225,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[97] &
        sig(:cond_82, width: 1)
    )
  assign :cond_227,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[99] &
        sig(:cond_101, width: 1)
    )
  assign :cond_232,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[99] &
        (
            (
                lit(12, width: 4, base: "h", signed: false) <=
                sig(:rd_cmdex, width: 4)
            ) &
            (
                lit(14, width: 4, base: "h", signed: false) >=
                sig(:rd_cmdex, width: 4)
            )
        )
    )
  assign :cond_237,
    (
        lit(101, width: 7, base: "h", signed: false) ==
        sig(:rd_cmd, width: 7)
    )
  assign :cond_239,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[102] &
        sig(:cond_26, width: 1)
    )
  assign :cond_241,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[102] &
        sig(:cond_83, width: 1)
    )
  assign :cond_242,
    (
        sig(:cond_20, width: 1) &
        sig(:cond_180, width: 1)
    )
  assign :cond_243,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[102] &
        (
            (
                lit(3, width: 4, base: "h", signed: false) <=
                sig(:rd_cmdex, width: 4)
            ) &
            (
                lit(8, width: 4, base: "h", signed: false) >=
                sig(:rd_cmdex, width: 4)
            )
        )
    )
  assign :cond_245,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[103]
  assign :cond_246,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[104] |
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[105]
    )
  assign :cond_249,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[106]
  assign :cond_251,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[109]
  assign :cond_254,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[110] &
        sig(:cond_26, width: 1)
    )
  assign :cond_255,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[110] &
        sig(:cond_82, width: 1)
    )
  assign :cond_257,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[112] |
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[113] |
            (
                sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[114] |
                sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[115]
            )
        )
    )
  assign :cond_258,
    (
        lit(58, width: 6, base: "h", signed: false) ==
        sig(:rd_cmd, width: 7)[6..1]
    )
  assign :rd_glob_param_5_set,
    (
        sig(:__VdfgRegularize_h35124d34_0_259, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_26, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_257, width: 1) |
                sig(:__VdfgRegularize_h35124d34_0_256, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_259,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:address_stack_pop_for_call, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_26,
    (
        sig(:cond_98, width: 1) &
        sig(:cond_12, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_257,
    (
        sig(:cond_90, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_258, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_256,
    (
        sig(:rd_descriptor_not_in_limits, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_258, width: 1)
    )
  assign :rd_glob_param_2_set,
    (
        sig(:cond_43, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_255, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_254, width: 1) |
                (
                    sig(:cond_64, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_27, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_252, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_251, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_28, width: 1) |
                                    (
                                        sig(:address_stack_for_iret_last, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_30, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_31, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_248, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_247, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h35124d34_0_246, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h35124d34_0_245, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h35124d34_0_34, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h35124d34_0_243, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h35124d34_0_35, width: 1) |
                                                                            (
                                                                                sig(:__VdfgRegularize_h35124d34_0_36, width: 1) |
                                                                                sig(:__VdfgRegularize_h35124d34_0_240, width: 1)
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_255,
    (
        sig(:cond_48, width: 1) &
        (
            (
              ~sig(:cond_49, width: 1)
            ) &
            sig(:rd_operand_16bit, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_254,
    (
        (
          ~sig(:rd_operand_16bit, width: 1)
        ) &
        sig(:cond_53, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_27,
    (
        sig(:cond_79, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_252,
    (
        sig(:cond_90, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_253, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_251,
    (
        sig(:rd_descriptor_not_in_limits, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_253, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_28,
    (
        sig(:cond_91, width: 1) &
        sig(:cond_94, width: 1)
    )
  assign :address_stack_for_iret_last,
    (
        sig(:cond_98, width: 1) &
        sig(:cond_101, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_30,
    (
        sig(:__VdfgRegularize_h35124d34_0_250, width: 1) &
        sig(:cond_159, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_31,
    (
        sig(:__VdfgRegularize_h35124d34_0_249, width: 1) &
        sig(:protected_mode, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_248,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_32, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_247,
    (
        sig(:__VdfgRegularize_h35124d34_0_33, width: 1) &
        sig(:cond_179, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_246,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_203, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_245,
    (
        sig(:cond_227, width: 1) &
        (
            sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
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
    )
  assign :__VdfgRegularize_h35124d34_0_34,
    (
        sig(:__VdfgRegularize_h35124d34_0_244, width: 1) &
        sig(:cond_242, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_243,
    (
        (
          ~sig(:cond_242, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_244, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_35,
    (
        sig(:__VdfgRegularize_h35124d34_0_242, width: 1) &
        sig(:v8086_mode, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_36,
    (
        sig(:__VdfgRegularize_h35124d34_0_241, width: 1) &
        sig(:cond_180, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_240,
    (
        sig(:__VdfgRegularize_h35124d34_0_33, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_241, width: 1)
    )
  assign :rd_req_all,
    (
        sig(:cond_251, width: 1) &
        (
            lit(7, width: 3, base: "h", signed: false) ==
            sig(:rd_cmdex, width: 4)[2..0]
        )
    )
  assign :rd_req_esp,
    (
        sig(:cond_27, width: 1) |
        (
            sig(:cond_43, width: 1) |
            (
                sig(:cond_75, width: 1) |
                (
                    sig(:cond_103, width: 1) |
                    (
                        sig(:cond_105, width: 1) |
                        (
                            sig(:cond_124, width: 1) |
                            (
                                sig(:address_enter_init, width: 1) |
                                (
                                    sig(:address_enter_last, width: 1) |
                                    (
                                        sig(:cond_131, width: 1) |
                                        (
                                            sig(:address_enter, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_239, width: 1) |
                                                (
                                                    sig(:cond_167, width: 1) |
                                                    (
                                                        sig(:rd_src_is_implicit_reg, width: 1) |
                                                        (
                                                            sig(:cond_169, width: 1) |
                                                            (
                                                                sig(:cond_200, width: 1) |
                                                                sig(:cond_222, width: 1)
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :address_enter_init,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[53] &
        sig(:cond_26, width: 1)
    )
  assign :address_enter_last,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[53] &
        sig(:cond_82, width: 1)
    )
  assign :address_enter,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[53] &
        sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_239,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:address_leave, width: 1)
    )
  assign :rd_src_is_implicit_reg,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[74] &
        sig(:cond_26, width: 1)
    )
  assign :rd_src_is_cmdex,
    (
        sig(:cond_124, width: 1) |
        (
            sig(:address_enter_init, width: 1) |
            (
                sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[100] &
                sig(:__VdfgRegularize_h35124d34_0_23, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_23,
    (
        lit(7, width: 4, base: "h", signed: false) >=
        sig(:rd_cmdex, width: 4)
    )
  assign :rd_req_implicit_reg,
    (
        sig(:cond_41, width: 1) |
        (
            sig(:cond_47, width: 1) |
            (
                sig(:cond_103, width: 1) |
                (
                    sig(:cond_163, width: 1) |
                    sig(:cond_220, width: 1)
                )
            )
        )
    )
  assign :rd_req_reg,
    (
        sig(:cond_6, width: 1) |
        (
            sig(:cond_54, width: 1) |
            (
                sig(:cond_133, width: 1) |
                mux(
                  sig(:cond_135, width: 1),
                  sig(:rd_decoder, width: 88)[3],
                  mux(
                    sig(:__VdfgRegularize_h35124d34_0_38, width: 1),
                    sig(:rd_arith_modregrm_to_reg, width: 1),
                    (
                        (
                            sig(:__VdfgRegularize_h35124d34_0_39, width: 1) &
                            (
                                sig(:cond_144, width: 1) &
                                sig(:rd_arith_modregrm_to_reg, width: 1)
                            )
                        ) |
                        (
                            sig(:cond_166, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_238, width: 1) |
                                (
                                    sig(:cond_216, width: 1) |
                                    (
                                        sig(:cond_245, width: 1) |
                                        sig(:cond_258, width: 1)
                                    )
                                )
                            )
                        )
                    )
                  )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_38,
    (
        sig(:__VdfgRegularize_h35124d34_0_37, width: 1) &
        sig(:cond_144, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_39,
    (
        sig(:cond_143, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_238,
    (
        sig(:cond_181, width: 1) &
        (
            sig(:__VdfgRegularize_h35124d34_0_40, width: 1) &
            (
                sig(:__VdfgRegularize_h35124d34_0_19, width: 1) &
                (
                    (
                        (
                          ~sig(:glob_param_2, width: 32)[2]
                        ) &
                        sig(:cond_182, width: 1)
                    ) |
                    (
                        (
                          ~sig(:glob_param_2, width: 32)[3]
                        ) &
                        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[80]
                    )
                )
            )
        )
    )
  assign :rd_dst_is_0,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[7]
  assign :address_esi,
    (
        sig(:cond_114, width: 1) |
        (
            sig(:cond_162, width: 1) |
            (
                sig(:cond_198, width: 1) |
                sig(:cond_249, width: 1)
            )
        )
    )
  assign :address_stack_save,
    (
        sig(:address_stack_for_call_param_first, width: 1) |
        (
            sig(:address_stack_for_iret_first, width: 1) |
            (
                sig(:address_stack_for_iret_to_v86, width: 1) |
                (
                    sig(:address_stack_for_iret_third, width: 1) |
                    (
                        sig(:address_stack_for_ret_first, width: 1) |
                        sig(:address_stack_pop_esp_prev, width: 1)
                    )
                )
            )
        )
    )
  assign :address_stack_for_call_param_first,
    (
        sig(:address_stack_pop_for_call, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :address_stack_for_iret_first,
    (
        sig(:cond_91, width: 1) &
        sig(:cond_92, width: 1)
    )
  assign :address_stack_for_iret_to_v86,
    (
        sig(:address_stack_add_4_to_saved, width: 1) &
        (
            lit(10, width: 4, base: "h", signed: false) ==
            sig(:rd_cmdex, width: 4)
        )
    )
  assign :address_stack_for_iret_third,
    (
        sig(:cond_98, width: 1) &
        sig(:cond_99, width: 1)
    )
  assign :address_stack_for_ret_first,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[63] &
        sig(:cond_82, width: 1)
    )
  assign :address_stack_pop_esp_prev,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[63] &
        sig(:cond_101, width: 1)
    )
  assign :read_rmw_virtual,
    (
        sig(:__VdfgRegularize_h35124d34_0_237, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_236, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_235, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_234, width: 1) |
                    mux(
                      sig(:__VdfgRegularize_h35124d34_0_233, width: 1),
                      sig(:__VdfgRegularize_h35124d34_0_47, width: 1),
                      (
                          sig(:__VdfgRegularize_h35124d34_0_232, width: 1) |
                          (
                              sig(:__VdfgRegularize_h35124d34_0_231, width: 1) |
                              (
                                  sig(:__VdfgRegularize_h35124d34_0_230, width: 1) |
                                  (
                                      sig(:address_enter_last, width: 1) |
                                      (
                                          sig(:__VdfgRegularize_h35124d34_0_229, width: 1) |
                                          (
                                              sig(:__VdfgRegularize_h35124d34_0_228, width: 1) |
                                              (
                                                  (
                                                      sig(:__VdfgRegularize_h35124d34_0_227, width: 1) &
                                                      sig(:cond_145, width: 1)
                                                  ) |
                                                  (
                                                      (
                                                          sig(:__VdfgRegularize_h35124d34_0_226, width: 1) &
                                                          sig(:cond_148, width: 1)
                                                      ) |
                                                      (
                                                          sig(:__VdfgRegularize_h35124d34_0_225, width: 1) |
                                                          (
                                                              sig(:__VdfgRegularize_h35124d34_0_224, width: 1) |
                                                              sig(:__VdfgRegularize_h35124d34_0_223, width: 1)
                                                          )
                                                      )
                                                  )
                                              )
                                          )
                                      )
                                  )
                              )
                          )
                      )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_237,
    (
        sig(:__VdfgRegularize_h35124d34_0_42, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_41, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_236,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_43, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_235,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_44, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_234,
    (
        sig(:__VdfgRegularize_h35124d34_0_42, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_45, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_233,
    (
        (
          ~sig(:cond_78, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_46, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_47,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:rd_cmd, width: 7)[1..0]
    )
  assign :__VdfgRegularize_h35124d34_0_232,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_48, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_231,
    (
        (
          ~sig(:cond_113, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_49, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_230,
    (
        sig(:__VdfgRegularize_h35124d34_0_42, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_50, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_229,
    (
        sig(:__VdfgRegularize_h35124d34_0_42, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_51, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_228,
    (
        (
          ~sig(:cond_142, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_52, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_227,
    (
        sig(:__VdfgRegularize_h35124d34_0_42, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_39, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_226,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_53, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_225,
    (
        sig(:__VdfgRegularize_h35124d34_0_42, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_54, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_224,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_55, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_223,
    (
        sig(:cond_193, width: 1) &
        (
            (
              ~sig(:cond_194, width: 1)
            ) &
            sig(:cond_195, width: 1)
        )
    )
  assign :address_stack_pop_speedup,
    (
        (
            sig(:cond_79, width: 1) &
            (
                lit(0, width: 4, base: "h", signed: false) <
                sig(:rd_cmdex, width: 4)
            )
        ) |
        mux(
          sig(:cond_160, width: 1),
          sig(:cond_159, width: 1),
          (
              sig(:cond_251, width: 1) &
              (
                  lit(0, width: 3, base: "h", signed: false) <
                  sig(:rd_cmdex, width: 4)[2..0]
              )
          )
        )
    )
  assign :io_read,
    sig(:rd_src_is_io, width: 1)
  assign :rd_src_is_io,
    (
        sig(:__VdfgRegularize_h35124d34_0_222, width: 1) |
        sig(:__VdfgRegularize_h35124d34_0_221, width: 1)
    )
  assign :address_leave,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[55]
  assign :rd_dst_is_eax,
    (
        sig(:__VdfgRegularize_h35124d34_0_220, width: 1) |
        (
            sig(:cond_67, width: 1) |
            (
                sig(:cond_149, width: 1) |
                (
                    sig(:cond_156, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_219, width: 1) |
                        sig(:__VdfgRegularize_h35124d34_0_57, width: 1)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_220,
    (
        sig(:cond_37, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_186, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_219,
    (
        sig(:rd_arith_modregrm_to_rm, width: 1) &
        sig(:address_memoffset, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_57,
    (
        sig(:address_xlat_transform, width: 1) |
        sig(:cond_257, width: 1)
    )
  assign :rd_src_is_imm,
    (
        sig(:cond_10, width: 1) |
        (
            (
                sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[3] &
                sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
            ) |
            (
                sig(:cond_67, width: 1) |
                (
                    sig(:cond_149, width: 1) |
                    (
                        sig(:cond_156, width: 1) |
                        (
                            sig(:cond_167, width: 1) |
                            (
                                (
                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
                                    sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
                                ) |
                                sig(:cond_220, width: 1)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :address_bits_transform,
    (
        sig(:cond_76, width: 1) &
        sig(:cond_82, width: 1)
    )
  assign :rd_src_is_1,
    (
        sig(:cond_40, width: 1) |
        (
            sig(:cond_41, width: 1) |
            (
                sig(:cond_110, width: 1) &
                sig(:cond_82, width: 1)
            )
        )
    )
  assign :read_system_dword,
    mux(
      sig(:cond_189, width: 1),
      sig(:rd_ss_esp_from_tss_386, width: 1),
      mux(
        sig(:__VdfgRegularize_h35124d34_0_218, width: 1),
        sig(:__VdfgRegularize_h35124d34_0_24, width: 1),
        (
            sig(:__VdfgRegularize_h35124d34_0_59, width: 1) &
            (
                sig(:__VdfgRegularize_h35124d34_0_24, width: 1) &
                sig(:__VdfgRegularize_h35124d34_0_23, width: 1)
            )
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_218,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_58, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_24,
    (
        lit(3, width: 4, base: "h", signed: false) <
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h35124d34_0_59,
    (
        sig(:cond_237, width: 1) &
        (
            (
                lit(12, width: 4, base: "h", signed: false) >=
                sig(:rd_cmdex, width: 4)
            ) |
            sig(:__VdfgRegularize_h35124d34_0_24, width: 1)
        )
    )
  assign :rd_req_eax,
    (
        sig(:cond_67, width: 1) |
        (
            sig(:cond_107, width: 1) |
            (
                sig(:cond_127, width: 1) |
                mux(
                  sig(:cond_135, width: 1),
                  sig(:__VdfgRegularize_h35124d34_0_2, width: 1),
                  (
                      (
                          sig(:cond_149, width: 1) &
                          sig(:cond_144, width: 1)
                      ) |
                      (
                          sig(:cond_150, width: 1) |
                          (
                              sig(:__VdfgRegularize_h35124d34_0_217, width: 1) |
                              (
                                  sig(:cond_163, width: 1) |
                                  (
                                      sig(:rd_req_ebx, width: 1) |
                                      (
                                          sig(:__VdfgRegularize_h35124d34_0_219, width: 1) |
                                          mux(
                                            sig(:cond_221, width: 1),
                                            (
                                              ~sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[93]
                                            ),
                                            (
                                                (
                                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[98] &
                                                    sig(:cond_26, width: 1)
                                                ) |
                                                sig(:__VdfgRegularize_h35124d34_0_57, width: 1)
                                            )
                                          )
                                      )
                                  )
                              )
                          )
                      )
                  )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_217,
    (
        sig(:cond_162, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_186, width: 1)
    )
  assign :rd_req_ebx,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[76]
  assign :rd_glob_param_3_value,
    mux(
      sig(:__VdfgRegularize_h35124d34_0_216, width: 1),
      lit(0, width: 32, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_h35124d34_0_60, width: 1),
        lit(0, width: 7, base: "d", signed: false).concat(
          (
              sig(:glob_param_3, width: 32)[24..20] -
              lit(1, width: 5, base: "h", signed: false)
          ).concat(
            sig(:glob_param_3, width: 32)[19..0]
          )
        ),
        mux(
          sig(:__VdfgRegularize_h35124d34_0_61, width: 1),
          sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
          mux(
            sig(:cond_89, width: 1),
            lit(0, width: 10, base: "d", signed: false).concat(
              sig(:rd_consumed, width: 4).concat(
                lit(0, width: 18, base: "h", signed: false)
              )
            ),
            mux(
              sig(:address_stack_for_iret_first, width: 1),
              sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
              mux(
                sig(:address_stack_for_iret_second, width: 1),
                sig(:glob_param_1, width: 32),
                mux(
                  sig(:address_stack_pop_esp_prev, width: 1),
                  sig(:glob_param_1, width: 32),
                  mux(
                    sig(:__VdfgRegularize_h35124d34_0_215, width: 1),
                    lit(0, width: 16, base: "d", signed: false).concat(
                      sig(:read_4, width: 32)[15..0]
                    ),
                    lit(0, width: 32, base: "h", signed: false)
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_216,
    (
        sig(:cond_15, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_170, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_60,
    (
        sig(:address_stack_pop_for_call, width: 1) &
        sig(:rd_ready, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_61,
    (
        sig(:cond_79, width: 1) &
        sig(:cond_83, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_62,
    mux(
      sig(:rd_operand_16bit, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:read_4, width: 32)[15..0]
      ),
      sig(:read_4, width: 32)
    )
  assign :address_stack_for_iret_second,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[40] &
        sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_215,
    (
        (
          ~sig(:rd_ss_esp_from_tss_fault, width: 1)
        ) &
        sig(:cond_187, width: 1)
    )
  assign :read_virtual,
    (
        sig(:__VdfgRegularize_h35124d34_0_214, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_213, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_259, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_220, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_212, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_255, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_64, width: 1) |
                                (
                                    sig(:cond_53, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_211, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_210, width: 1) |
                                            mux(
                                              sig(:__VdfgRegularize_h35124d34_0_233, width: 1),
                                              (
                                                  lit(0, width: 2, base: "h", signed: false) ==
                                                  sig(:rd_cmd, width: 7)[1..0]
                                              ),
                                              (
                                                  sig(:__VdfgRegularize_h35124d34_0_209, width: 1) |
                                                  (
                                                      sig(:cond_91, width: 1) |
                                                      (
                                                          sig(:address_stack_add_4_to_saved, width: 1) |
                                                          (
                                                              sig(:address_stack_for_iret_second, width: 1) |
                                                              (
                                                                  sig(:cond_98, width: 1) |
                                                                  (
                                                                      sig(:__VdfgRegularize_h35124d34_0_208, width: 1) |
                                                                      (
                                                                          sig(:__VdfgRegularize_h35124d34_0_207, width: 1) |
                                                                          (
                                                                              sig(:__VdfgRegularize_h35124d34_0_206, width: 1) |
                                                                              (
                                                                                  sig(:__VdfgRegularize_h35124d34_0_205, width: 1) |
                                                                                  (
                                                                                      sig(:rd_dst_is_memory_last, width: 1) |
                                                                                      (
                                                                                          sig(:__VdfgRegularize_h35124d34_0_204, width: 1) |
                                                                                          (
                                                                                              sig(:__VdfgRegularize_h35124d34_0_203, width: 1) |
                                                                                              (
                                                                                                  sig(:address_enter, width: 1) |
                                                                                                  (
                                                                                                      sig(:__VdfgRegularize_h35124d34_0_202, width: 1) |
                                                                                                      (
                                                                                                          sig(:__VdfgRegularize_h35124d34_0_201, width: 1) |
                                                                                                          (
                                                                                                              sig(:__VdfgRegularize_h35124d34_0_239, width: 1) |
                                                                                                              (
                                                                                                                  (
                                                                                                                      (
                                                                                                                        ~sig(:cond_145, width: 1)
                                                                                                                      ) &
                                                                                                                      sig(:__VdfgRegularize_h35124d34_0_227, width: 1)
                                                                                                                  ) |
                                                                                                                  (
                                                                                                                      (
                                                                                                                          (
                                                                                                                            ~sig(:cond_148, width: 1)
                                                                                                                          ) &
                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_226, width: 1)
                                                                                                                      ) |
                                                                                                                      (
                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_200, width: 1) |
                                                                                                                          (
                                                                                                                              sig(:__VdfgRegularize_h35124d34_0_199, width: 1) |
                                                                                                                              (
                                                                                                                                  sig(:__VdfgRegularize_h35124d34_0_198, width: 1) |
                                                                                                                                  (
                                                                                                                                      sig(:address_stack_pop_esp_prev, width: 1) |
                                                                                                                                      (
                                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_250, width: 1) |
                                                                                                                                          (
                                                                                                                                              sig(:__VdfgRegularize_h35124d34_0_249, width: 1) |
                                                                                                                                              (
                                                                                                                                                  sig(:cond_161, width: 1) |
                                                                                                                                                  (
                                                                                                                                                      sig(:__VdfgRegularize_h35124d34_0_217, width: 1) |
                                                                                                                                                      (
                                                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_197, width: 1) |
                                                                                                                                                          (
                                                                                                                                                              sig(:__VdfgRegularize_h35124d34_0_196, width: 1) |
                                                                                                                                                              (
                                                                                                                                                                  sig(:__VdfgRegularize_h35124d34_0_195, width: 1) |
                                                                                                                                                                  (
                                                                                                                                                                      sig(:__VdfgRegularize_h35124d34_0_194, width: 1) |
                                                                                                                                                                      (
                                                                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_193, width: 1) |
                                                                                                                                                                          (
                                                                                                                                                                              sig(:__VdfgRegularize_h35124d34_0_192, width: 1) |
                                                                                                                                                                              (
                                                                                                                                                                                  sig(:__VdfgRegularize_h35124d34_0_191, width: 1) |
                                                                                                                                                                                  (
                                                                                                                                                                                      sig(:__VdfgRegularize_h35124d34_0_190, width: 1) |
                                                                                                                                                                                      (
                                                                                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_189, width: 1) |
                                                                                                                                                                                          (
                                                                                                                                                                                              sig(:__VdfgRegularize_h35124d34_0_188, width: 1) |
                                                                                                                                                                                              (
                                                                                                                                                                                                  sig(:__VdfgRegularize_h35124d34_0_187, width: 1) |
                                                                                                                                                                                                  (
                                                                                                                                                                                                    sig(:__VdfgRegularize_h35124d34_0_185, width: 1) | (sig(:__VdfgRegularize_h35124d34_0_184, width: 1) | (sig(:__VdfgRegularize_h35124d34_0_183, width: 1) | sig(:__VdfgRegularize_h35124d34_0_182, width: 1)))
                                                                                                                                                                                                  )
                                                                                                                                                                                              )
                                                                                                                                                                                          )
                                                                                                                                                                                      )
                                                                                                                                                                                  )
                                                                                                                                                                              )
                                                                                                                                                                          )
                                                                                                                                                                      )
                                                                                                                                                                  )
                                                                                                                                                              )
                                                                                                                                                          )
                                                                                                                                                      )
                                                                                                                                                  )
                                                                                                                                              )
                                                                                                                                          )
                                                                                                                                      )
                                                                                                                                  )
                                                                                                                              )
                                                                                                                          )
                                                                                                                      )
                                                                                                                  )
                                                                                                              )
                                                                                                          )
                                                                                                      )
                                                                                                  )
                                                                                              )
                                                                                          )
                                                                                      )
                                                                                  )
                                                                              )
                                                                          )
                                                                      )
                                                                  )
                                                              )
                                                          )
                                                      )
                                                  )
                                              )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_214,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_63, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_213,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_11, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_212,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_43, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_64,
    (
        sig(:cond_51, width: 1) &
        sig(:rd_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_211,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_66, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_210,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_75, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_209,
    (
        sig(:cond_79, width: 1) &
        (
            (
              ~sig(:cond_84, width: 1)
            ) &
            (
                sig(:__VdfgRegularize_h35124d34_0_15, width: 1) |
                (
                    lit(3, width: 2, base: "h", signed: false) ==
                    sig(:iopl, width: 2)
                )
            )
        )
    )
  assign :address_stack_add_4_to_saved,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[35] &
        (
            lit(10, width: 4, base: "h", signed: false) <=
            sig(:rd_cmdex, width: 4)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_208,
    (
        sig(:__VdfgRegularize_h35124d34_0_67, width: 1) &
        sig(:cond_103, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_207,
    (
        sig(:__VdfgRegularize_h35124d34_0_67, width: 1) &
        sig(:cond_105, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_206,
    (
        (
          ~sig(:cond_109, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_68, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_205,
    (
        sig(:cond_114, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_186, width: 1)
    )
  assign :rd_dst_is_memory_last,
    (
        sig(:cond_39, width: 1) &
        sig(:cond_115, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_204,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_70, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_203,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_71, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_202,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_72, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_201,
    (
        (
          ~sig(:cond_137, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_73, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_200,
    (
        (
          ~sig(:cond_152, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_74, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_199,
    (
        sig(:__VdfgRegularize_h35124d34_0_42, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_75, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_198,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_76, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_250,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:address_stack_for_ret_first, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_249,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_160, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_197,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_77, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_196,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_78, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_195,
    (
        sig(:cond_198, width: 1) &
        (
            sig(:__VdfgRegularize_h35124d34_0_56, width: 1) &
            sig(:cond_195, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_194,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_79, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_193,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_206, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_192,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_219, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_191,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_80, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_190,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_222, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_189,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_224, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_188,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:cond_225, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_187,
    (
        sig(:cond_249, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_186, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_185,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_81, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_184,
    (
        sig(:__VdfgRegularize_h35124d34_0_67, width: 1) &
        sig(:cond_251, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_183,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:address_xlat_transform, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_182,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_82, width: 1)
    )
  assign :rd_glob_param_4_value,
    mux(
      sig(:address_stack_for_iret_third, width: 1),
      sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
      mux(
        sig(:cond_161, width: 1),
        sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
        mux(
          sig(:cond_189, width: 1),
          mux(
            sig(:rd_ss_esp_from_tss_386, width: 1),
            sig(:read_4, width: 32),
            lit(0, width: 16, base: "d", signed: false).concat(
              sig(:read_4, width: 32)[15..0]
            )
          ),
          lit(0, width: 32, base: "h", signed: false)
        )
      )
    )
  assign :address_stack_pop_for_call,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[5] &
        sig(:__VdfgRegularize_h35124d34_0_3, width: 1)
    )
  assign :rd_glob_param_5_value,
    mux(
      sig(:__VdfgRegularize_h35124d34_0_259, width: 1),
      sig(:read_4, width: 32),
      mux(
        sig(:__VdfgRegularize_h35124d34_0_26, width: 1),
        sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
        mux(
          sig(:__VdfgRegularize_h35124d34_0_257, width: 1),
          lit(0, width: 32, base: "h", signed: false),
          mux(
            sig(:__VdfgRegularize_h35124d34_0_256, width: 1),
            sig(:rd_descriptor_not_in_limits, width: 1),
            lit(0, width: 32, base: "h", signed: false)
          )
        )
      )
    )
  assign :write_virtual_check,
    (
        sig(:__VdfgRegularize_h35124d34_0_181, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_84, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_85, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_86, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_180, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_179, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_178, width: 1) |
                                sig(:cond_246, width: 1)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_181,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_83, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_84,
    (
        sig(:cond_106, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_85,
    (
        sig(:cond_116, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_86,
    (
        sig(:cond_126, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_180,
    (
        sig(:rd_arith_modregrm_to_reg, width: 1) &
        sig(:address_memoffset, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_179,
    (
        sig(:__VdfgRegularize_h35124d34_0_88, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_87, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_178,
    (
        sig(:__VdfgRegularize_h35124d34_0_88, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_89, width: 1)
    )
  assign :rd_req_esi,
    (
        sig(:__VdfgRegularize_h35124d34_0_205, width: 1) |
        (
            sig(:rd_dst_is_memory_last, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_217, width: 1) |
                (
                    (
                        sig(:read_for_rd_ready, width: 1) &
                        sig(:__VdfgRegularize_h35124d34_0_195, width: 1)
                    ) |
                    sig(:__VdfgRegularize_h35124d34_0_187, width: 1)
                )
            )
        )
    )
  assign :rd_dst_is_implicit_reg,
    sig(:rd_req_implicit_reg, width: 1)
  assign :rd_req_eflags,
    (
        sig(:cond_6, width: 1) |
        (
            sig(:rd_dst_is_0, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_177, width: 1) |
                (
                    sig(:cond_40, width: 1) |
                    (
                        sig(:cond_41, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_90, width: 1) |
                            (
                                sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[22] |
                                (
                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[24] |
                                    (
                                        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[23] |
                                        (
                                            (
                                                sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[25] |
                                                (
                                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[26] |
                                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[27]
                                                )
                                            ) |
                                            (
                                                sig(:cond_67, width: 1) |
                                                (
                                                    sig(:cond_76, width: 1) |
                                                    (
                                                        sig(:cond_110, width: 1) |
                                                        (
                                                            sig(:rd_src_is_ecx, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h35124d34_0_205, width: 1) |
                                                                (
                                                                    sig(:rd_dst_is_memory_last, width: 1) |
                                                                    (
                                                                        sig(:cond_127, width: 1) |
                                                                        (
                                                                            sig(:cond_133, width: 1) |
                                                                            (
                                                                                sig(:cond_135, width: 1) |
                                                                                (
                                                                                    sig(:cond_139, width: 1) |
                                                                                    (
                                                                                        sig(:cond_140, width: 1) |
                                                                                        (
                                                                                            sig(:cond_143, width: 1) |
                                                                                            (
                                                                                                sig(:cond_147, width: 1) |
                                                                                                (
                                                                                                    sig(:cond_149, width: 1) |
                                                                                                    (
                                                                                                        sig(:cond_150, width: 1) |
                                                                                                        (
                                                                                                            sig(:cond_154, width: 1) |
                                                                                                            (
                                                                                                                sig(:cond_155, width: 1) |
                                                                                                                (
                                                                                                                    sig(:cond_156, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:cond_181, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:cond_185, width: 1) |
                                                                                                                            (
                                                                                                                                sig(:cond_222, width: 1) |
                                                                                                                                (
                                                                                                                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[95] |
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[96] |
                                                                                                                                        (
                                                                                                                                            sig(:cond_257, width: 1) |
                                                                                                                                            sig(:cond_258, width: 1)
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_177,
    (
        sig(:read_for_rd_ready, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_220, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_90,
    (
        sig(:cond_44, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :rd_src_is_ecx,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[44] &
        sig(:cond_26, width: 1)
    )
  assign :rd_extra_wire,
    mux(
      (
          sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[3] &
          sig(:cond_101, width: 1)
      ),
      sig(:__VdfgRegularize_h35124d34_0_91, width: 32),
      mux(
        (
            sig(:cond_181, width: 1) &
            sig(:cond_182, width: 1)
        ),
        lit(0, width: 8, base: "d", signed: false).concat(
          sig(:glob_descriptor, width: 64)[55..40].concat(
            lit(0, width: 8, base: "h", signed: false)
          )
        ),
        mux(
          (
              (
                ~sig(:cond_182, width: 1)
              ) &
              sig(:cond_181, width: 1)
          ),
          sig(:glob_desc_limit, width: 32),
          mux(
            (
                sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
                sig(:cond_101, width: 1)
            ),
            sig(:__VdfgRegularize_h35124d34_0_91, width: 32),
            lit(0, width: 32, base: "h", signed: false)
          )
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_91,
    sig(:rd_decoder, width: 88)[55..24]
  assign :address_memoffset,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[90] &
        sig(:__VdfgRegularize_h35124d34_0_10, width: 1)
    )
  assign :rd_src_is_reg,
    (
        sig(:cond_0, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_90, width: 1) |
            mux(
              sig(:cond_76, width: 1),
              sig(:cond_82, width: 1),
              (
                  sig(:cond_127, width: 1) |
                  (
                      sig(:cond_139, width: 1) |
                      (
                          sig(:cond_140, width: 1) |
                          mux(
                            sig(:cond_143, width: 1),
                            sig(:rd_arith_modregrm_to_rm, width: 1),
                            (
                                sig(:cond_154, width: 1) |
                                (
                                    sig(:cond_165, width: 1) |
                                    sig(:cond_217, width: 1)
                                )
                            )
                          )
                      )
                  )
              )
            )
        )
    )
  assign :io_read_address,
    mux(
      sig(:cond_173, width: 1),
      mux(
        sig(:cond_26, width: 1),
        lit(0, width: 8, base: "d", signed: false).concat(
          sig(:rd_decoder, width: 88)[15..8]
        ),
        mux(
          sig(:cond_83, width: 1),
          sig(:glob_param_1, width: 32)[15..0],
          sig(:edx, width: 32)[15..0]
        )
      ),
      mux(
        sig(:cond_196, width: 1),
        sig(:edx, width: 32)[15..0],
        lit(0, width: 16, base: "h", signed: false)
      )
    )
  assign :rd_req_memory,
    mux(
      sig(:cond_6, width: 1),
      sig(:cond_3, width: 1),
      (
          sig(:cond_27, width: 1) |
          (
              sig(:__VdfgRegularize_h35124d34_0_83, width: 1) |
              (
                  sig(:__VdfgRegularize_h35124d34_0_236, width: 1) |
                  (
                      sig(:__VdfgRegularize_h35124d34_0_44, width: 1) |
                      (
                          sig(:__VdfgRegularize_h35124d34_0_45, width: 1) |
                          mux(
                            sig(:__VdfgRegularize_h35124d34_0_46, width: 1),
                            sig(:__VdfgRegularize_h35124d34_0_47, width: 1),
                            (
                                sig(:__VdfgRegularize_h35124d34_0_84, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_48, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_49, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_85, width: 1) |
                                            (
                                                sig(:cond_124, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_86, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_230, width: 1) |
                                                        (
                                                            sig(:address_enter_init, width: 1) |
                                                            (
                                                                sig(:cond_131, width: 1) |
                                                                (
                                                                    sig(:address_enter, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h35124d34_0_51, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h35124d34_0_52, width: 1) |
                                                                            (
                                                                                (
                                                                                    sig(:__VdfgRegularize_h35124d34_0_39, width: 1) &
                                                                                    sig(:cond_145, width: 1)
                                                                                ) |
                                                                                (
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h35124d34_0_53, width: 1) &
                                                                                        sig(:cond_148, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        (
                                                                                            sig(:cond_166, width: 1) &
                                                                                            sig(:cond_3, width: 1)
                                                                                        ) |
                                                                                        (
                                                                                            sig(:cond_167, width: 1) |
                                                                                            (
                                                                                                sig(:rd_src_is_implicit_reg, width: 1) |
                                                                                                (
                                                                                                    sig(:cond_169, width: 1) |
                                                                                                    (
                                                                                                        sig(:__VdfgRegularize_h35124d34_0_55, width: 1) |
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_h35124d34_0_176, width: 1) |
                                                                                                            (
                                                                                                                sig(:__VdfgRegularize_h35124d34_0_221, width: 1) |
                                                                                                                (
                                                                                                                    sig(:cond_200, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:__VdfgRegularize_h35124d34_0_180, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_h35124d34_0_87, width: 1) |
                                                                                                                            (
                                                                                                                                sig(:__VdfgRegularize_h35124d34_0_89, width: 1) |
                                                                                                                                (
                                                                                                                                    sig(:__VdfgRegularize_h35124d34_0_245, width: 1) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[100] &
                                                                                                                                            sig(:__VdfgRegularize_h35124d34_0_21, width: 1)
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            sig(:cond_246, width: 1) |
                                                                                                                                            sig(:__VdfgRegularize_h35124d34_0_187, width: 1)
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                          )
                      )
                  )
              )
          )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_83,
    (
        sig(:cond_28, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_44,
    (
        sig(:cond_40, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_45,
    (
        sig(:cond_44, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_46,
    (
        sig(:cond_76, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_48,
    (
        sig(:cond_110, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_49,
    (
        sig(:rd_src_is_ecx, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_51,
    (
        sig(:cond_139, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_52,
    (
        sig(:cond_140, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_53,
    (
        sig(:cond_147, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_55,
    (
        sig(:cond_177, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_176,
    (
        sig(:cond_191, width: 1) &
        (
            (
              ~sig(:cond_192, width: 1)
            ) &
            sig(:cond_39, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_221,
    (
        sig(:cond_196, width: 1) &
        (
            (
              ~sig(:cond_197, width: 1)
            ) &
            sig(:cond_195, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_87,
    (
        sig(:cond_217, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_89,
    (
        sig(:cond_219, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :rd_glob_param_3_set,
    (
        sig(:__VdfgRegularize_h35124d34_0_216, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_60, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_61, width: 1) |
                (
                    sig(:cond_89, width: 1) |
                    (
                        sig(:address_stack_for_iret_first, width: 1) |
                        (
                            sig(:address_stack_for_iret_second, width: 1) |
                            (
                                sig(:address_stack_pop_esp_prev, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_215, width: 1) |
                                    sig(:__VdfgRegularize_h35124d34_0_175, width: 1)
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_175,
    (
        sig(:cond_209, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_170, width: 1)
    )
  assign :rd_glob_descriptor_value,
    mux(
      sig(:__VdfgRegularize_h35124d34_0_216, width: 1),
      sig(:read_8, width: 64),
      mux(
        sig(:__VdfgRegularize_h35124d34_0_174, width: 1),
        sig(:read_8, width: 64),
        mux(
          sig(:__VdfgRegularize_h35124d34_0_173, width: 1),
          sig(:read_8, width: 64),
          mux(
            sig(:__VdfgRegularize_h35124d34_0_172, width: 1),
            sig(:read_8, width: 64),
            mux(
              sig(:__VdfgRegularize_h35124d34_0_171, width: 1),
              sig(:read_8, width: 64),
              mux(
                sig(:cond_66, width: 1),
                sig(:read_8, width: 64),
                mux(
                  sig(:__VdfgRegularize_h35124d34_0_92, width: 1),
                  sig(:__VdfgRegularize_h35124d34_0_93, width: 64),
                  mux(
                    sig(:__VdfgRegularize_h35124d34_0_94, width: 1),
                    (
                        lit(158329674399744, width: 64, base: "h", signed: false) |
                        lit(0, width: 28, base: "d", signed: false).concat(
                        sig(:glob_param_1, width: 32)[15..12]
                      ).concat(
                        (
                            sig(:glob_param_1, width: 32) <<
                            lit(20, width: 32, base: "h", signed: false)
                        )
                      )
                    ),
                    mux(
                      sig(:__VdfgRegularize_h35124d34_0_95, width: 1),
                      lit(17592186044416, width: 64, base: "h", signed: false),
                      mux(
                        sig(:__VdfgRegularize_h35124d34_0_169, width: 1),
                        sig(:read_8, width: 64),
                        mux(
                          sig(:__VdfgRegularize_h35124d34_0_252, width: 1),
                          sig(:read_8, width: 64),
                          mux(
                            sig(:__VdfgRegularize_h35124d34_0_248, width: 1),
                            sig(:read_8, width: 64),
                            mux(
                              sig(:__VdfgRegularize_h35124d34_0_257, width: 1),
                              sig(:read_8, width: 64),
                              mux(
                                sig(:__VdfgRegularize_h35124d34_0_96, width: 1),
                                sig(:read_8, width: 64),
                                mux(
                                  sig(:__VdfgRegularize_h35124d34_0_175, width: 1),
                                  sig(:read_8, width: 64),
                                  mux(
                                    sig(:__VdfgRegularize_h35124d34_0_168, width: 1),
                                    sig(:read_8, width: 64),
                                    mux(
                                      sig(:__VdfgRegularize_h35124d34_0_34, width: 1),
                                      sig(:read_8, width: 64),
                                      mux(
                                        sig(:__VdfgRegularize_h35124d34_0_35, width: 1),
                                        sig(:__VdfgRegularize_h35124d34_0_93, width: 64),
                                        mux(
                                          sig(:__VdfgRegularize_h35124d34_0_36, width: 1),
                                          sig(:read_8, width: 64),
                                          lit(0, width: 64, base: "h", signed: false)
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_174,
    (
        sig(:cond_20, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[4] &
            sig(:cond_99, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_173,
    (
        sig(:cond_21, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_170, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_172,
    (
        sig(:cond_20, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[28] &
            sig(:__VdfgRegularize_h35124d34_0_5, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_171,
    (
        sig(:cond_63, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_170, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_92,
    (
        sig(:cond_69, width: 1) &
        sig(:v8086_mode, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_93,
    (
        lit(267181325549568, width: 64, base: "h", signed: false) |
        lit(0, width: 28, base: "d", signed: false).concat(
        sig(:glob_param_1, width: 32)[15..12]
      ).concat(
        sig(:glob_param_1, width: 32)[11..0].concat(
          lit(65535, width: 20, base: "h", signed: false)
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_94,
    (
        sig(:cond_69, width: 1) &
        sig(:real_mode, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_95,
    (
        sig(:cond_69, width: 1) &
        sig(:protected_mode, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_169,
    (
        (
          ~(
              sig(:protected_mode, width: 1) &
              sig(:__VdfgRegularize_h35124d34_0_13, width: 1)
          )
        ) &
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[33] &
            sig(:cond_82, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_96,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[88] &
        (
            sig(:cond_82, width: 1) &
            sig(:cond_17, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_168,
    (
        sig(:cond_20, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
            (
                lit(15, width: 4, base: "h", signed: false) ==
                sig(:rd_cmdex, width: 4)
            )
        )
    )
  assign :rd_dst_is_eip,
    (
        sig(:cond_10, width: 1) |
        sig(:rd_src_is_imm_se, width: 1)
    )
  assign :rd_src_is_imm_se,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[87] &
        sig(:cond_82, width: 1)
    )
  assign :rd_src_is_memory,
    (
        sig(:__VdfgRegularize_h35124d34_0_63, width: 1) |
        (
            sig(:cond_11, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_236, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_167, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_220, width: 1) |
                        (
                            sig(:address_stack_add_4_to_saved, width: 1) |
                            (
                                sig(:cond_103, width: 1) |
                                (
                                    sig(:cond_105, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_206, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_205, width: 1) |
                                            (
                                                sig(:rd_dst_is_memory_last, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_70, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_71, width: 1) |
                                                        (
                                                            sig(:address_enter, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h35124d34_0_72, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h35124d34_0_201, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h35124d34_0_239, width: 1) |
                                                                        mux(
                                                                          sig(:__VdfgRegularize_h35124d34_0_39, width: 1),
                                                                          sig(:rd_arith_modregrm_to_reg, width: 1),
                                                                          (
                                                                              sig(:__VdfgRegularize_h35124d34_0_74, width: 1) |
                                                                              (
                                                                                  sig(:__VdfgRegularize_h35124d34_0_217, width: 1) |
                                                                                  (
                                                                                      sig(:__VdfgRegularize_h35124d34_0_77, width: 1) |
                                                                                      (
                                                                                          sig(:__VdfgRegularize_h35124d34_0_195, width: 1) |
                                                                                          (
                                                                                              sig(:__VdfgRegularize_h35124d34_0_79, width: 1) |
                                                                                              (
                                                                                                  sig(:cond_206, width: 1) |
                                                                                                  (
                                                                                                      sig(:__VdfgRegularize_h35124d34_0_219, width: 1) |
                                                                                                      (
                                                                                                          sig(:__VdfgRegularize_h35124d34_0_80, width: 1) |
                                                                                                          (
                                                                                                              sig(:cond_222, width: 1) |
                                                                                                              (
                                                                                                                  sig(:cond_224, width: 1) |
                                                                                                                  (
                                                                                                                      sig(:cond_225, width: 1) |
                                                                                                                      (
                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_218, width: 1) |
                                                                                                                          (
                                                                                                                              sig(:__VdfgRegularize_h35124d34_0_59, width: 1) |
                                                                                                                              (
                                                                                                                                  sig(:__VdfgRegularize_h35124d34_0_166, width: 1) |
                                                                                                                                  (
                                                                                                                                      sig(:__VdfgRegularize_h35124d34_0_187, width: 1) |
                                                                                                                                      (
                                                                                                                                          sig(:__VdfgRegularize_h35124d34_0_81, width: 1) |
                                                                                                                                          (
                                                                                                                                              sig(:__VdfgRegularize_h35124d34_0_184, width: 1) |
                                                                                                                                              (
                                                                                                                                                  sig(:address_xlat_transform, width: 1) |
                                                                                                                                                  sig(:__VdfgRegularize_h35124d34_0_82, width: 1)
                                                                                                                                              )
                                                                                                                                          )
                                                                                                                                      )
                                                                                                                                  )
                                                                                                                              )
                                                                                                                          )
                                                                                                                      )
                                                                                                                  )
                                                                                                              )
                                                                                                          )
                                                                                                      )
                                                                                                  )
                                                                                              )
                                                                                          )
                                                                                      )
                                                                                  )
                                                                              )
                                                                          )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_63,
    (
        sig(:cond_7, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_167,
    (
        (
          ~sig(:rd_io_allow_2_fault, width: 1)
        ) &
        sig(:cond_35, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_70,
    (
        sig(:__VdfgRegularize_h35124d34_0_69, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_71,
    (
        sig(:cond_121, width: 1) &
        sig(:cond_118, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_72,
    (
        sig(:cond_133, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_74,
    (
        sig(:cond_150, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_77,
    (
        sig(:cond_169, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_79,
    (
        sig(:cond_205, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_80,
    (
        sig(:cond_216, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_166,
    (
        sig(:cond_239, width: 1) &
        (
            sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
            (
                lit(0, width: 2, base: "h", signed: false) !=
                sig(:glob_param_1, width: 32)[17..16]
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_81,
    (
        sig(:rd_req_reg_not_8bit, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :address_xlat_transform,
    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[111]
  assign :__VdfgRegularize_h35124d34_0_82,
    (
        sig(:cond_258, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :read_system_qword,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_66, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_25,
    (
      ~sig(:rd_mutex_busy_active, width: 1)
    )
  assign :rd_dst_is_modregrm_imm,
    (
        sig(:__VdfgRegularize_h35124d34_0_97, width: 1) &
        sig(:cond_133, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_97,
    (
      ~sig(:cond_134, width: 1)
    )
  assign :address_stack_pop,
    (
        sig(:cond_43, width: 1) |
        (
            sig(:cond_75, width: 1) |
            (
                sig(:cond_79, width: 1) |
                (
                    sig(:cond_103, width: 1) |
                    (
                        sig(:cond_105, width: 1) |
                        mux(
                          sig(:address_stack_for_ret_first, width: 1),
                          sig(:cond_159, width: 1),
                          mux(
                            sig(:cond_160, width: 1),
                            sig(:cond_159, width: 1),
                            (
                                sig(:cond_222, width: 1) |
                                sig(:cond_251, width: 1)
                            )
                          )
                        )
                    )
                )
            )
        )
    )
  assign :rd_req_reg_not_8bit,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[108] |
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[107]
    )
  assign :rd_dst_is_rm,
    (
        sig(:__VdfgRegularize_h35124d34_0_98, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_99, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_100, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_165, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_90, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_103, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_104, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_105, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_106, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_107, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_108, width: 1) |
                                                (
                                                    sig(:cond_120, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_109, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h35124d34_0_164, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h35124d34_0_111, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h35124d34_0_112, width: 1) |
                                                                    mux(
                                                                      sig(:__VdfgRegularize_h35124d34_0_37, width: 1),
                                                                      sig(:rd_arith_modregrm_to_rm, width: 1),
                                                                      (
                                                                          sig(:__VdfgRegularize_h35124d34_0_113, width: 1) |
                                                                          (
                                                                              sig(:__VdfgRegularize_h35124d34_0_114, width: 1) |
                                                                              (
                                                                                  sig(:__VdfgRegularize_h35124d34_0_115, width: 1) |
                                                                                  (
                                                                                      sig(:__VdfgRegularize_h35124d34_0_116, width: 1) |
                                                                                      (
                                                                                          sig(:__VdfgRegularize_h35124d34_0_117, width: 1) |
                                                                                          (
                                                                                              sig(:__VdfgRegularize_h35124d34_0_163, width: 1) |
                                                                                              sig(:__VdfgRegularize_h35124d34_0_121, width: 1)
                                                                                          )
                                                                                      )
                                                                                  )
                                                                              )
                                                                          )
                                                                      )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_98,
    (
        sig(:cond_0, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_99,
    (
        sig(:cond_28, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_100,
    (
        sig(:rd_dst_is_0, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_165,
    (
        sig(:__VdfgRegularize_h35124d34_0_102, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_101, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_103,
    (
        sig(:__VdfgRegularize_h35124d34_0_65, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_104,
    (
        sig(:cond_76, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_105,
    (
        sig(:cond_106, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_106,
    (
        sig(:cond_110, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_107,
    (
        sig(:rd_src_is_ecx, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_108,
    (
        sig(:cond_116, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_109,
    (
        sig(:cond_126, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_164,
    (
        (
          ~sig(:cond_2, width: 1)
        ) &
        sig(:__VdfgRegularize_h35124d34_0_110, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_111,
    (
        sig(:cond_139, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_112,
    (
        sig(:cond_140, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_37,
    (
        sig(:cond_143, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_113,
    (
        sig(:cond_147, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_114,
    (
        sig(:cond_154, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_115,
    (
        sig(:cond_155, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_116,
    (
        sig(:cond_165, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_117,
    (
        sig(:cond_177, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_163,
    (
        sig(:__VdfgRegularize_h35124d34_0_102, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_118, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_121,
    (
        sig(:__VdfgRegularize_h35124d34_0_119, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_120, width: 1) |
            sig(:cond_254, width: 1)
        )
    )
  assign :rd_req_edx,
    (
        sig(:rd_req_ebx, width: 1) |
        (
            sig(:cond_221, width: 1) &
            sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[93]
        )
    )
  assign :__VdfgRegularize_h35124d34_0_222,
    (
        sig(:cond_173, width: 1) &
        (
            (
              ~sig(:rd_in_condition, width: 1)
            ) &
            (
                sig(:__VdfgRegularize_h35124d34_0_4, width: 1) |
                sig(:cond_83, width: 1)
            )
        )
    )
  assign :rd_src_is_eax,
    (
        sig(:cond_163, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_176, width: 1) |
            (
                sig(:cond_212, width: 1) |
                sig(:__VdfgRegularize_h35124d34_0_180, width: 1)
            )
        )
    )
  assign :address_stack_for_ret_second,
    sig(:address_stack_pop_esp_prev, width: 1)
  assign :rd_glob_param_1_set,
    (
        sig(:__VdfgRegularize_h35124d34_0_162, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_64, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_122, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_123, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_124, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_125, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_126, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_127, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_128, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_161, width: 1) |
                                            (
                                                sig(:cond_65, width: 1) |
                                                (
                                                    sig(:cond_75, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_129, width: 1) |
                                                        (
                                                            sig(:cond_88, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h35124d34_0_130, width: 1) |
                                                                mux(
                                                                  sig(:address_stack_for_iret_second, width: 1),
                                                                  sig(:rd_ready, width: 1),
                                                                  mux(
                                                                    sig(:address_stack_pop_esp_prev, width: 1),
                                                                    sig(:rd_ready, width: 1),
                                                                    (
                                                                        sig(:__VdfgRegularize_h35124d34_0_131, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h35124d34_0_132, width: 1) |
                                                                            (
                                                                                sig(:__VdfgRegularize_h35124d34_0_163, width: 1) |
                                                                                (
                                                                                    sig(:__VdfgRegularize_h35124d34_0_196, width: 1) |
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h35124d34_0_246, width: 1) |
                                                                                        sig(:__VdfgRegularize_h35124d34_0_160, width: 1)
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                  )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_162,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_18, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_122,
    (
        sig(:cond_53, width: 1) &
        sig(:rd_operand_16bit, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_123,
    (
        sig(:__VdfgRegularize_h35124d34_0_103, width: 1) &
        sig(:cond_57, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_124,
    (
        sig(:__VdfgRegularize_h35124d34_0_103, width: 1) &
        sig(:cond_58, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_125,
    (
        sig(:__VdfgRegularize_h35124d34_0_103, width: 1) &
        sig(:cond_59, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_126,
    (
        sig(:__VdfgRegularize_h35124d34_0_211, width: 1) &
        sig(:cond_57, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_127,
    (
        sig(:__VdfgRegularize_h35124d34_0_211, width: 1) &
        sig(:cond_58, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_128,
    (
        sig(:__VdfgRegularize_h35124d34_0_211, width: 1) &
        sig(:cond_59, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_161,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_61, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_129,
    (
        sig(:cond_79, width: 1) &
        sig(:cond_82, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_130,
    (
        sig(:cond_91, width: 1) &
        sig(:cond_93, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_131,
    (
        sig(:__VdfgRegularize_h35124d34_0_250, width: 1) &
        sig(:protected_mode, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_132,
    (
        sig(:__VdfgRegularize_h35124d34_0_249, width: 1) &
        sig(:cond_159, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_160,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_210, width: 1)
    )
  assign :rd_glob_param_4_set,
    (
        sig(:address_stack_for_iret_third, width: 1) |
        (
            sig(:cond_161, width: 1) |
            sig(:cond_189, width: 1)
        )
    )
  assign :address_stack_pop_next,
    (
        sig(:address_stack_pop_for_call, width: 1) |
        (
            sig(:cond_91, width: 1) |
            (
                sig(:address_stack_add_4_to_saved, width: 1) |
                (
                    sig(:address_stack_for_iret_second, width: 1) |
                    (
                        sig(:cond_98, width: 1) |
                        (
                            sig(:address_stack_pop_esp_prev, width: 1) |
                            mux(
                              sig(:address_stack_for_ret_first, width: 1),
                              sig(:protected_mode, width: 1),
                              mux(
                                sig(:cond_160, width: 1),
                                sig(:protected_mode, width: 1),
                                sig(:cond_161, width: 1)
                              )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :rd_req_edi,
    (
        sig(:__VdfgRegularize_h35124d34_0_177, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_205, width: 1) |
            (
                sig(:rd_dst_is_memory_last, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_176, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_221, width: 1) |
                        sig(:__VdfgRegularize_h35124d34_0_187, width: 1)
                    )
                )
            )
        )
    )
  assign :rd_glob_descriptor_set,
    (
        sig(:__VdfgRegularize_h35124d34_0_216, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_174, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_173, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_172, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_171, width: 1) |
                        (
                            sig(:cond_66, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_92, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_94, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_95, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_169, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_252, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_248, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_257, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h35124d34_0_96, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h35124d34_0_175, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h35124d34_0_168, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h35124d34_0_34, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h35124d34_0_35, width: 1) |
                                                                            sig(:__VdfgRegularize_h35124d34_0_36, width: 1)
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :read_system_word,
    (
        sig(:__VdfgRegularize_h35124d34_0_159, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_167, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_158, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_157, width: 1) |
                    (
                        sig(:cond_88, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_215, width: 1) |
                            mux(
                              sig(:cond_189, width: 1),
                              (
                                ~sig(:rd_ss_esp_from_tss_386, width: 1)
                              ),
                              mux(
                                sig(:__VdfgRegularize_h35124d34_0_218, width: 1),
                                sig(:__VdfgRegularize_h35124d34_0_8, width: 1),
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_59, width: 1) &
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_8, width: 1) |
                                        (
                                            lit(7, width: 4, base: "h", signed: false) <
                                            sig(:rd_cmdex, width: 4)
                                        )
                                    )
                                )
                              )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_159,
    (
        (
          ~sig(:cond_34, width: 1)
        ) &
        sig(:cond_33, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_158,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_64, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_157,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_65, width: 1)
    )
  assign :read_system_descriptor,
    (
        sig(:__VdfgRegularize_h35124d34_0_216, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_174, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_173, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_172, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_171, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_156, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_252, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_248, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_257, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_96, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_175, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_168, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_34, width: 1) |
                                                        sig(:__VdfgRegularize_h35124d34_0_36, width: 1)
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_156,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_169, width: 1)
    )
  assign :address_edi,
    (
        sig(:cond_37, width: 1) |
        (
            sig(:cond_115, width: 1) |
            sig(:cond_193, width: 1)
        )
    )
  assign :rd_waiting,
    (
        (
            sig(:__VdfgRegularize_h35124d34_0_98, width: 1) &
            sig(:cond_2, width: 1)
        ) |
        (
            (
                sig(:__VdfgRegularize_h35124d34_0_41, width: 1) &
                sig(:cond_4, width: 1)
            ) |
            (
                (
                    sig(:cond_5, width: 1) &
                    sig(:__VdfgRegularize_h35124d34_0_237, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgRegularize_h35124d34_0_133, width: 1) &
                        sig(:rd_mutex_busy_modregrm_rm, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_h35124d34_0_63, width: 1) &
                            sig(:rd_mutex_busy_memory, width: 1)
                        ) |
                        (
                            (
                                sig(:cond_5, width: 1) &
                                sig(:__VdfgRegularize_h35124d34_0_214, width: 1)
                            ) |
                            (
                                (
                                    sig(:cond_11, width: 1) &
                                    sig(:rd_mutex_busy_memory, width: 1)
                                ) |
                                (
                                    (
                                        sig(:cond_5, width: 1) &
                                        sig(:__VdfgRegularize_h35124d34_0_213, width: 1)
                                    ) |
                                    (
                                        (
                                            sig(:cond_15, width: 1) &
                                            sig(:rd_mutex_busy_active, width: 1)
                                        ) |
                                        (
                                            (
                                                sig(:cond_5, width: 1) &
                                                sig(:__VdfgRegularize_h35124d34_0_216, width: 1)
                                            ) |
                                            (
                                                (
                                                    sig(:cond_18, width: 1) &
                                                    sig(:rd_mutex_busy_active, width: 1)
                                                ) |
                                                (
                                                    (
                                                        sig(:cond_5, width: 1) &
                                                        sig(:__VdfgRegularize_h35124d34_0_174, width: 1)
                                                    ) |
                                                    (
                                                        (
                                                            sig(:cond_21, width: 1) &
                                                            sig(:rd_mutex_busy_active, width: 1)
                                                        ) |
                                                        (
                                                            (
                                                                sig(:cond_5, width: 1) &
                                                                sig(:__VdfgRegularize_h35124d34_0_173, width: 1)
                                                            ) |
                                                            (
                                                                (
                                                                    sig(:address_stack_pop_for_call, width: 1) &
                                                                    sig(:rd_mutex_busy_active, width: 1)
                                                                ) |
                                                                (
                                                                    (
                                                                        sig(:cond_5, width: 1) &
                                                                        sig(:__VdfgRegularize_h35124d34_0_259, width: 1)
                                                                    ) |
                                                                    (
                                                                        (
                                                                            sig(:__VdfgRegularize_h35124d34_0_83, width: 1) &
                                                                            sig(:rd_mutex_busy_memory, width: 1)
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:cond_29, width: 1) &
                                                                                sig(:__VdfgRegularize_h35124d34_0_181, width: 1)
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    sig(:__VdfgRegularize_h35124d34_0_100, width: 1) &
                                                                                    sig(:rd_mutex_busy_modregrm_rm, width: 1)
                                                                                ) |
                                                                                (
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h35124d34_0_43, width: 1) &
                                                                                        sig(:rd_mutex_busy_memory, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        (
                                                                                            sig(:cond_5, width: 1) &
                                                                                            sig(:__VdfgRegularize_h35124d34_0_236, width: 1)
                                                                                        ) |
                                                                                        (
                                                                                            (
                                                                                                sig(:cond_32, width: 1) &
                                                                                                (
                                                                                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[10] &
                                                                                                    sig(:cond_82, width: 1)
                                                                                                )
                                                                                            ) |
                                                                                            (
                                                                                                (
                                                                                                    sig(:cond_33, width: 1) &
                                                                                                    sig(:cond_34, width: 1)
                                                                                                ) |
                                                                                                (
                                                                                                    (
                                                                                                        sig(:cond_5, width: 1) &
                                                                                                        sig(:__VdfgRegularize_h35124d34_0_159, width: 1)
                                                                                                    ) |
                                                                                                    (
                                                                                                        (
                                                                                                            sig(:cond_35, width: 1) &
                                                                                                            sig(:rd_io_allow_2_fault, width: 1)
                                                                                                        ) |
                                                                                                        (
                                                                                                            (
                                                                                                                sig(:cond_5, width: 1) &
                                                                                                                sig(:__VdfgRegularize_h35124d34_0_167, width: 1)
                                                                                                            ) |
                                                                                                            (
                                                                                                                (
                                                                                                                    sig(:cond_37, width: 1) &
                                                                                                                    sig(:cond_38, width: 1)
                                                                                                                ) |
                                                                                                                (
                                                                                                                    (
                                                                                                                        sig(:cond_5, width: 1) &
                                                                                                                        sig(:__VdfgRegularize_h35124d34_0_220, width: 1)
                                                                                                                    ) |
                                                                                                                    (
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_h35124d34_0_101, width: 1) &
                                                                                                                            sig(:rd_mutex_busy_modregrm_rm, width: 1)
                                                                                                                        ) |
                                                                                                                        (
                                                                                                                            (
                                                                                                                                sig(:__VdfgRegularize_h35124d34_0_44, width: 1) &
                                                                                                                                sig(:rd_mutex_busy_memory, width: 1)
                                                                                                                            ) |
                                                                                                                            (
                                                                                                                                (
                                                                                                                                    sig(:cond_5, width: 1) &
                                                                                                                                    sig(:__VdfgRegularize_h35124d34_0_235, width: 1)
                                                                                                                                ) |
                                                                                                                                (
                                                                                                                                    (
                                                                                                                                        sig(:cond_41, width: 1) &
                                                                                                                                        sig(:rd_mutex_busy_implicit_reg, width: 1)
                                                                                                                                    ) |
                                                                                                                                    (
                                                                                                                                        (
                                                                                                                                            sig(:cond_43, width: 1) &
                                                                                                                                            sig(:rd_mutex_busy_memory, width: 1)
                                                                                                                                        ) |
                                                                                                                                        (
                                                                                                                                            (
                                                                                                                                                sig(:cond_5, width: 1) &
                                                                                                                                                sig(:__VdfgRegularize_h35124d34_0_212, width: 1)
                                                                                                                                            ) |
                                                                                                                                            (
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_h35124d34_0_90, width: 1) &
                                                                                                                                                    sig(:cond_2, width: 1)
                                                                                                                                                ) |
                                                                                                                                                (
                                                                                                                                                    (
                                                                                                                                                        sig(:__VdfgRegularize_h35124d34_0_45, width: 1) &
                                                                                                                                                        sig(:cond_4, width: 1)
                                                                                                                                                    ) |
                                                                                                                                                    (
                                                                                                                                                        (
                                                                                                                                                            sig(:cond_5, width: 1) &
                                                                                                                                                            sig(:__VdfgRegularize_h35124d34_0_234, width: 1)
                                                                                                                                                        ) |
                                                                                                                                                        (
                                                                                                                                                            (
                                                                                                                                                                sig(:cond_47, width: 1) &
                                                                                                                                                                sig(:rd_mutex_busy_implicit_reg, width: 1)
                                                                                                                                                            ) |
                                                                                                                                                            (
                                                                                                                                                                (
                                                                                                                                                                    sig(:cond_48, width: 1) &
                                                                                                                                                                    sig(:cond_49, width: 1)
                                                                                                                                                                ) |
                                                                                                                                                                (
                                                                                                                                                                    (
                                                                                                                                                                        sig(:cond_5, width: 1) &
                                                                                                                                                                        sig(:__VdfgRegularize_h35124d34_0_255, width: 1)
                                                                                                                                                                    ) |
                                                                                                                                                                    (
                                                                                                                                                                        (
                                                                                                                                                                            sig(:cond_5, width: 1) &
                                                                                                                                                                            sig(:__VdfgRegularize_h35124d34_0_64, width: 1)
                                                                                                                                                                        ) |
                                                                                                                                                                        (
                                                                                                                                                                            (
                                                                                                                                                                                sig(:cond_5, width: 1) &
                                                                                                                                                                                sig(:cond_53, width: 1)
                                                                                                                                                                            ) |
                                                                                                                                                                            (
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:__VdfgRegularize_h35124d34_0_103, width: 1) &
                                                                                                                                                                                    sig(:rd_mutex_busy_modregrm_rm, width: 1)
                                                                                                                                                                                ) |
                                                                                                                                                                                (
                                                                                                                                                                                    (
                                                                                                                                                                                        sig(:__VdfgRegularize_h35124d34_0_66, width: 1) &
                                                                                                                                                                                        sig(:rd_mutex_busy_memory, width: 1)
                                                                                                                                                                                    ) |
                                                                                                                                                                                    (
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:cond_5, width: 1) &
                                                                                                                                                                                            sig(:__VdfgRegularize_h35124d34_0_211, width: 1)
                                                                                                                                                                                        ) |
                                                                                                                                                                                        (
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:cond_61, width: 1) &
                                                                                                                                                                                                sig(:rd_mutex_busy_active, width: 1)
                                                                                                                                                                                            ) |
                                                                                                                                                                                            (
                                                                                                                                                                                                (
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :cond_5,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ) &
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :__VdfgRegularize_h35124d34_0_172,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    )
                                                                                                                                                                                                ) |
                                                                                                                                                                                                (
                                                                                                                                                                                                    (
                                                                                                                                                                                                      sig(:cond_63, width: 1) &
                                                                                                                                                                                                      sig(:rd_mutex_busy_active, width: 1)
                                                                                                                                                                                                    ) |
                                                                                                                                                                                                    (
                                                                                                                                                                                                      (sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_171, width: 1)) |
                                                                                                                                                                                                      ((sig(:cond_64, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_158, width: 1)) | ((sig(:cond_65, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_157, width: 1)) | ((sig(:cond_66, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:read_system_qword, width: 1)) | ((sig(:cond_67, width: 1) & sig(:rd_mutex_busy_eax, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_169, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_156, width: 1)) | ((sig(:cond_75, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_210, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_104, width: 1) & (sig(:rd_mutex_busy_modregrm_rm, width: 1) | sig(:__VdfgRegularize_h35124d34_0_14, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_46, width: 1) & sig(:cond_78, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_233, width: 1)) | ((sig(:cond_79, width: 1) & sig(:cond_84, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_209, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[35] & (sig(:cond_99, width: 1) & (sig(:rd_mutex_busy_eflags, width: 1) | sig(:rd_mutex_busy_memory, width: 1)))) | ((sig(:cond_5, width: 1) & sig(:cond_88, width: 1)) | ((sig(:cond_89, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_252, width: 1)) | ((sig(:cond_5, width: 1) & sig(:cond_91, width: 1)) | ((sig(:cond_5, width: 1) & sig(:address_stack_add_4_to_saved, width: 1)) | ((sig(:cond_5, width: 1) & sig(:address_stack_for_iret_second, width: 1)) | ((sig(:cond_5, width: 1) & sig(:cond_98, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[40] & ((lit(9, width: 4, base: "h", signed: false) <= sig(:rd_cmdex, width: 4)) & sig(:rd_mutex_busy_active, width: 1))) | ((sig(:cond_103, width: 1) & sig(:cond_104, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_208, width: 1)) | ((sig(:cond_105, width: 1) & sig(:cond_104, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_207, width: 1)) | ((sig(:cond_29, width: 1) & sig(:__VdfgRegularize_h35124d34_0_84, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_134, width: 1) & (sig(:__VdfgRegularize_h35124d34_0_16, width: 1) | sig(:rd_mutex_busy_modregrm_rm, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_68, width: 1) & sig(:cond_109, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_206, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_106, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_48, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_232, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_107, width: 1) & sig(:cond_112, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_49, width: 1) & sig(:cond_113, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_231, width: 1)) | ((sig(:cond_114, width: 1) & sig(:cond_38, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_205, width: 1)) | ((sig(:cond_5, width: 1) & sig(:rd_dst_is_memory_last, width: 1)) | ((sig(:cond_29, width: 1) & sig(:__VdfgRegularize_h35124d34_0_85, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_135, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_70, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_204, width: 1)) | ((sig(:cond_119, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_71, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_203, width: 1)) | ((sig(:cond_124, width: 1) & ((sig(:cond_26, width: 1) & sig(:rd_mutex_busy_eax, width: 1)) | ((sig(:cond_82, width: 1) & sig(:rd_mutex_busy_ecx, width: 1)) | (sig(:cond_83, width: 1) & sig(:rd_mutex_busy_edx, width: 1))))) | ((sig(:cond_29, width: 1) & sig(:__VdfgRegularize_h35124d34_0_86, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_110, width: 1) & sig(:cond_2, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_50, width: 1) & sig(:cond_4, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_230, width: 1)) | ((sig(:address_enter_init, width: 1) & sig(:rd_mutex_busy_ebp, width: 1)) | ((sig(:cond_5, width: 1) & sig(:address_enter_last, width: 1)) | ((sig(:cond_5, width: 1) & sig(:address_enter, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_136, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_72, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_202, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_137, width: 1) & (sig(:rd_imul_modregrm_mutex_busy, width: 1) | sig(:rd_mutex_busy_modregrm_rm, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_73, width: 1) & sig(:cond_137, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_201, width: 1)) | ((sig(:address_leave, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_239, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_111, width: 1) & sig(:cond_2, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_51, width: 1) & sig(:cond_4, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_229, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_112, width: 1) & (sig(:cond_112, width: 1) | sig(:rd_mutex_busy_modregrm_reg, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_52, width: 1) & sig(:cond_142, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_228, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_37, width: 1) & sig(:cond_2, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_39, width: 1) & sig(:cond_4, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_227, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_113, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_53, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_226, width: 1)) | ((sig(:cond_149, width: 1) & sig(:rd_mutex_busy_eax, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_138, width: 1) & (sig(:rd_mutex_busy_eax, width: 1) | sig(:rd_mutex_busy_modregrm_rm, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_74, width: 1) & sig(:cond_152, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_200, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_114, width: 1) & sig(:cond_2, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_75, width: 1) & sig(:cond_4, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_199, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_115, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_76, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_198, width: 1)) | ((sig(:cond_156, width: 1) & sig(:rd_mutex_busy_eax, width: 1)) | ((sig(:cond_5, width: 1) & sig(:address_stack_pop_esp_prev, width: 1)) | ((sig(:address_stack_for_ret_first, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_250, width: 1)) | ((sig(:cond_160, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_249, width: 1)) | ((sig(:cond_5, width: 1) & sig(:cond_161, width: 1)) | ((sig(:cond_162, width: 1) & sig(:cond_38, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_217, width: 1)) | ((sig(:cond_163, width: 1) & (sig(:rd_mutex_busy_eax, width: 1) | sig(:rd_mutex_busy_implicit_reg, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_116, width: 1) & sig(:cond_2, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_54, width: 1) & sig(:cond_4, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_225, width: 1)) | ((sig(:rd_src_is_implicit_reg, width: 1) & sig(:rd_mutex_busy_implicit_reg, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_139, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_77, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_197, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[75] & (sig(:cond_83, width: 1) & sig(:rd_mutex_busy_eflags, width: 1))) | ((sig(:rd_req_ebx, width: 1) & sig(:rd_mutex_busy_eax, width: 1)) | ((sig(:cond_173, width: 1) & sig(:rd_in_condition, width: 1)) | ((sig(:cond_176, width: 1) & sig(:__VdfgRegularize_h35124d34_0_222, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_117, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_55, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_224, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_118, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_78, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_196, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_32, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_248, width: 1)) | ((sig(:cond_181, width: 1) & sig(:cond_183, width: 1)) | ((sig(:cond_185, width: 1) & sig(:cond_183, width: 1)) | ((sig(:cond_187, width: 1) & sig(:rd_ss_esp_from_tss_fault, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_215, width: 1)) | ((sig(:cond_5, width: 1) & sig(:cond_189, width: 1)) | ((sig(:cond_190, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_257, width: 1)) | ((sig(:cond_191, width: 1) & sig(:cond_192, width: 1)) | ((sig(:cond_193, width: 1) & sig(:cond_194, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_223, width: 1)) | ((sig(:cond_196, width: 1) & sig(:cond_197, width: 1)) | ((sig(:cond_176, width: 1) & sig(:__VdfgRegularize_h35124d34_0_221, width: 1)) | ((sig(:cond_198, width: 1) & sig(:cond_38, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_195, width: 1)) | ((sig(:cond_203, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_96, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_140, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_79, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_194, width: 1)) | ((sig(:cond_206, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_193, width: 1)) | ((sig(:cond_209, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_175, width: 1)) | ((sig(:cond_210, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_168, width: 1)) | ((sig(:cond_212, width: 1) & sig(:rd_mutex_busy_eax, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_219, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_192, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_180, width: 1) & (sig(:cond_29, width: 1) | sig(:rd_mutex_busy_eax, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_141, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_80, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_191, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_119, width: 1) & sig(:rd_mutex_busy_modregrm_reg, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_87, width: 1) & sig(:rd_mutex_busy_modregrm_reg, width: 1)) | ((sig(:cond_29, width: 1) & sig(:__VdfgRegularize_h35124d34_0_179, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_120, width: 1) & sig(:rd_mutex_busy_modregrm_reg, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_89, width: 1) & sig(:rd_mutex_busy_modregrm_reg, width: 1)) | ((sig(:cond_29, width: 1) & sig(:__VdfgRegularize_h35124d34_0_178, width: 1)) | ((sig(:cond_222, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_190, width: 1)) | ((sig(:cond_224, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_189, width: 1)) | ((sig(:cond_225, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_188, width: 1)) | ((sig(:cond_227, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_245, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_155, width: 1)) | ((sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[99] & (sig(:cond_94, width: 1) & sig(:rd_mutex_busy_memory, width: 1))) | ((sig(:__VdfgRegularize_h35124d34_0_58, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_218, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_59, width: 1)) | ((sig(:cond_239, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_166, width: 1)) | ((sig(:cond_241, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_34, width: 1)) | ((sig(:cond_243, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_36, width: 1)) | ((sig(:cond_32, width: 1) & sig(:cond_245, width: 1)) | ((sig(:cond_29, width: 1) & sig(:cond_246, width: 1)) | ((sig(:cond_249, width: 1) & sig(:cond_38, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_187, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_142, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_81, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_185, width: 1)) | ((sig(:cond_251, width: 1) & sig(:cond_104, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_184, width: 1)) | ((sig(:cond_254, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:cond_255, width: 1) & sig(:rd_mutex_busy_active, width: 1)) | ((sig(:address_xlat_transform, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | ((sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_183, width: 1)) | ((sig(:cond_257, width: 1) & sig(:rd_mutex_busy_eax, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_143, width: 1) & sig(:rd_mutex_busy_modregrm_rm, width: 1)) | ((sig(:__VdfgRegularize_h35124d34_0_82, width: 1) & sig(:rd_mutex_busy_memory, width: 1)) | (sig(:cond_5, width: 1) & sig(:__VdfgRegularize_h35124d34_0_182, width: 1)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                )
                                                                                                                                                                                            )
                                                                                                                                                                                        )
                                                                                                                                                                                    )
                                                                                                                                                                                )
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    )
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_41,
    (
        sig(:cond_0, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_133,
    (
        sig(:cond_7, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_43,
    (
        sig(:rd_dst_is_0, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_101,
    (
        sig(:cond_40, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_66,
    (
        sig(:__VdfgRegularize_h35124d34_0_65, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_134,
    (
        sig(:cond_107, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_68,
    (
        sig(:cond_107, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_135,
    (
        sig(:__VdfgRegularize_h35124d34_0_69, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_110,
    (
        sig(:cond_127, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_50,
    (
        sig(:cond_127, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_136,
    (
        sig(:cond_133, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_137,
    (
        sig(:cond_135, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_73,
    (
        sig(:cond_135, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_138,
    (
        sig(:cond_150, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_75,
    (
        sig(:cond_154, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_76,
    (
        sig(:cond_155, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_54,
    (
        sig(:cond_165, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_139,
    (
        sig(:cond_169, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_118,
    (
        sig(:cond_178, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_78,
    (
        sig(:cond_178, width: 1) &
        sig(:cond_3, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_32,
    (
        sig(:cond_179, width: 1) &
        sig(:cond_180, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_140,
    (
        sig(:cond_205, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_141,
    (
        sig(:cond_216, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_119,
    (
        sig(:cond_217, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_120,
    (
        sig(:cond_219, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_155,
    (
        sig(:__VdfgRegularize_h35124d34_0_29, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_245, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_58,
    (
        sig(:cond_232, width: 1) &
        (
            (
                lit(12, width: 4, base: "h", signed: false) !=
                sig(:rd_cmdex, width: 4)
            ) |
            (
                sig(:__VdfgRegularize_h35124d34_0_24, width: 1) &
                sig(:cr0_pg, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_142,
    (
        sig(:rd_req_reg_not_8bit, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_143,
    (
        sig(:cond_258, width: 1) &
        sig(:cond_1, width: 1)
    )
  assign :address_ea_buffer,
    (
        sig(:__VdfgRegularize_h35124d34_0_144, width: 1) |
        (
            sig(:cond_51, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_122, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_145, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_146, width: 1) |
                        (
                            sig(:cond_225, width: 1) |
                            sig(:__VdfgRegularize_h35124d34_0_147, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_144,
    (
        sig(:cond_11, width: 1) &
        sig(:cond_12, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_145,
    (
        sig(:cond_121, width: 1) &
        sig(:cond_94, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_146,
    (
        sig(:cond_206, width: 1) &
        sig(:cond_12, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_147,
    (
        sig(:cond_246, width: 1) &
        sig(:cond_82, width: 1)
    )
  assign :rd_req_ecx,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[60] |
        sig(:rd_req_ebx, width: 1)
    )
  assign :read_rmw_system_dword,
    (
        sig(:__VdfgRegularize_h35124d34_0_155, width: 1) |
        sig(:__VdfgRegularize_h35124d34_0_166, width: 1)
    )
  assign :rd_glob_param_2_value,
    mux(
      sig(:cond_43, width: 1),
      sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
      mux(
        sig(:__VdfgRegularize_h35124d34_0_255, width: 1),
        sig(:read_4, width: 32),
        mux(
          sig(:__VdfgRegularize_h35124d34_0_254, width: 1),
          sig(:read_4, width: 32),
          mux(
            sig(:cond_64, width: 1),
            lit(0, width: 16, base: "d", signed: false).concat(
              sig(:read_4, width: 32)[15..0]
            ),
            mux(
              sig(:__VdfgRegularize_h35124d34_0_27, width: 1),
              sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
              mux(
                sig(:__VdfgRegularize_h35124d34_0_252, width: 1),
                lit(0, width: 32, base: "h", signed: false),
                mux(
                  sig(:__VdfgRegularize_h35124d34_0_251, width: 1),
                  sig(:__VdfgRegularize_h35124d34_0_154, width: 32),
                  mux(
                    sig(:__VdfgRegularize_h35124d34_0_28, width: 1),
                    sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
                    mux(
                      sig(:address_stack_for_iret_last, width: 1),
                      sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
                      mux(
                        sig(:__VdfgRegularize_h35124d34_0_30, width: 1),
                        sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
                        mux(
                          sig(:__VdfgRegularize_h35124d34_0_31, width: 1),
                          sig(:__VdfgRegularize_h35124d34_0_62, width: 32),
                          mux(
                            sig(:__VdfgRegularize_h35124d34_0_248, width: 1),
                            lit(0, width: 32, base: "h", signed: false),
                            mux(
                              sig(:__VdfgRegularize_h35124d34_0_247, width: 1),
                              sig(:__VdfgRegularize_h35124d34_0_154, width: 32),
                              mux(
                                sig(:__VdfgRegularize_h35124d34_0_246, width: 1),
                                mux(
                                  (
                                      lit(12, width: 4, base: "h", signed: false) ==
                                      sig(:glob_descriptor, width: 64)[43..40]
                                  ),
                                  sig(:glob_descriptor, width: 64)[63..48].concat(
                                    sig(:glob_descriptor, width: 64)[15..0]
                                  ),
                                  lit(0, width: 16, base: "d", signed: false).concat(
                                    sig(:glob_descriptor, width: 64)[15..0]
                                  )
                                ),
                                mux(
                                  sig(:__VdfgRegularize_h35124d34_0_245, width: 1),
                                  sig(:read_4, width: 32),
                                  mux(
                                    sig(:__VdfgRegularize_h35124d34_0_34, width: 1),
                                    lit(0, width: 32, base: "h", signed: false),
                                    mux(
                                      sig(:__VdfgRegularize_h35124d34_0_243, width: 1),
                                      lit(0, width: 29, base: "d", signed: false).concat(
                                        sig(:glob_param_1, width: 32)[2].concat(
                                          sig(:__VdfgRegularize_h35124d34_0_148, width: 2)
                                        )
                                      ),
                                      mux(
                                        sig(:__VdfgRegularize_h35124d34_0_35, width: 1),
                                        lit(0, width: 32, base: "h", signed: false),
                                        mux(
                                          sig(:__VdfgRegularize_h35124d34_0_36, width: 1),
                                          lit(0, width: 32, base: "h", signed: false),
                                          mux(
                                            sig(:__VdfgRegularize_h35124d34_0_240, width: 1),
                                            sig(:__VdfgRegularize_h35124d34_0_154, width: 32),
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
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_154,
    lit(0, width: 30, base: "d", signed: false).concat(
      sig(:__VdfgRegularize_h35124d34_0_148, width: 2)
    )
  assign :__VdfgRegularize_h35124d34_0_148,
    sig(:rd_descriptor_not_in_limits, width: 1).concat(
      sig(:__VdfgRegularize_h35124d34_0_13, width: 1)
    )
  assign :read_length_word,
    (
        sig(:__VdfgRegularize_h35124d34_0_144, width: 1) |
        (
            (
                (
                  ~sig(:cond_24, width: 1)
                ) &
                sig(:address_stack_pop_for_call, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_h35124d34_0_45, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_64, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_66, width: 1) |
                        (
                            sig(:cond_75, width: 1) |
                            (
                                sig(:address_stack_for_iret_second, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_204, width: 1) |
                                    (
                                        (
                                            sig(:cond_121, width: 1) &
                                            sig(:cond_93, width: 1)
                                        ) |
                                        (
                                            sig(:address_stack_pop_esp_prev, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_78, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_32, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_146, width: 1) |
                                                        (
                                                            (
                                                                sig(:cond_246, width: 1) &
                                                                sig(:cond_26, width: 1)
                                                            ) |
                                                            sig(:__VdfgRegularize_h35124d34_0_81, width: 1)
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :rd_src_is_rm,
    (
        sig(:__VdfgRegularize_h35124d34_0_133, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_100, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_134, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_135, width: 1) |
                    (
                        sig(:cond_119, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_136, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_137, width: 1) |
                                mux(
                                  sig(:__VdfgRegularize_h35124d34_0_37, width: 1),
                                  sig(:rd_arith_modregrm_to_reg, width: 1),
                                  (
                                      sig(:__VdfgRegularize_h35124d34_0_138, width: 1) |
                                      (
                                          sig(:__VdfgRegularize_h35124d34_0_139, width: 1) |
                                          (
                                              sig(:__VdfgRegularize_h35124d34_0_140, width: 1) |
                                              (
                                                  sig(:__VdfgRegularize_h35124d34_0_141, width: 1) |
                                                  (
                                                      sig(:__VdfgRegularize_h35124d34_0_142, width: 1) |
                                                      (
                                                          sig(:cond_255, width: 1) |
                                                          sig(:__VdfgRegularize_h35124d34_0_143, width: 1)
                                                      )
                                                  )
                                              )
                                          )
                                      )
                                  )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :rd_system_linear,
    mux(
      sig(:cond_33, width: 1),
      (
          lit(102, width: 32, base: "h", signed: false) +
          sig(:tr_base, width: 32)
      ),
      mux(
        sig(:cond_35, width: 1),
        (
            sig(:tr_base, width: 32) +
            sig(:__VdfgRegularize_h35124d34_0_1, width: 32)
        ),
        mux(
          sig(:cond_64, width: 1),
          (
              sig(:idtr_base, width: 32) +
              sig(:__VdfgRegularize_h35124d34_0_153, width: 30).concat(
              lit(0, width: 2, base: "h", signed: false)
            )
          ),
          mux(
            sig(:cond_65, width: 1),
            (
                sig(:idtr_base, width: 32) +
                sig(:__VdfgRegularize_h35124d34_0_153, width: 30).concat(
                lit(2, width: 2, base: "h", signed: false)
              )
            ),
            mux(
              sig(:cond_66, width: 1),
              (
                  sig(:idtr_base, width: 32) +
                  lit(0, width: 21, base: "d", signed: false).concat(
                  sig(:exc_vector, width: 8).concat(
                    lit(0, width: 3, base: "h", signed: false)
                  )
                )
              ),
              mux(
                sig(:cond_88, width: 1),
                sig(:tr_base, width: 32),
                mux(
                  sig(:cond_187, width: 1),
                  (
                      sig(:tr_base, width: 32) +
                      mux(
                        sig(:rd_ss_esp_from_tss_386, width: 1),
                        (
                            lit(8, width: 32, base: "h", signed: false) +
                            sig(:__VdfgRegularize_h35124d34_0_264, width: 32)
                        ),
                        (
                            lit(4, width: 32, base: "h", signed: false) +
                            sig(:__VdfgRegularize_h35124d34_0_263, width: 32)
                        )
                      )
                  ),
                  mux(
                    sig(:cond_189, width: 1),
                    (
                        sig(:tr_base, width: 32) +
                        mux(
                          sig(:rd_ss_esp_from_tss_386, width: 1),
                          (
                              lit(4, width: 32, base: "h", signed: false) +
                              sig(:__VdfgRegularize_h35124d34_0_264, width: 32)
                          ),
                          (
                              lit(2, width: 32, base: "h", signed: false) +
                              sig(:__VdfgRegularize_h35124d34_0_263, width: 32)
                          )
                        )
                    ),
                    mux(
                      sig(:cond_227, width: 1),
                      (
                          lit(4, width: 32, base: "h", signed: false) +
                          (
                              sig(:gdtr_base, width: 32) +
                              lit(0, width: 16, base: "d", signed: false).concat(
                              sig(:tr, width: 16)[15..3].concat(
                                lit(0, width: 3, base: "h", signed: false)
                              )
                            )
                          )
                      ),
                      mux(
                        (
                            sig(:cond_232, width: 1) &
                            (
                                sig(:__VdfgRegularize_h35124d34_0_5, width: 1) &
                                sig(:__VdfgRegularize_h35124d34_0_8, width: 1)
                            )
                        ),
                        (
                            lit(12, width: 32, base: "h", signed: false) +
                            sig(:glob_desc_base, width: 32)
                        ),
                        mux(
                          (
                              sig(:cond_232, width: 1) &
                              (
                                  sig(:__VdfgRegularize_h35124d34_0_5, width: 1) &
                                  sig(:__VdfgRegularize_h35124d34_0_24, width: 1)
                              )
                          ),
                          (
                              lit(28, width: 32, base: "h", signed: false) +
                              sig(:glob_desc_base, width: 32)
                          ),
                          mux(
                            (
                                sig(:cond_232, width: 1) &
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_21, width: 1) |
                                    sig(:__VdfgRegularize_h35124d34_0_12, width: 1)
                                )
                            ),
                            sig(:rd_task_switch_linear_next, width: 32),
                            mux(
                              sig(:cond_237, width: 1),
                              sig(:rd_task_switch_linear_next, width: 32),
                              mux(
                                sig(:cond_239, width: 1),
                                (
                                    lit(4, width: 32, base: "h", signed: false) +
                                    (
                                        sig(:gdtr_base, width: 32) +
                                        lit(0, width: 16, base: "d", signed: false).concat(
                                        sig(:glob_param_1, width: 32)[15..3].concat(
                                          lit(0, width: 3, base: "h", signed: false)
                                        )
                                      )
                                    )
                                ),
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
  assign :__VdfgRegularize_h35124d34_0_153,
    lit(0, width: 22, base: "d", signed: false).concat(
      sig(:exc_vector, width: 8)
    )
  assign :__VdfgRegularize_h35124d34_0_5,
    (
        lit(12, width: 4, base: "h", signed: false) ==
        sig(:rd_cmdex, width: 4)
    )
  assign :rd_glob_param_1_value,
    mux(
      sig(:__VdfgRegularize_h35124d34_0_162, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:glob_descriptor, width: 64)[31..16]
      ),
      mux(
        sig(:__VdfgRegularize_h35124d34_0_64, width: 1),
        sig(:__VdfgRegularize_h35124d34_0_152, width: 32),
        mux(
          sig(:__VdfgRegularize_h35124d34_0_122, width: 1),
          sig(:__VdfgRegularize_h35124d34_0_152, width: 32),
          mux(
            sig(:__VdfgRegularize_h35124d34_0_123, width: 1),
            lit(0, width: 13, base: "d", signed: false).concat(
              sig(:rd_decoder, width: 88)[13..11]
            ).concat(
              sig(:dst_wire, width: 32)[15..0]
            ),
            mux(
              sig(:__VdfgRegularize_h35124d34_0_124, width: 1),
              lit(6, width: 16, base: "h", signed: false).concat(
                sig(:dst_wire, width: 32)[15..0]
              ),
              mux(
                sig(:__VdfgRegularize_h35124d34_0_125, width: 1),
                lit(7, width: 16, base: "h", signed: false).concat(
                  sig(:dst_wire, width: 32)[15..0]
                ),
                mux(
                  sig(:__VdfgRegularize_h35124d34_0_126, width: 1),
                  lit(0, width: 13, base: "d", signed: false).concat(
                    sig(:rd_decoder, width: 88)[13..11]
                  ).concat(
                    sig(:read_4, width: 32)[15..0]
                  ),
                  mux(
                    sig(:__VdfgRegularize_h35124d34_0_127, width: 1),
                    lit(6, width: 16, base: "h", signed: false).concat(
                      sig(:read_4, width: 32)[15..0]
                    ),
                    mux(
                      sig(:__VdfgRegularize_h35124d34_0_128, width: 1),
                      lit(7, width: 16, base: "h", signed: false).concat(
                        sig(:read_4, width: 32)[15..0]
                      ),
                      mux(
                        sig(:__VdfgRegularize_h35124d34_0_161, width: 1),
                        lit(0, width: 16, base: "d", signed: false).concat(
                          sig(:glob_descriptor, width: 64)[31..16]
                        ),
                        mux(
                          sig(:cond_65, width: 1),
                          sig(:__VdfgRegularize_h35124d34_0_149, width: 32),
                          mux(
                            sig(:cond_75, width: 1),
                            lit(0, width: 13, base: "d", signed: false).concat(
                              sig(:rd_decoder, width: 88)[5..3].concat(
                                sig(:read_4, width: 32)[15..0]
                              )
                            ),
                            mux(
                              sig(:__VdfgRegularize_h35124d34_0_129, width: 1),
                              sig(:__VdfgRegularize_h35124d34_0_149, width: 32),
                              mux(
                                sig(:cond_88, width: 1),
                                lit(0, width: 16, base: "d", signed: false).concat(
                                  sig(:read_4, width: 32)[15..0]
                                ),
                                mux(
                                  sig(:__VdfgRegularize_h35124d34_0_130, width: 1),
                                  sig(:__VdfgRegularize_h35124d34_0_150, width: 32),
                                  mux(
                                    sig(:address_stack_for_iret_second, width: 1),
                                    lit(58, width: 16, base: "h", signed: false).concat(
                                      sig(:read_4, width: 32)[15..0]
                                    ),
                                    mux(
                                      sig(:address_stack_pop_esp_prev, width: 1),
                                      lit(26, width: 16, base: "h", signed: false).concat(
                                        sig(:read_4, width: 32)[15..0]
                                      ),
                                      mux(
                                        sig(:__VdfgRegularize_h35124d34_0_131, width: 1),
                                        sig(:__VdfgRegularize_h35124d34_0_150, width: 32),
                                        mux(
                                          sig(:__VdfgRegularize_h35124d34_0_132, width: 1),
                                          sig(:__VdfgRegularize_h35124d34_0_150, width: 32),
                                          mux(
                                            sig(:__VdfgRegularize_h35124d34_0_163, width: 1),
                                            lit(0, width: 16, base: "d", signed: false).concat(
                                              sig(:dst_wire, width: 32)[15..0]
                                            ),
                                            mux(
                                              sig(:__VdfgRegularize_h35124d34_0_196, width: 1),
                                              lit(0, width: 16, base: "d", signed: false).concat(
                                                sig(:read_4, width: 32)[15..0]
                                              ),
                                              mux(
                                                sig(:__VdfgRegularize_h35124d34_0_246, width: 1),
                                                lit(1, width: 16, base: "h", signed: false).concat(
                                                  sig(:glob_descriptor, width: 64)[31..16]
                                                ),
                                                mux(
                                                  sig(:__VdfgRegularize_h35124d34_0_160, width: 1),
                                                  lit(0, width: 16, base: "d", signed: false).concat(
                                                    sig(:glob_descriptor, width: 64)[31..16]
                                                  ),
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
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_152,
    lit(0, width: 13, base: "d", signed: false).concat(
      (
          sig(:rd_decoder, width: 88)[4] &
          sig(:rd_decoder, width: 88)[2]
      ).concat(
        (
            (
                sig(:rd_decoder, width: 88)[6] &
                sig(:rd_decoder, width: 88)[0]
            ) |
            sig(:rd_arith_modregrm_to_reg, width: 1)
        ).concat(
          sig(:rd_decoder, width: 88)[0].concat(
            sig(:read_4, width: 32)[15..0]
          )
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_149,
    lit(1, width: 16, base: "h", signed: false).concat(
      sig(:read_4, width: 32)[15..0]
    )
  assign :__VdfgRegularize_h35124d34_0_150,
    lit(9, width: 16, base: "h", signed: false).concat(
      sig(:read_4, width: 32)[15..0]
    )
  assign :rd_glob_descriptor_2_value,
    mux(
      sig(:address_stack_for_iret_second, width: 1),
      sig(:glob_descriptor, width: 64),
      mux(
        sig(:address_stack_pop_esp_prev, width: 1),
        sig(:glob_descriptor, width: 64),
        lit(0, width: 64, base: "h", signed: false)
      )
    )
  assign :rd_dst_is_modregrm_imm_se,
    (
        sig(:cond_133, width: 1) &
        sig(:cond_134, width: 1)
    )
  assign :rd_dst_is_reg,
    (
        sig(:cond_6, width: 1) |
        (
            sig(:cond_54, width: 1) |
            (
                sig(:cond_133, width: 1) |
                mux(
                  sig(:cond_135, width: 1),
                  sig(:rd_decoder, width: 88)[3],
                  mux(
                    sig(:cond_143, width: 1),
                    sig(:rd_arith_modregrm_to_reg, width: 1),
                    (
                        sig(:cond_166, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_238, width: 1) |
                            (
                                (
                                    sig(:cond_185, width: 1) &
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_40, width: 1) &
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_19, width: 1) &
                                            (
                                                (
                                                    (
                                                      ~sig(:glob_param_2, width: 32)[4]
                                                    ) &
                                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[81]
                                                ) |
                                                (
                                                    (
                                                      ~sig(:glob_param_2, width: 32)[5]
                                                    ) &
                                                    sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[82]
                                                )
                                            )
                                        )
                                    )
                                ) |
                                (
                                    sig(:cond_216, width: 1) |
                                    (
                                        sig(:cond_225, width: 1) |
                                        (
                                            sig(:cond_245, width: 1) |
                                            (
                                                sig(:rd_req_reg_not_8bit, width: 1) |
                                                sig(:cond_258, width: 1)
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                  )
                )
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_40,
    (
      ~sig(:cond_183, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_19,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:glob_param_2, width: 32)[1..0]
    )
  assign :rd_dst_is_memory,
    (
        sig(:__VdfgRegularize_h35124d34_0_41, width: 1) |
        (
            sig(:__VdfgRegularize_h35124d34_0_83, width: 1) |
            (
                sig(:__VdfgRegularize_h35124d34_0_236, width: 1) |
                (
                    sig(:__VdfgRegularize_h35124d34_0_44, width: 1) |
                    (
                        sig(:__VdfgRegularize_h35124d34_0_45, width: 1) |
                        (
                            sig(:__VdfgRegularize_h35124d34_0_46, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_84, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_48, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_49, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h35124d34_0_85, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_86, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_230, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_51, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h35124d34_0_52, width: 1) |
                                                            mux(
                                                              sig(:__VdfgRegularize_h35124d34_0_39, width: 1),
                                                              sig(:rd_arith_modregrm_to_rm, width: 1),
                                                              (
                                                                  sig(:__VdfgRegularize_h35124d34_0_53, width: 1) |
                                                                  (
                                                                      sig(:__VdfgRegularize_h35124d34_0_75, width: 1) |
                                                                      (
                                                                          sig(:__VdfgRegularize_h35124d34_0_76, width: 1) |
                                                                          (
                                                                              sig(:__VdfgRegularize_h35124d34_0_54, width: 1) |
                                                                              (
                                                                                  sig(:__VdfgRegularize_h35124d34_0_55, width: 1) |
                                                                                  (
                                                                                      sig(:__VdfgRegularize_h35124d34_0_180, width: 1) |
                                                                                      (
                                                                                          (
                                                                                              sig(:cond_217, width: 1) |
                                                                                              sig(:cond_219, width: 1)
                                                                                          ) &
                                                                                          sig(:cond_3, width: 1)
                                                                                      )
                                                                                  )
                                                                              )
                                                                          )
                                                                      )
                                                                  )
                                                              )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :rd_glob_descriptor_2_set,
    (
        sig(:address_stack_for_iret_second, width: 1) |
        sig(:address_stack_pop_esp_prev, width: 1)
    )
  assign :rd_error_code,
    mux(
      sig(:__VdfgRegularize_h35124d34_0_216, width: 1),
      sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
      mux(
        sig(:__VdfgRegularize_h35124d34_0_174, width: 1),
        sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
        mux(
          sig(:__VdfgRegularize_h35124d34_0_173, width: 1),
          sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
          mux(
            sig(:__VdfgRegularize_h35124d34_0_172, width: 1),
            sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
            mux(
              sig(:__VdfgRegularize_h35124d34_0_171, width: 1),
              sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
              mux(
                sig(:__VdfgRegularize_h35124d34_0_169, width: 1),
                sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
                mux(
                  sig(:cond_187, width: 1),
                  sig(:tr, width: 16)[15..2].concat(
                    lit(0, width: 2, base: "h", signed: false)
                  ),
                  mux(
                    sig(:__VdfgRegularize_h35124d34_0_96, width: 1),
                    sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
                    mux(
                      sig(:__VdfgRegularize_h35124d34_0_175, width: 1),
                      sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
                      mux(
                        sig(:__VdfgRegularize_h35124d34_0_168, width: 1),
                        sig(:__VdfgRegularize_h35124d34_0_151, width: 16),
                        lit(0, width: 16, base: "h", signed: false)
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h35124d34_0_151,
    sig(:glob_param_1, width: 32)[15..2].concat(
      lit(0, width: 2, base: "h", signed: false)
    )
  assign :rd_dst_is_edx_eax,
    (
        sig(:cond_107, width: 1) |
        mux(
          sig(:cond_135, width: 1),
          sig(:__VdfgRegularize_h35124d34_0_2, width: 1),
          sig(:cond_150, width: 1)
        )
    )
  assign :rd_src_is_modregrm_imm,
    mux(
      sig(:cond_76, width: 1),
      sig(:cond_26, width: 1),
      mux(
        sig(:cond_110, width: 1),
        sig(:cond_83, width: 1),
        (
            (
                sig(:__VdfgRegularize_h35124d34_0_97, width: 1) &
                sig(:__VdfgRegularize_h35124d34_0_113, width: 1)
            ) |
            (
                (
                    sig(:__VdfgRegularize_h35124d34_0_97, width: 1) &
                    sig(:__VdfgRegularize_h35124d34_0_53, width: 1)
                ) |
                (
                    sig(:cond_155, width: 1) |
                    sig(:cond_219, width: 1)
                )
            )
        )
      )
    )
  assign :address_ea_buffer_plus_2,
    (
        sig(:cond_121, width: 1) |
        sig(:cond_246, width: 1)
    )
  assign :rd_req_edx_eax,
    mux(
      sig(:cond_107, width: 1),
      sig(:rd_decoder, width: 88)[0],
      mux(
        sig(:cond_135, width: 1),
        (
            sig(:__VdfgRegularize_h35124d34_0_2, width: 1) &
            sig(:rd_decoder, width: 88)[0]
        ),
        (
            sig(:cond_150, width: 1) &
            sig(:rd_decoder, width: 88)[0]
        )
      )
    )
  assign :rd_req_ebp,
    (
        sig(:address_enter_last, width: 1) |
        sig(:__VdfgRegularize_h35124d34_0_239, width: 1)
    )
  assign :rd_req_rm,
    mux(
      sig(:cond_6, width: 1),
      sig(:cond_1, width: 1),
      (
          sig(:__VdfgRegularize_h35124d34_0_99, width: 1) |
          (
              sig(:__VdfgRegularize_h35124d34_0_100, width: 1) |
              (
                  sig(:__VdfgRegularize_h35124d34_0_165, width: 1) |
                  (
                      sig(:__VdfgRegularize_h35124d34_0_90, width: 1) |
                      mux(
                        sig(:__VdfgRegularize_h35124d34_0_104, width: 1),
                        sig(:__VdfgRegularize_h35124d34_0_47, width: 1),
                        (
                            sig(:__VdfgRegularize_h35124d34_0_105, width: 1) |
                            (
                                sig(:__VdfgRegularize_h35124d34_0_106, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h35124d34_0_107, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h35124d34_0_108, width: 1) |
                                        (
                                            sig(:cond_120, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h35124d34_0_109, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h35124d34_0_164, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h35124d34_0_111, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h35124d34_0_112, width: 1) |
                                                            mux(
                                                              sig(:__VdfgRegularize_h35124d34_0_38, width: 1),
                                                              sig(:rd_arith_modregrm_to_rm, width: 1),
                                                              (
                                                                  (
                                                                      sig(:__VdfgRegularize_h35124d34_0_113, width: 1) &
                                                                      sig(:cond_148, width: 1)
                                                                  ) |
                                                                  (
                                                                      (
                                                                          sig(:cond_166, width: 1) &
                                                                          sig(:cond_1, width: 1)
                                                                      ) |
                                                                      (
                                                                          sig(:__VdfgRegularize_h35124d34_0_117, width: 1) |
                                                                          sig(:__VdfgRegularize_h35124d34_0_121, width: 1)
                                                                      )
                                                                  )
                                                              )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                      )
                  )
              )
          )
      )
    )
  assign :rd_src_is_modregrm_imm_se,
    (
        sig(:cond_147, width: 1) &
        (
            (
                sig(:cond_1, width: 1) |
                sig(:cond_3, width: 1)
            ) &
            sig(:cond_134, width: 1)
        )
    )
  assign :read_length_dword,
    (
        (
            sig(:address_stack_pop_for_call, width: 1) &
            sig(:cond_24, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_h35124d34_0_145, width: 1) |
            sig(:__VdfgRegularize_h35124d34_0_147, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_13,
    (
        lit(0, width: 14, base: "h", signed: false) ==
        sig(:glob_param_1, width: 32)[15..2]
    )
  assign :__VdfgRegularize_h35124d34_0_15,
    (
      ~sig(:v8086_mode, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_29,
    (
      ~sig(:rd_mutex_busy_memory, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_33,
    (
      ~sig(:cond_180, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_244,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_241, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_242,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_243, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_241,
    (
        sig(:__VdfgRegularize_h35124d34_0_15, width: 1) &
        sig(:__VdfgRegularize_h35124d34_0_242, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_42,
    (
      ~sig(:cond_4, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_56,
    (
      ~sig(:cond_38, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_65,
    (
        (
            sig(:cond_57, width: 1) |
            (
                sig(:cond_58, width: 1) |
                sig(:cond_59, width: 1)
            )
        ) &
        (
            sig(:cond_26, width: 1) &
            (
                sig(:cond_57, width: 1) |
                sig(:cond_118, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h35124d34_0_67,
    (
      ~sig(:cond_104, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_69,
    (
        sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[46] &
        (
            sig(:cond_82, width: 1) &
            sig(:cond_118, width: 1)
        )
    )
  assign :__VdfgRegularize_h35124d34_0_88,
    (
      ~sig(:rd_mutex_busy_modregrm_reg, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_102,
    (
      ~sig(:rd_mutex_busy_modregrm_rm, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_170,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_17, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_186,
    (
        sig(:__VdfgRegularize_h35124d34_0_56, width: 1) &
        sig(:cond_39, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_253,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_89, width: 1)
    )
  assign :__VdfgRegularize_h35124d34_0_258,
    (
        sig(:__VdfgRegularize_h35124d34_0_25, width: 1) &
        sig(:cond_190, width: 1)
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
      if_stmt(((lit(99, width: 7, base: "h", signed: false) == sig(:rd_cmd, width: 7)) & (lit(12, width: 4, base: "h", signed: false) == sig(:rd_cmdex, width: 4)))) do
        assign(
          :rd_task_switch_linear_reg,
          sig(:rd_system_linear, width: 32),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_ready, width: 1)) do
            assign(
              :rd_task_switch_linear_reg,
              sig(:rd_task_switch_linear_next, width: 32),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :rd_task_switch_linear_reg,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_2,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :__VdfgBinToOneHot_Pre_hb4cc6da5_0_0,
      lit(0, width: 7, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :combinational_logic_3,
    sensitivity: [
    ],
    clocked: false,
    initial: false do
    assign(
      sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[sig(:__VdfgBinToOneHot_Pre_hb4cc6da5_0_0, width: 7)],
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      sig(:__VdfgBinToOneHot_Tab_hb4cc6da5_0_0, width: 128)[sig(:rd_cmd, width: 7)],
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      :__VdfgBinToOneHot_Pre_hb4cc6da5_0_0,
      sig(:rd_cmd, width: 7),
      kind: :blocking
    )
  end

end
