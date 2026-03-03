# frozen_string_literal: true

class ExecuteCommands < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: execute_commands

  def self._import_decl_kinds
    {
      __VdfgBinToOneHot_Pre_ha6c45459_0_0: :logic,
      __VdfgBinToOneHot_Tab_ha6c45459_0_0: :logic,
      __VdfgRegularize_h7a35cd6a_0_0: :logic,
      __VdfgRegularize_h7a35cd6a_0_1: :logic,
      __VdfgRegularize_h7a35cd6a_0_10: :logic,
      __VdfgRegularize_h7a35cd6a_0_100: :logic,
      __VdfgRegularize_h7a35cd6a_0_101: :logic,
      __VdfgRegularize_h7a35cd6a_0_102: :logic,
      __VdfgRegularize_h7a35cd6a_0_103: :logic,
      __VdfgRegularize_h7a35cd6a_0_104: :logic,
      __VdfgRegularize_h7a35cd6a_0_105: :logic,
      __VdfgRegularize_h7a35cd6a_0_106: :logic,
      __VdfgRegularize_h7a35cd6a_0_107: :logic,
      __VdfgRegularize_h7a35cd6a_0_108: :logic,
      __VdfgRegularize_h7a35cd6a_0_109: :logic,
      __VdfgRegularize_h7a35cd6a_0_11: :logic,
      __VdfgRegularize_h7a35cd6a_0_110: :logic,
      __VdfgRegularize_h7a35cd6a_0_111: :logic,
      __VdfgRegularize_h7a35cd6a_0_112: :logic,
      __VdfgRegularize_h7a35cd6a_0_113: :logic,
      __VdfgRegularize_h7a35cd6a_0_114: :logic,
      __VdfgRegularize_h7a35cd6a_0_115: :logic,
      __VdfgRegularize_h7a35cd6a_0_116: :logic,
      __VdfgRegularize_h7a35cd6a_0_117: :logic,
      __VdfgRegularize_h7a35cd6a_0_118: :logic,
      __VdfgRegularize_h7a35cd6a_0_119: :logic,
      __VdfgRegularize_h7a35cd6a_0_12: :logic,
      __VdfgRegularize_h7a35cd6a_0_120: :logic,
      __VdfgRegularize_h7a35cd6a_0_121: :logic,
      __VdfgRegularize_h7a35cd6a_0_122: :logic,
      __VdfgRegularize_h7a35cd6a_0_123: :logic,
      __VdfgRegularize_h7a35cd6a_0_124: :logic,
      __VdfgRegularize_h7a35cd6a_0_125: :logic,
      __VdfgRegularize_h7a35cd6a_0_126: :logic,
      __VdfgRegularize_h7a35cd6a_0_127: :logic,
      __VdfgRegularize_h7a35cd6a_0_128: :logic,
      __VdfgRegularize_h7a35cd6a_0_129: :logic,
      __VdfgRegularize_h7a35cd6a_0_13: :logic,
      __VdfgRegularize_h7a35cd6a_0_130: :logic,
      __VdfgRegularize_h7a35cd6a_0_131: :logic,
      __VdfgRegularize_h7a35cd6a_0_132: :logic,
      __VdfgRegularize_h7a35cd6a_0_133: :logic,
      __VdfgRegularize_h7a35cd6a_0_134: :logic,
      __VdfgRegularize_h7a35cd6a_0_135: :logic,
      __VdfgRegularize_h7a35cd6a_0_136: :logic,
      __VdfgRegularize_h7a35cd6a_0_137: :logic,
      __VdfgRegularize_h7a35cd6a_0_138: :logic,
      __VdfgRegularize_h7a35cd6a_0_139: :logic,
      __VdfgRegularize_h7a35cd6a_0_14: :logic,
      __VdfgRegularize_h7a35cd6a_0_140: :logic,
      __VdfgRegularize_h7a35cd6a_0_141: :logic,
      __VdfgRegularize_h7a35cd6a_0_142: :logic,
      __VdfgRegularize_h7a35cd6a_0_143: :logic,
      __VdfgRegularize_h7a35cd6a_0_144: :logic,
      __VdfgRegularize_h7a35cd6a_0_145: :logic,
      __VdfgRegularize_h7a35cd6a_0_146: :logic,
      __VdfgRegularize_h7a35cd6a_0_147: :logic,
      __VdfgRegularize_h7a35cd6a_0_148: :logic,
      __VdfgRegularize_h7a35cd6a_0_149: :logic,
      __VdfgRegularize_h7a35cd6a_0_15: :logic,
      __VdfgRegularize_h7a35cd6a_0_150: :logic,
      __VdfgRegularize_h7a35cd6a_0_151: :logic,
      __VdfgRegularize_h7a35cd6a_0_152: :logic,
      __VdfgRegularize_h7a35cd6a_0_153: :logic,
      __VdfgRegularize_h7a35cd6a_0_154: :logic,
      __VdfgRegularize_h7a35cd6a_0_155: :logic,
      __VdfgRegularize_h7a35cd6a_0_156: :logic,
      __VdfgRegularize_h7a35cd6a_0_157: :logic,
      __VdfgRegularize_h7a35cd6a_0_158: :logic,
      __VdfgRegularize_h7a35cd6a_0_159: :logic,
      __VdfgRegularize_h7a35cd6a_0_16: :logic,
      __VdfgRegularize_h7a35cd6a_0_160: :logic,
      __VdfgRegularize_h7a35cd6a_0_161: :logic,
      __VdfgRegularize_h7a35cd6a_0_162: :logic,
      __VdfgRegularize_h7a35cd6a_0_163: :logic,
      __VdfgRegularize_h7a35cd6a_0_164: :logic,
      __VdfgRegularize_h7a35cd6a_0_165: :logic,
      __VdfgRegularize_h7a35cd6a_0_166: :logic,
      __VdfgRegularize_h7a35cd6a_0_167: :logic,
      __VdfgRegularize_h7a35cd6a_0_168: :logic,
      __VdfgRegularize_h7a35cd6a_0_169: :logic,
      __VdfgRegularize_h7a35cd6a_0_17: :logic,
      __VdfgRegularize_h7a35cd6a_0_170: :logic,
      __VdfgRegularize_h7a35cd6a_0_171: :logic,
      __VdfgRegularize_h7a35cd6a_0_172: :logic,
      __VdfgRegularize_h7a35cd6a_0_173: :logic,
      __VdfgRegularize_h7a35cd6a_0_174: :logic,
      __VdfgRegularize_h7a35cd6a_0_175: :logic,
      __VdfgRegularize_h7a35cd6a_0_176: :logic,
      __VdfgRegularize_h7a35cd6a_0_177: :logic,
      __VdfgRegularize_h7a35cd6a_0_178: :logic,
      __VdfgRegularize_h7a35cd6a_0_179: :logic,
      __VdfgRegularize_h7a35cd6a_0_18: :logic,
      __VdfgRegularize_h7a35cd6a_0_180: :logic,
      __VdfgRegularize_h7a35cd6a_0_181: :logic,
      __VdfgRegularize_h7a35cd6a_0_182: :logic,
      __VdfgRegularize_h7a35cd6a_0_183: :logic,
      __VdfgRegularize_h7a35cd6a_0_184: :logic,
      __VdfgRegularize_h7a35cd6a_0_185: :logic,
      __VdfgRegularize_h7a35cd6a_0_186: :logic,
      __VdfgRegularize_h7a35cd6a_0_187: :logic,
      __VdfgRegularize_h7a35cd6a_0_188: :logic,
      __VdfgRegularize_h7a35cd6a_0_189: :logic,
      __VdfgRegularize_h7a35cd6a_0_19: :logic,
      __VdfgRegularize_h7a35cd6a_0_190: :logic,
      __VdfgRegularize_h7a35cd6a_0_191: :logic,
      __VdfgRegularize_h7a35cd6a_0_192: :logic,
      __VdfgRegularize_h7a35cd6a_0_193: :logic,
      __VdfgRegularize_h7a35cd6a_0_194: :logic,
      __VdfgRegularize_h7a35cd6a_0_195: :logic,
      __VdfgRegularize_h7a35cd6a_0_196: :logic,
      __VdfgRegularize_h7a35cd6a_0_197: :logic,
      __VdfgRegularize_h7a35cd6a_0_198: :logic,
      __VdfgRegularize_h7a35cd6a_0_199: :logic,
      __VdfgRegularize_h7a35cd6a_0_2: :logic,
      __VdfgRegularize_h7a35cd6a_0_20: :logic,
      __VdfgRegularize_h7a35cd6a_0_200: :logic,
      __VdfgRegularize_h7a35cd6a_0_201: :logic,
      __VdfgRegularize_h7a35cd6a_0_202: :logic,
      __VdfgRegularize_h7a35cd6a_0_203: :logic,
      __VdfgRegularize_h7a35cd6a_0_204: :logic,
      __VdfgRegularize_h7a35cd6a_0_205: :logic,
      __VdfgRegularize_h7a35cd6a_0_206: :logic,
      __VdfgRegularize_h7a35cd6a_0_207: :logic,
      __VdfgRegularize_h7a35cd6a_0_208: :logic,
      __VdfgRegularize_h7a35cd6a_0_209: :logic,
      __VdfgRegularize_h7a35cd6a_0_21: :logic,
      __VdfgRegularize_h7a35cd6a_0_210: :logic,
      __VdfgRegularize_h7a35cd6a_0_211: :logic,
      __VdfgRegularize_h7a35cd6a_0_212: :logic,
      __VdfgRegularize_h7a35cd6a_0_213: :logic,
      __VdfgRegularize_h7a35cd6a_0_214: :logic,
      __VdfgRegularize_h7a35cd6a_0_215: :logic,
      __VdfgRegularize_h7a35cd6a_0_216: :logic,
      __VdfgRegularize_h7a35cd6a_0_217: :logic,
      __VdfgRegularize_h7a35cd6a_0_218: :logic,
      __VdfgRegularize_h7a35cd6a_0_219: :logic,
      __VdfgRegularize_h7a35cd6a_0_22: :logic,
      __VdfgRegularize_h7a35cd6a_0_220: :logic,
      __VdfgRegularize_h7a35cd6a_0_221: :logic,
      __VdfgRegularize_h7a35cd6a_0_222: :logic,
      __VdfgRegularize_h7a35cd6a_0_223: :logic,
      __VdfgRegularize_h7a35cd6a_0_224: :logic,
      __VdfgRegularize_h7a35cd6a_0_225: :logic,
      __VdfgRegularize_h7a35cd6a_0_226: :logic,
      __VdfgRegularize_h7a35cd6a_0_227: :logic,
      __VdfgRegularize_h7a35cd6a_0_228: :logic,
      __VdfgRegularize_h7a35cd6a_0_229: :logic,
      __VdfgRegularize_h7a35cd6a_0_23: :logic,
      __VdfgRegularize_h7a35cd6a_0_230: :logic,
      __VdfgRegularize_h7a35cd6a_0_231: :logic,
      __VdfgRegularize_h7a35cd6a_0_232: :logic,
      __VdfgRegularize_h7a35cd6a_0_233: :logic,
      __VdfgRegularize_h7a35cd6a_0_234: :logic,
      __VdfgRegularize_h7a35cd6a_0_235: :logic,
      __VdfgRegularize_h7a35cd6a_0_236: :logic,
      __VdfgRegularize_h7a35cd6a_0_237: :logic,
      __VdfgRegularize_h7a35cd6a_0_238: :logic,
      __VdfgRegularize_h7a35cd6a_0_239: :logic,
      __VdfgRegularize_h7a35cd6a_0_24: :logic,
      __VdfgRegularize_h7a35cd6a_0_240: :logic,
      __VdfgRegularize_h7a35cd6a_0_241: :logic,
      __VdfgRegularize_h7a35cd6a_0_242: :logic,
      __VdfgRegularize_h7a35cd6a_0_243: :logic,
      __VdfgRegularize_h7a35cd6a_0_244: :logic,
      __VdfgRegularize_h7a35cd6a_0_245: :logic,
      __VdfgRegularize_h7a35cd6a_0_246: :logic,
      __VdfgRegularize_h7a35cd6a_0_247: :logic,
      __VdfgRegularize_h7a35cd6a_0_248: :logic,
      __VdfgRegularize_h7a35cd6a_0_249: :logic,
      __VdfgRegularize_h7a35cd6a_0_25: :logic,
      __VdfgRegularize_h7a35cd6a_0_250: :logic,
      __VdfgRegularize_h7a35cd6a_0_251: :logic,
      __VdfgRegularize_h7a35cd6a_0_252: :logic,
      __VdfgRegularize_h7a35cd6a_0_253: :logic,
      __VdfgRegularize_h7a35cd6a_0_26: :logic,
      __VdfgRegularize_h7a35cd6a_0_27: :logic,
      __VdfgRegularize_h7a35cd6a_0_28: :logic,
      __VdfgRegularize_h7a35cd6a_0_29: :logic,
      __VdfgRegularize_h7a35cd6a_0_3: :logic,
      __VdfgRegularize_h7a35cd6a_0_30: :logic,
      __VdfgRegularize_h7a35cd6a_0_31: :logic,
      __VdfgRegularize_h7a35cd6a_0_32: :logic,
      __VdfgRegularize_h7a35cd6a_0_33: :logic,
      __VdfgRegularize_h7a35cd6a_0_34: :logic,
      __VdfgRegularize_h7a35cd6a_0_35: :logic,
      __VdfgRegularize_h7a35cd6a_0_36: :logic,
      __VdfgRegularize_h7a35cd6a_0_37: :logic,
      __VdfgRegularize_h7a35cd6a_0_38: :logic,
      __VdfgRegularize_h7a35cd6a_0_39: :logic,
      __VdfgRegularize_h7a35cd6a_0_4: :logic,
      __VdfgRegularize_h7a35cd6a_0_40: :logic,
      __VdfgRegularize_h7a35cd6a_0_41: :logic,
      __VdfgRegularize_h7a35cd6a_0_42: :logic,
      __VdfgRegularize_h7a35cd6a_0_43: :logic,
      __VdfgRegularize_h7a35cd6a_0_44: :logic,
      __VdfgRegularize_h7a35cd6a_0_45: :logic,
      __VdfgRegularize_h7a35cd6a_0_46: :logic,
      __VdfgRegularize_h7a35cd6a_0_47: :logic,
      __VdfgRegularize_h7a35cd6a_0_48: :logic,
      __VdfgRegularize_h7a35cd6a_0_49: :logic,
      __VdfgRegularize_h7a35cd6a_0_5: :logic,
      __VdfgRegularize_h7a35cd6a_0_50: :logic,
      __VdfgRegularize_h7a35cd6a_0_51: :logic,
      __VdfgRegularize_h7a35cd6a_0_52: :logic,
      __VdfgRegularize_h7a35cd6a_0_53: :logic,
      __VdfgRegularize_h7a35cd6a_0_54: :logic,
      __VdfgRegularize_h7a35cd6a_0_55: :logic,
      __VdfgRegularize_h7a35cd6a_0_56: :logic,
      __VdfgRegularize_h7a35cd6a_0_57: :logic,
      __VdfgRegularize_h7a35cd6a_0_58: :logic,
      __VdfgRegularize_h7a35cd6a_0_59: :logic,
      __VdfgRegularize_h7a35cd6a_0_6: :logic,
      __VdfgRegularize_h7a35cd6a_0_60: :logic,
      __VdfgRegularize_h7a35cd6a_0_61: :logic,
      __VdfgRegularize_h7a35cd6a_0_62: :logic,
      __VdfgRegularize_h7a35cd6a_0_63: :logic,
      __VdfgRegularize_h7a35cd6a_0_64: :logic,
      __VdfgRegularize_h7a35cd6a_0_65: :logic,
      __VdfgRegularize_h7a35cd6a_0_66: :logic,
      __VdfgRegularize_h7a35cd6a_0_67: :logic,
      __VdfgRegularize_h7a35cd6a_0_68: :logic,
      __VdfgRegularize_h7a35cd6a_0_69: :logic,
      __VdfgRegularize_h7a35cd6a_0_7: :logic,
      __VdfgRegularize_h7a35cd6a_0_70: :logic,
      __VdfgRegularize_h7a35cd6a_0_71: :logic,
      __VdfgRegularize_h7a35cd6a_0_72: :logic,
      __VdfgRegularize_h7a35cd6a_0_73: :logic,
      __VdfgRegularize_h7a35cd6a_0_74: :logic,
      __VdfgRegularize_h7a35cd6a_0_75: :logic,
      __VdfgRegularize_h7a35cd6a_0_76: :logic,
      __VdfgRegularize_h7a35cd6a_0_77: :logic,
      __VdfgRegularize_h7a35cd6a_0_78: :logic,
      __VdfgRegularize_h7a35cd6a_0_79: :logic,
      __VdfgRegularize_h7a35cd6a_0_8: :logic,
      __VdfgRegularize_h7a35cd6a_0_80: :logic,
      __VdfgRegularize_h7a35cd6a_0_81: :logic,
      __VdfgRegularize_h7a35cd6a_0_82: :logic,
      __VdfgRegularize_h7a35cd6a_0_83: :logic,
      __VdfgRegularize_h7a35cd6a_0_84: :logic,
      __VdfgRegularize_h7a35cd6a_0_85: :logic,
      __VdfgRegularize_h7a35cd6a_0_86: :logic,
      __VdfgRegularize_h7a35cd6a_0_87: :logic,
      __VdfgRegularize_h7a35cd6a_0_88: :logic,
      __VdfgRegularize_h7a35cd6a_0_89: :logic,
      __VdfgRegularize_h7a35cd6a_0_9: :logic,
      __VdfgRegularize_h7a35cd6a_0_90: :logic,
      __VdfgRegularize_h7a35cd6a_0_91: :logic,
      __VdfgRegularize_h7a35cd6a_0_92: :logic,
      __VdfgRegularize_h7a35cd6a_0_93: :logic,
      __VdfgRegularize_h7a35cd6a_0_94: :logic,
      __VdfgRegularize_h7a35cd6a_0_95: :logic,
      __VdfgRegularize_h7a35cd6a_0_96: :logic,
      __VdfgRegularize_h7a35cd6a_0_97: :logic,
      __VdfgRegularize_h7a35cd6a_0_98: :logic,
      __VdfgRegularize_h7a35cd6a_0_99: :logic,
      __VdfgRegularize_h7a35cd6a_1_0: :logic,
      _unused_ok: :wire,
      cond_0: :wire,
      cond_10: :wire,
      cond_100: :wire,
      cond_101: :wire,
      cond_102: :wire,
      cond_103: :wire,
      cond_104: :wire,
      cond_105: :wire,
      cond_106: :wire,
      cond_108: :wire,
      cond_109: :wire,
      cond_113: :wire,
      cond_117: :wire,
      cond_12: :wire,
      cond_120: :wire,
      cond_121: :wire,
      cond_122: :wire,
      cond_123: :wire,
      cond_124: :wire,
      cond_126: :wire,
      cond_13: :wire,
      cond_130: :wire,
      cond_131: :wire,
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
      cond_153: :wire,
      cond_154: :wire,
      cond_155: :wire,
      cond_158: :wire,
      cond_16: :wire,
      cond_162: :wire,
      cond_164: :wire,
      cond_165: :wire,
      cond_166: :wire,
      cond_168: :wire,
      cond_17: :wire,
      cond_170: :wire,
      cond_172: :wire,
      cond_174: :wire,
      cond_175: :wire,
      cond_176: :wire,
      cond_178: :wire,
      cond_183: :wire,
      cond_184: :wire,
      cond_185: :wire,
      cond_186: :wire,
      cond_187: :wire,
      cond_188: :wire,
      cond_19: :wire,
      cond_190: :wire,
      cond_191: :wire,
      cond_193: :wire,
      cond_196: :wire,
      cond_197: :wire,
      cond_2: :wire,
      cond_20: :wire,
      cond_200: :wire,
      cond_201: :wire,
      cond_204: :wire,
      cond_205: :wire,
      cond_206: :wire,
      cond_207: :wire,
      cond_209: :wire,
      cond_211: :wire,
      cond_213: :wire,
      cond_217: :wire,
      cond_218: :wire,
      cond_219: :wire,
      cond_220: :wire,
      cond_221: :wire,
      cond_222: :wire,
      cond_223: :wire,
      cond_225: :wire,
      cond_226: :wire,
      cond_227: :wire,
      cond_232: :wire,
      cond_236: :wire,
      cond_239: :wire,
      cond_24: :wire,
      cond_240: :wire,
      cond_241: :wire,
      cond_244: :wire,
      cond_246: :wire,
      cond_249: :wire,
      cond_25: :wire,
      cond_250: :wire,
      cond_252: :wire,
      cond_253: :wire,
      cond_254: :wire,
      cond_255: :wire,
      cond_256: :wire,
      cond_259: :wire,
      cond_26: :wire,
      cond_260: :wire,
      cond_267: :wire,
      cond_270: :wire,
      cond_272: :wire,
      cond_273: :wire,
      cond_279: :wire,
      cond_28: :wire,
      cond_282: :wire,
      cond_284: :wire,
      cond_285: :wire,
      cond_286: :wire,
      cond_29: :wire,
      cond_294: :wire,
      cond_295: :wire,
      cond_296: :wire,
      cond_297: :wire,
      cond_3: :wire,
      cond_30: :wire,
      cond_31: :wire,
      cond_34: :wire,
      cond_35: :wire,
      cond_37: :wire,
      cond_38: :wire,
      cond_39: :wire,
      cond_40: :wire,
      cond_41: :wire,
      cond_42: :wire,
      cond_44: :wire,
      cond_47: :wire,
      cond_49: :wire,
      cond_50: :wire,
      cond_51: :wire,
      cond_54: :wire,
      cond_55: :wire,
      cond_6: :wire,
      cond_63: :wire,
      cond_64: :wire,
      cond_65: :wire,
      cond_67: :wire,
      cond_68: :wire,
      cond_7: :wire,
      cond_72: :wire,
      cond_73: :wire,
      cond_74: :wire,
      cond_79: :wire,
      cond_8: :wire,
      cond_87: :wire,
      cond_88: :wire,
      cond_9: :wire,
      cond_93: :wire,
      cond_95: :wire,
      cond_96: :wire,
      cond_98: :wire,
      cond_99: :wire,
      e_aaa_sum_ax: :wire,
      e_aas_sub_ax: :wire,
      e_bcd_condition_cf: :wire,
      e_bit_selected: :wire,
      e_bit_selector: :wire,
      e_bit_value: :wire,
      e_bound_dst: :wire,
      e_cmpxchg_eq: :wire,
      e_cmpxchg_sub: :wire,
      e_cpl_current: :wire,
      e_cr0_reg: :wire,
      e_daa_step1: :wire,
      e_das_step1: :wire,
      e_invd_code_done: :reg,
      e_invd_data_done: :reg,
      e_io_allow_bits: :wire,
      e_src_ze: :wire,
      e_wbinvd_code_done: :reg,
      e_wbinvd_data_done: :reg,
      exe_arith_adc: :wire,
      exe_arith_add: :wire,
      exe_arith_and: :wire,
      exe_arith_sbb: :wire,
      exe_arith_sub: :wire,
      exe_bcd_condition_af: :wire,
      exe_buffer_shift: :wire,
      exe_buffer_shift_word: :wire,
      exe_buffer_to_reg: :wire,
      exe_cmd_loop_condition: :wire,
      exe_cmd_loop_ecx: :wire,
      exe_condition: :wire,
      exe_int_2_int_trap_same_exception: :wire,
      exe_jecxz_condition: :wire,
      exe_new_tss_max: :wire,
      exe_privilege_not_accepted: :wire,
      exe_push_eflags: :wire,
      exe_segment: :wire,
      exe_selector: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :exe_reset
  input :eax, width: 32
  input :ecx, width: 32
  input :edx, width: 32
  input :ebp, width: 32
  input :esp, width: 32
  input :tr_base, width: 32
  input :es, width: 16
  input :cs, width: 16
  input :ss, width: 16
  input :ds, width: 16
  input :fs, width: 16
  input :gs, width: 16
  input :ldtr, width: 16
  input :tr, width: 16
  input :cr2, width: 32
  input :cr3, width: 32
  input :dr0, width: 32
  input :dr1, width: 32
  input :dr2, width: 32
  input :dr3, width: 32
  input :dr6_bt
  input :dr6_bs
  input :dr6_bd
  input :dr6_b12
  input :dr6_breakpoints, width: 4
  input :dr7, width: 32
  input :cpl, width: 2
  input :real_mode
  input :v8086_mode
  input :protected_mode
  input :idflag
  input :acflag
  input :vmflag
  input :rflag
  input :ntflag
  input :iopl, width: 2
  input :oflag
  input :dflag
  input :iflag
  input :tflag
  input :sflag
  input :zflag
  input :aflag
  input :pflag
  input :cflag
  input :cr0_pg
  input :cr0_cd
  input :cr0_nw
  input :cr0_am
  input :cr0_wp
  input :cr0_ne
  input :cr0_ts
  input :cr0_em
  input :cr0_mp
  input :cr0_pe
  input :cs_limit, width: 32
  input :tr_limit, width: 32
  input :tr_cache, width: 64
  input :ss_cache, width: 64
  input :idtr_limit, width: 16
  input :idtr_base, width: 32
  input :gdtr_limit, width: 16
  input :gdtr_base, width: 32
  input :exc_push_error
  input :exc_error_code, width: 16
  input :exc_soft_int_ib
  input :exc_soft_int
  input :exc_vector, width: 8
  input :exe_mutex_current, width: 11
  input :exe_eip, width: 32
  input :e_eip_next_sum, width: 32
  input :exe_extra, width: 32
  input :exe_linear, width: 32
  input :exe_cmd, width: 7
  input :exe_cmdex, width: 4
  input :exe_decoder, width: 40
  input :exe_modregrm_reg, width: 3
  input :exe_address_effective, width: 32
  input :exe_is_8bit
  input :exe_operand_16bit
  input :exe_operand_32bit
  input :exe_address_16bit
  input :exe_consumed, width: 4
  input :src, width: 32
  input :dst, width: 32
  input :exe_enter_offset, width: 32
  input :exe_ready
  input :mult_busy
  input :mult_result, width: 66
  input :div_busy
  input :exe_div_exception
  input :div_result_quotient, width: 32
  input :div_result_remainder, width: 32
  input :e_shift_no_write
  input :e_shift_oszapc_update
  input :e_shift_cf_of_update
  input :e_shift_oflag
  input :e_shift_cflag
  input :e_shift_result, width: 32
  output :tlbcheck_do
  input :tlbcheck_done
  input :tlbcheck_page_fault
  output :tlbcheck_address, width: 32
  output :tlbcheck_rw
  output :tlbflushsingle_do
  input :tlbflushsingle_done
  output :tlbflushsingle_address, width: 32
  output :invdcode_do
  input :invdcode_done
  output :invddata_do
  input :invddata_done
  output :wbinvddata_do
  input :wbinvddata_done
  input :wr_task_rpl, width: 2
  input :wr_esp_prev, width: 32
  input :glob_descriptor, width: 64
  input :glob_descriptor_2, width: 64
  input :glob_param_1, width: 32
  input :glob_param_2, width: 32
  input :glob_param_3, width: 32
  input :glob_param_5, width: 32
  input :glob_desc_base, width: 32
  input :glob_desc_limit, width: 32
  input :glob_desc_2_limit, width: 32
  output :exe_glob_descriptor_set
  output :exe_glob_descriptor_value, width: 64
  output :exe_glob_descriptor_2_set
  output :exe_glob_descriptor_2_value, width: 64
  output :exe_glob_param_1_set
  output :exe_glob_param_1_value, width: 32
  output :exe_glob_param_2_set
  output :exe_glob_param_2_value, width: 32
  output :exe_glob_param_3_set
  output :exe_glob_param_3_value, width: 32
  output :dr6_bd_set
  output :offset_ret_far_se
  output :offset_new_stack
  output :offset_new_stack_minus
  output :offset_new_stack_continue
  output :offset_leave
  output :offset_pop
  output :offset_enter_last
  output :offset_ret
  output :offset_iret_glob_param_4
  output :offset_iret
  output :offset_ret_imm
  output :offset_esp
  output :offset_call
  output :offset_call_keep
  output :offset_call_int_same_first
  output :offset_call_int_same_next
  output :offset_int_real
  output :offset_int_real_next
  output :offset_task
  output :task_eip, width: 32
  output :exe_waiting
  output :exe_bound_fault
  output :exe_trigger_gp_fault
  output :exe_trigger_ts_fault
  output :exe_trigger_ss_fault
  output :exe_trigger_np_fault
  output :exe_trigger_pf_fault
  output :exe_trigger_db_fault
  output :exe_trigger_nm_fault
  output :exe_load_seg_gp_fault
  output :exe_load_seg_ss_fault
  output :exe_load_seg_np_fault
  output :exe_error_code, width: 16
  output :exe_result, width: 32
  output :exe_result2, width: 32
  output :exe_result_push, width: 32
  output :exe_result_signals, width: 5
  output :exe_arith_index, width: 4
  output :exe_arith_sub_carry
  output :exe_arith_add_carry
  output :exe_arith_adc_carry
  output :exe_arith_sbb_carry
  output :exe_buffer, width: 32
  output :exe_buffer_shifted, width: 464
  output :exe_is_8bit_clear
  output :exe_cmpxchg_switch
  output :exe_task_switch_finished
  output :exe_eip_from_glob_param_2
  output :exe_eip_from_glob_param_2_16bit
  output :exe_branch
  output :exe_branch_eip, width: 32

  # Signals

  signal :__VdfgBinToOneHot_Pre_ha6c45459_0_0, width: 7
  signal :__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128
  signal :__VdfgRegularize_h7a35cd6a_0_0, width: 15
  signal :__VdfgRegularize_h7a35cd6a_0_1
  signal :__VdfgRegularize_h7a35cd6a_0_10
  signal :__VdfgRegularize_h7a35cd6a_0_100
  signal :__VdfgRegularize_h7a35cd6a_0_101
  signal :__VdfgRegularize_h7a35cd6a_0_102
  signal :__VdfgRegularize_h7a35cd6a_0_103
  signal :__VdfgRegularize_h7a35cd6a_0_104
  signal :__VdfgRegularize_h7a35cd6a_0_105
  signal :__VdfgRegularize_h7a35cd6a_0_106
  signal :__VdfgRegularize_h7a35cd6a_0_107
  signal :__VdfgRegularize_h7a35cd6a_0_108
  signal :__VdfgRegularize_h7a35cd6a_0_109
  signal :__VdfgRegularize_h7a35cd6a_0_11
  signal :__VdfgRegularize_h7a35cd6a_0_110
  signal :__VdfgRegularize_h7a35cd6a_0_111
  signal :__VdfgRegularize_h7a35cd6a_0_112
  signal :__VdfgRegularize_h7a35cd6a_0_113
  signal :__VdfgRegularize_h7a35cd6a_0_114
  signal :__VdfgRegularize_h7a35cd6a_0_115
  signal :__VdfgRegularize_h7a35cd6a_0_116
  signal :__VdfgRegularize_h7a35cd6a_0_117
  signal :__VdfgRegularize_h7a35cd6a_0_118
  signal :__VdfgRegularize_h7a35cd6a_0_119
  signal :__VdfgRegularize_h7a35cd6a_0_12
  signal :__VdfgRegularize_h7a35cd6a_0_120
  signal :__VdfgRegularize_h7a35cd6a_0_121
  signal :__VdfgRegularize_h7a35cd6a_0_122
  signal :__VdfgRegularize_h7a35cd6a_0_123
  signal :__VdfgRegularize_h7a35cd6a_0_124
  signal :__VdfgRegularize_h7a35cd6a_0_125
  signal :__VdfgRegularize_h7a35cd6a_0_126
  signal :__VdfgRegularize_h7a35cd6a_0_127
  signal :__VdfgRegularize_h7a35cd6a_0_128
  signal :__VdfgRegularize_h7a35cd6a_0_129
  signal :__VdfgRegularize_h7a35cd6a_0_13
  signal :__VdfgRegularize_h7a35cd6a_0_130
  signal :__VdfgRegularize_h7a35cd6a_0_131
  signal :__VdfgRegularize_h7a35cd6a_0_132
  signal :__VdfgRegularize_h7a35cd6a_0_133
  signal :__VdfgRegularize_h7a35cd6a_0_134
  signal :__VdfgRegularize_h7a35cd6a_0_135
  signal :__VdfgRegularize_h7a35cd6a_0_136
  signal :__VdfgRegularize_h7a35cd6a_0_137
  signal :__VdfgRegularize_h7a35cd6a_0_138
  signal :__VdfgRegularize_h7a35cd6a_0_139
  signal :__VdfgRegularize_h7a35cd6a_0_14
  signal :__VdfgRegularize_h7a35cd6a_0_140
  signal :__VdfgRegularize_h7a35cd6a_0_141
  signal :__VdfgRegularize_h7a35cd6a_0_142
  signal :__VdfgRegularize_h7a35cd6a_0_143
  signal :__VdfgRegularize_h7a35cd6a_0_144
  signal :__VdfgRegularize_h7a35cd6a_0_145
  signal :__VdfgRegularize_h7a35cd6a_0_146
  signal :__VdfgRegularize_h7a35cd6a_0_147
  signal :__VdfgRegularize_h7a35cd6a_0_148
  signal :__VdfgRegularize_h7a35cd6a_0_149
  signal :__VdfgRegularize_h7a35cd6a_0_15
  signal :__VdfgRegularize_h7a35cd6a_0_150
  signal :__VdfgRegularize_h7a35cd6a_0_151
  signal :__VdfgRegularize_h7a35cd6a_0_152
  signal :__VdfgRegularize_h7a35cd6a_0_153
  signal :__VdfgRegularize_h7a35cd6a_0_154
  signal :__VdfgRegularize_h7a35cd6a_0_155
  signal :__VdfgRegularize_h7a35cd6a_0_156
  signal :__VdfgRegularize_h7a35cd6a_0_157
  signal :__VdfgRegularize_h7a35cd6a_0_158
  signal :__VdfgRegularize_h7a35cd6a_0_159
  signal :__VdfgRegularize_h7a35cd6a_0_16
  signal :__VdfgRegularize_h7a35cd6a_0_160
  signal :__VdfgRegularize_h7a35cd6a_0_161
  signal :__VdfgRegularize_h7a35cd6a_0_162
  signal :__VdfgRegularize_h7a35cd6a_0_163
  signal :__VdfgRegularize_h7a35cd6a_0_164
  signal :__VdfgRegularize_h7a35cd6a_0_165
  signal :__VdfgRegularize_h7a35cd6a_0_166
  signal :__VdfgRegularize_h7a35cd6a_0_167
  signal :__VdfgRegularize_h7a35cd6a_0_168
  signal :__VdfgRegularize_h7a35cd6a_0_169
  signal :__VdfgRegularize_h7a35cd6a_0_17
  signal :__VdfgRegularize_h7a35cd6a_0_170
  signal :__VdfgRegularize_h7a35cd6a_0_171, width: 5
  signal :__VdfgRegularize_h7a35cd6a_0_172
  signal :__VdfgRegularize_h7a35cd6a_0_173, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_174, width: 16
  signal :__VdfgRegularize_h7a35cd6a_0_175, width: 16
  signal :__VdfgRegularize_h7a35cd6a_0_176
  signal :__VdfgRegularize_h7a35cd6a_0_177
  signal :__VdfgRegularize_h7a35cd6a_0_178
  signal :__VdfgRegularize_h7a35cd6a_0_179
  signal :__VdfgRegularize_h7a35cd6a_0_18
  signal :__VdfgRegularize_h7a35cd6a_0_180
  signal :__VdfgRegularize_h7a35cd6a_0_181
  signal :__VdfgRegularize_h7a35cd6a_0_182
  signal :__VdfgRegularize_h7a35cd6a_0_183
  signal :__VdfgRegularize_h7a35cd6a_0_184
  signal :__VdfgRegularize_h7a35cd6a_0_185
  signal :__VdfgRegularize_h7a35cd6a_0_186
  signal :__VdfgRegularize_h7a35cd6a_0_187
  signal :__VdfgRegularize_h7a35cd6a_0_188
  signal :__VdfgRegularize_h7a35cd6a_0_189
  signal :__VdfgRegularize_h7a35cd6a_0_19
  signal :__VdfgRegularize_h7a35cd6a_0_190
  signal :__VdfgRegularize_h7a35cd6a_0_191
  signal :__VdfgRegularize_h7a35cd6a_0_192, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_193
  signal :__VdfgRegularize_h7a35cd6a_0_194, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_195, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_196, width: 19
  signal :__VdfgRegularize_h7a35cd6a_0_197, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_198
  signal :__VdfgRegularize_h7a35cd6a_0_199
  signal :__VdfgRegularize_h7a35cd6a_0_2
  signal :__VdfgRegularize_h7a35cd6a_0_20
  signal :__VdfgRegularize_h7a35cd6a_0_200, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_201
  signal :__VdfgRegularize_h7a35cd6a_0_202, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_203
  signal :__VdfgRegularize_h7a35cd6a_0_204, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_205
  signal :__VdfgRegularize_h7a35cd6a_0_206
  signal :__VdfgRegularize_h7a35cd6a_0_207
  signal :__VdfgRegularize_h7a35cd6a_0_208
  signal :__VdfgRegularize_h7a35cd6a_0_209
  signal :__VdfgRegularize_h7a35cd6a_0_21
  signal :__VdfgRegularize_h7a35cd6a_0_210, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_211, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_212, width: 14
  signal :__VdfgRegularize_h7a35cd6a_0_213
  signal :__VdfgRegularize_h7a35cd6a_0_214
  signal :__VdfgRegularize_h7a35cd6a_0_215
  signal :__VdfgRegularize_h7a35cd6a_0_216
  signal :__VdfgRegularize_h7a35cd6a_0_217
  signal :__VdfgRegularize_h7a35cd6a_0_218
  signal :__VdfgRegularize_h7a35cd6a_0_219
  signal :__VdfgRegularize_h7a35cd6a_0_22
  signal :__VdfgRegularize_h7a35cd6a_0_220
  signal :__VdfgRegularize_h7a35cd6a_0_221
  signal :__VdfgRegularize_h7a35cd6a_0_222, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_223, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_224, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_225, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_226
  signal :__VdfgRegularize_h7a35cd6a_0_227
  signal :__VdfgRegularize_h7a35cd6a_0_228
  signal :__VdfgRegularize_h7a35cd6a_0_229
  signal :__VdfgRegularize_h7a35cd6a_0_23
  signal :__VdfgRegularize_h7a35cd6a_0_230
  signal :__VdfgRegularize_h7a35cd6a_0_231
  signal :__VdfgRegularize_h7a35cd6a_0_232
  signal :__VdfgRegularize_h7a35cd6a_0_233
  signal :__VdfgRegularize_h7a35cd6a_0_234
  signal :__VdfgRegularize_h7a35cd6a_0_235
  signal :__VdfgRegularize_h7a35cd6a_0_236
  signal :__VdfgRegularize_h7a35cd6a_0_237
  signal :__VdfgRegularize_h7a35cd6a_0_238
  signal :__VdfgRegularize_h7a35cd6a_0_239
  signal :__VdfgRegularize_h7a35cd6a_0_24
  signal :__VdfgRegularize_h7a35cd6a_0_240
  signal :__VdfgRegularize_h7a35cd6a_0_241
  signal :__VdfgRegularize_h7a35cd6a_0_242
  signal :__VdfgRegularize_h7a35cd6a_0_243
  signal :__VdfgRegularize_h7a35cd6a_0_244
  signal :__VdfgRegularize_h7a35cd6a_0_245, width: 13
  signal :__VdfgRegularize_h7a35cd6a_0_246
  signal :__VdfgRegularize_h7a35cd6a_0_247
  signal :__VdfgRegularize_h7a35cd6a_0_248
  signal :__VdfgRegularize_h7a35cd6a_0_249
  signal :__VdfgRegularize_h7a35cd6a_0_25
  signal :__VdfgRegularize_h7a35cd6a_0_250, width: 33
  signal :__VdfgRegularize_h7a35cd6a_0_251, width: 33
  signal :__VdfgRegularize_h7a35cd6a_0_252, width: 33
  signal :__VdfgRegularize_h7a35cd6a_0_253, width: 11
  signal :__VdfgRegularize_h7a35cd6a_0_26
  signal :__VdfgRegularize_h7a35cd6a_0_27
  signal :__VdfgRegularize_h7a35cd6a_0_28
  signal :__VdfgRegularize_h7a35cd6a_0_29
  signal :__VdfgRegularize_h7a35cd6a_0_3
  signal :__VdfgRegularize_h7a35cd6a_0_30
  signal :__VdfgRegularize_h7a35cd6a_0_31
  signal :__VdfgRegularize_h7a35cd6a_0_32
  signal :__VdfgRegularize_h7a35cd6a_0_33
  signal :__VdfgRegularize_h7a35cd6a_0_34
  signal :__VdfgRegularize_h7a35cd6a_0_35
  signal :__VdfgRegularize_h7a35cd6a_0_36
  signal :__VdfgRegularize_h7a35cd6a_0_37
  signal :__VdfgRegularize_h7a35cd6a_0_38
  signal :__VdfgRegularize_h7a35cd6a_0_39
  signal :__VdfgRegularize_h7a35cd6a_0_4
  signal :__VdfgRegularize_h7a35cd6a_0_40
  signal :__VdfgRegularize_h7a35cd6a_0_41
  signal :__VdfgRegularize_h7a35cd6a_0_42
  signal :__VdfgRegularize_h7a35cd6a_0_43
  signal :__VdfgRegularize_h7a35cd6a_0_44
  signal :__VdfgRegularize_h7a35cd6a_0_45
  signal :__VdfgRegularize_h7a35cd6a_0_46
  signal :__VdfgRegularize_h7a35cd6a_0_47
  signal :__VdfgRegularize_h7a35cd6a_0_48
  signal :__VdfgRegularize_h7a35cd6a_0_49
  signal :__VdfgRegularize_h7a35cd6a_0_5
  signal :__VdfgRegularize_h7a35cd6a_0_50
  signal :__VdfgRegularize_h7a35cd6a_0_51
  signal :__VdfgRegularize_h7a35cd6a_0_52
  signal :__VdfgRegularize_h7a35cd6a_0_53
  signal :__VdfgRegularize_h7a35cd6a_0_54
  signal :__VdfgRegularize_h7a35cd6a_0_55
  signal :__VdfgRegularize_h7a35cd6a_0_56
  signal :__VdfgRegularize_h7a35cd6a_0_57
  signal :__VdfgRegularize_h7a35cd6a_0_58
  signal :__VdfgRegularize_h7a35cd6a_0_59
  signal :__VdfgRegularize_h7a35cd6a_0_6
  signal :__VdfgRegularize_h7a35cd6a_0_60
  signal :__VdfgRegularize_h7a35cd6a_0_61
  signal :__VdfgRegularize_h7a35cd6a_0_62
  signal :__VdfgRegularize_h7a35cd6a_0_63
  signal :__VdfgRegularize_h7a35cd6a_0_64
  signal :__VdfgRegularize_h7a35cd6a_0_65, width: 32
  signal :__VdfgRegularize_h7a35cd6a_0_66, width: 16
  signal :__VdfgRegularize_h7a35cd6a_0_67
  signal :__VdfgRegularize_h7a35cd6a_0_68
  signal :__VdfgRegularize_h7a35cd6a_0_69
  signal :__VdfgRegularize_h7a35cd6a_0_7
  signal :__VdfgRegularize_h7a35cd6a_0_70
  signal :__VdfgRegularize_h7a35cd6a_0_71
  signal :__VdfgRegularize_h7a35cd6a_0_72
  signal :__VdfgRegularize_h7a35cd6a_0_73
  signal :__VdfgRegularize_h7a35cd6a_0_74
  signal :__VdfgRegularize_h7a35cd6a_0_75
  signal :__VdfgRegularize_h7a35cd6a_0_76
  signal :__VdfgRegularize_h7a35cd6a_0_77
  signal :__VdfgRegularize_h7a35cd6a_0_78
  signal :__VdfgRegularize_h7a35cd6a_0_79
  signal :__VdfgRegularize_h7a35cd6a_0_8
  signal :__VdfgRegularize_h7a35cd6a_0_80
  signal :__VdfgRegularize_h7a35cd6a_0_81
  signal :__VdfgRegularize_h7a35cd6a_0_82
  signal :__VdfgRegularize_h7a35cd6a_0_83
  signal :__VdfgRegularize_h7a35cd6a_0_84
  signal :__VdfgRegularize_h7a35cd6a_0_85
  signal :__VdfgRegularize_h7a35cd6a_0_86
  signal :__VdfgRegularize_h7a35cd6a_0_87
  signal :__VdfgRegularize_h7a35cd6a_0_88
  signal :__VdfgRegularize_h7a35cd6a_0_89
  signal :__VdfgRegularize_h7a35cd6a_0_9
  signal :__VdfgRegularize_h7a35cd6a_0_90
  signal :__VdfgRegularize_h7a35cd6a_0_91
  signal :__VdfgRegularize_h7a35cd6a_0_92
  signal :__VdfgRegularize_h7a35cd6a_0_93
  signal :__VdfgRegularize_h7a35cd6a_0_94
  signal :__VdfgRegularize_h7a35cd6a_0_95
  signal :__VdfgRegularize_h7a35cd6a_0_96
  signal :__VdfgRegularize_h7a35cd6a_0_97
  signal :__VdfgRegularize_h7a35cd6a_0_98
  signal :__VdfgRegularize_h7a35cd6a_0_99
  signal :__VdfgRegularize_h7a35cd6a_1_0
  signal :_unused_ok
  signal :cond_0
  signal :cond_10
  signal :cond_100
  signal :cond_101
  signal :cond_102
  signal :cond_103
  signal :cond_104
  signal :cond_105
  signal :cond_106
  signal :cond_108
  signal :cond_109
  signal :cond_113
  signal :cond_117
  signal :cond_12
  signal :cond_120
  signal :cond_121
  signal :cond_122
  signal :cond_123
  signal :cond_124
  signal :cond_126
  signal :cond_13
  signal :cond_130
  signal :cond_131
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
  signal :cond_153
  signal :cond_154
  signal :cond_155
  signal :cond_158
  signal :cond_16
  signal :cond_162
  signal :cond_164
  signal :cond_165
  signal :cond_166
  signal :cond_168
  signal :cond_17
  signal :cond_170
  signal :cond_172
  signal :cond_174
  signal :cond_175
  signal :cond_176
  signal :cond_178
  signal :cond_183
  signal :cond_184
  signal :cond_185
  signal :cond_186
  signal :cond_187
  signal :cond_188
  signal :cond_19
  signal :cond_190
  signal :cond_191
  signal :cond_193
  signal :cond_196
  signal :cond_197
  signal :cond_2
  signal :cond_20
  signal :cond_200
  signal :cond_201
  signal :cond_204
  signal :cond_205
  signal :cond_206
  signal :cond_207
  signal :cond_209
  signal :cond_211
  signal :cond_213
  signal :cond_217
  signal :cond_218
  signal :cond_219
  signal :cond_220
  signal :cond_221
  signal :cond_222
  signal :cond_223
  signal :cond_225
  signal :cond_226
  signal :cond_227
  signal :cond_232
  signal :cond_236
  signal :cond_239
  signal :cond_24
  signal :cond_240
  signal :cond_241
  signal :cond_244
  signal :cond_246
  signal :cond_249
  signal :cond_25
  signal :cond_250
  signal :cond_252
  signal :cond_253
  signal :cond_254
  signal :cond_255
  signal :cond_256
  signal :cond_259
  signal :cond_26
  signal :cond_260
  signal :cond_267
  signal :cond_270
  signal :cond_272
  signal :cond_273
  signal :cond_279
  signal :cond_28
  signal :cond_282
  signal :cond_284
  signal :cond_285
  signal :cond_286
  signal :cond_29
  signal :cond_294
  signal :cond_295
  signal :cond_296
  signal :cond_297
  signal :cond_3
  signal :cond_30
  signal :cond_31
  signal :cond_34
  signal :cond_35
  signal :cond_37
  signal :cond_38
  signal :cond_39
  signal :cond_40
  signal :cond_41
  signal :cond_42
  signal :cond_44
  signal :cond_47
  signal :cond_49
  signal :cond_50
  signal :cond_51
  signal :cond_54
  signal :cond_55
  signal :cond_6
  signal :cond_63
  signal :cond_64
  signal :cond_65
  signal :cond_67
  signal :cond_68
  signal :cond_7
  signal :cond_72
  signal :cond_73
  signal :cond_74
  signal :cond_79
  signal :cond_8
  signal :cond_87
  signal :cond_88
  signal :cond_9
  signal :cond_93
  signal :cond_95
  signal :cond_96
  signal :cond_98
  signal :cond_99
  signal :e_aaa_sum_ax, width: 16
  signal :e_aas_sub_ax, width: 16
  signal :e_bcd_condition_cf
  signal :e_bit_selected
  signal :e_bit_selector, width: 5
  signal :e_bit_value
  signal :e_bound_dst, width: 32
  signal :e_cmpxchg_eq
  signal :e_cmpxchg_sub, width: 33
  signal :e_cpl_current, width: 2
  signal :e_cr0_reg, width: 32
  signal :e_daa_step1, width: 8
  signal :e_das_step1, width: 8
  signal :e_invd_code_done
  signal :e_invd_data_done
  signal :e_io_allow_bits, width: 4
  signal :e_src_ze, width: 32
  signal :e_wbinvd_code_done
  signal :e_wbinvd_data_done
  signal :exe_arith_adc, width: 33
  signal :exe_arith_add, width: 33
  signal :exe_arith_and, width: 32
  signal :exe_arith_sbb, width: 33
  signal :exe_arith_sub, width: 33
  signal :exe_bcd_condition_af
  signal :exe_buffer_shift
  signal :exe_buffer_shift_word
  signal :exe_buffer_to_reg, width: 32
  signal :exe_cmd_loop_condition
  signal :exe_cmd_loop_ecx
  signal :exe_condition
  signal :exe_int_2_int_trap_same_exception
  signal :exe_jecxz_condition
  signal :exe_new_tss_max, width: 32
  signal :exe_privilege_not_accepted
  signal :exe_push_eflags, width: 32
  signal :exe_segment, width: 3
  signal :exe_selector, width: 16

  # Assignments

  assign :exe_push_eflags,
    sig(:__VdfgRegularize_h7a35cd6a_0_253, width: 11).concat(
      lit(0, width: 2, base: "d", signed: false).concat(
        sig(:acflag, width: 1).concat(
          sig(:vmflag, width: 1).concat(
            sig(:rflag, width: 1).concat(
              lit(0, width: 1, base: "d", signed: false).concat(
                sig(:__VdfgRegularize_h7a35cd6a_0_0, width: 15)
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_253,
    sig(:idflag, width: 1)
  assign :__VdfgRegularize_h7a35cd6a_0_0,
    sig(:ntflag, width: 1).concat(
      sig(:iopl, width: 2).concat(
        sig(:oflag, width: 1).concat(
          sig(:dflag, width: 1).concat(
            sig(:iflag, width: 1).concat(
              sig(:tflag, width: 1).concat(
                sig(:sflag, width: 1).concat(
                  sig(:zflag, width: 1).concat(
                    lit(0, width: 1, base: "d", signed: false).concat(
                      sig(:aflag, width: 1).concat(
                        lit(0, width: 1, base: "d", signed: false).concat(
                          sig(:pflag, width: 1).concat(
                            lit(1, width: 1, base: "h", signed: false).concat(
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
  assign :exe_segment,
    sig(:glob_param_1, width: 32)[18..16]
  assign :exe_selector,
    sig(:glob_param_1, width: 32)[15..0]
  assign :exe_privilege_not_accepted,
    (
        (
            sig(:glob_param_1, width: 32)[1..0] >
            sig(:glob_descriptor, width: 64)[46..45]
        ) |
        (
            sig(:cpl, width: 2) >
            sig(:glob_descriptor, width: 64)[46..45]
        )
    )
  assign :exe_arith_adc,
    (
        sig(:exe_arith_add, width: 33) +
        sig(:__VdfgRegularize_h7a35cd6a_0_250, width: 33)
    )
  assign :exe_arith_add,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_252, width: 33) +
        sig(:__VdfgRegularize_h7a35cd6a_0_251, width: 33)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_250,
    sig(:cflag, width: 1)
  assign :__VdfgRegularize_h7a35cd6a_0_252,
    lit(0, width: 1, base: "d", signed: false).concat(
      sig(:src, width: 32)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_251,
    lit(0, width: 1, base: "d", signed: false).concat(
      sig(:dst, width: 32)
    )
  assign :exe_arith_and,
    (
        sig(:dst, width: 32) &
        sig(:src, width: 32)
    )
  assign :exe_arith_sub,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_251, width: 33) -
        sig(:__VdfgRegularize_h7a35cd6a_0_252, width: 33)
    )
  assign :exe_arith_sbb,
    (
        sig(:exe_arith_sub, width: 33) -
        sig(:__VdfgRegularize_h7a35cd6a_0_250, width: 33)
    )
  assign :exe_arith_sub_carry,
    mux(
      sig(:exe_cmpxchg_switch, width: 1),
      (
          sig(:exe_cmpxchg_switch, width: 1) &
          sig(:e_cmpxchg_sub, width: 33)[32]
      ),
      sig(:exe_arith_sub, width: 33)[32]
    )
  assign :exe_cmpxchg_switch,
    (
        lit(52, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :e_cmpxchg_sub,
    (
        lit(0, width: 1, base: "d", signed: false).concat(
          sig(:eax, width: 32)
        ) -
        sig(:__VdfgRegularize_h7a35cd6a_0_251, width: 33)
    )
  assign :exe_arith_add_carry,
    sig(:exe_arith_add, width: 33)[32]
  assign :exe_arith_adc_carry,
    sig(:exe_arith_adc, width: 33)[32]
  assign :exe_arith_sbb_carry,
    sig(:exe_arith_sbb, width: 33)[32]
  assign :task_eip,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_1, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:exe_buffer_shifted, width: 464)[415..400]
      ),
      sig(:exe_buffer_shifted, width: 464)[431..400]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_1,
    (
        lit(3, width: 4, base: "h", signed: false) >=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :exe_branch_eip,
    mux(
      sig(:exe_operand_16bit, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:e_eip_next_sum, width: 32)[15..0]
      ),
      sig(:e_eip_next_sum, width: 32)
    )
  assign :exe_jecxz_condition,
    mux(
      sig(:exe_address_16bit, width: 1),
      (
          lit(0, width: 16, base: "h", signed: false) ==
          sig(:ecx, width: 32)[15..0]
      ),
      (
          lit(0, width: 32, base: "h", signed: false) ==
          sig(:ecx, width: 32)
      )
    )
  assign :e_io_allow_bits,
    case_select(
      sig(:glob_param_1, width: 32)[2..0],
      cases: {
        0 => sig(:src, width: 32)[3..0],
        1 => sig(:src, width: 32)[4..1],
        2 => sig(:src, width: 32)[5..2],
        3 => sig(:src, width: 32)[6..3],
        4 => sig(:src, width: 32)[7..4],
        5 => sig(:src, width: 32)[8..5],
        6 => sig(:src, width: 32)[9..6]
      },
      default: sig(:src, width: 32)[10..7]
    )
  assign :exe_int_2_int_trap_same_exception,
    (
        sig(:v8086_mode, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_2, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_3, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_2,
    (
        sig(:glob_descriptor, width: 64)[43] &
        sig(:glob_descriptor, width: 64)[42]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_3,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:glob_descriptor, width: 64)[46..45]
    )
  assign :e_cpl_current,
    mux(
      sig(:glob_param_1, width: 32)[20],
      sig(:glob_param_3, width: 32)[1..0],
      sig(:cpl, width: 2)
    )
  assign :exe_load_seg_gp_fault,
    (
        sig(:cond_113, width: 1) &
        (
            (
                (
                    lit(6, width: 3, base: "h", signed: false) >
                    sig(:exe_segment, width: 3)
                ) &
                (
                    (
                        lit(1, width: 3, base: "h", signed: false) !=
                        sig(:exe_segment, width: 3)
                    ) &
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) |
                        (
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_5, width: 1) &
                                (
                                    (
                                        sig(:glob_param_1, width: 32)[1..0] !=
                                        sig(:e_cpl_current, width: 2)
                                    ) |
                                    (
                                        sig(:glob_descriptor, width: 64)[43] |
                                        (
                                            sig(:__VdfgRegularize_h7a35cd6a_0_8, width: 1) |
                                            (
                                                sig(:glob_descriptor, width: 64)[46..45] !=
                                                sig(:e_cpl_current, width: 2)
                                            )
                                        )
                                    )
                                )
                            ) |
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_9, width: 1) &
                                sig(:__VdfgRegularize_h7a35cd6a_0_11, width: 1)
                            )
                        )
                    )
                )
            ) |
            (
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_12, width: 1) &
                    sig(:__VdfgRegularize_h7a35cd6a_0_14, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_15, width: 1) &
                        sig(:__VdfgRegularize_h7a35cd6a_0_18, width: 1)
                    ) |
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_19, width: 1) &
                        (
                            (
                                sig(:glob_param_1, width: 32)[1..0] <
                                sig(:cpl, width: 2)
                            ) |
                            sig(:__VdfgRegularize_h7a35cd6a_0_242, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :cond_113,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[33] &
        sig(:cond_67, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_4,
    (
      ~sig(:glob_descriptor, width: 64)[44]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_5,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:exe_segment, width: 3)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_8,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_6, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_7, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_9,
    (
        lit(2, width: 3, base: "h", signed: false) !=
        sig(:exe_segment, width: 3)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_11,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_249, width: 1) |
        sig(:__VdfgRegularize_h7a35cd6a_0_10, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_12,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:exe_segment, width: 3)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_14,
    (
        sig(:glob_descriptor, width: 64)[44] |
        sig(:__VdfgRegularize_h7a35cd6a_0_13, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_15,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:exe_segment, width: 3)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_18,
    (
        sig(:glob_descriptor, width: 64)[44] |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_16, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_17, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_19,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:exe_segment, width: 3)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_242,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_98, width: 1) |
        (
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_248, width: 1) &
                sig(:__VdfgRegularize_h7a35cd6a_0_20, width: 1)
            ) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_2, width: 1) &
                (
                    sig(:glob_descriptor, width: 64)[46..45] >
                    sig(:glob_param_1, width: 32)[1..0]
                )
            )
        )
    )
  assign :exe_load_seg_ss_fault,
    (
        (
          ~sig(:glob_param_1, width: 32)[21]
        ) &
        (
            sig(:cond_113, width: 1) &
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_21, width: 1) &
                sig(:__VdfgRegularize_h7a35cd6a_0_5, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_21,
    (
      ~sig(:glob_descriptor, width: 64)[47]
    )
  assign :exe_load_seg_np_fault,
    (
        sig(:cond_113, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_21, width: 1) &
            (
                sig(:glob_param_1, width: 32)[21] |
                sig(:__VdfgRegularize_h7a35cd6a_0_9, width: 1)
            )
        )
    )
  assign :e_bit_selector,
    mux(
      sig(:exe_operand_16bit, width: 1),
      lit(0, width: 1, base: "d", signed: false).concat(
        sig(:src, width: 32)[3..0]
      ),
      sig(:src, width: 32)[4..0]
    )
  assign :e_bit_selected,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_22, width: 1),
      sig(:dst, width: 32)[0],
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_23, width: 1),
        sig(:dst, width: 32)[1],
        mux(
          sig(:__VdfgRegularize_h7a35cd6a_0_24, width: 1),
          sig(:dst, width: 32)[2],
          mux(
            sig(:__VdfgRegularize_h7a35cd6a_0_25, width: 1),
            sig(:dst, width: 32)[3],
            mux(
              sig(:__VdfgRegularize_h7a35cd6a_0_26, width: 1),
              sig(:dst, width: 32)[4],
              mux(
                sig(:__VdfgRegularize_h7a35cd6a_0_27, width: 1),
                sig(:dst, width: 32)[5],
                mux(
                  sig(:__VdfgRegularize_h7a35cd6a_0_28, width: 1),
                  sig(:dst, width: 32)[6],
                  mux(
                    sig(:__VdfgRegularize_h7a35cd6a_0_29, width: 1),
                    sig(:dst, width: 32)[7],
                    mux(
                      sig(:__VdfgRegularize_h7a35cd6a_0_30, width: 1),
                      sig(:dst, width: 32)[8],
                      mux(
                        sig(:__VdfgRegularize_h7a35cd6a_0_31, width: 1),
                        sig(:dst, width: 32)[9],
                        mux(
                          sig(:__VdfgRegularize_h7a35cd6a_0_32, width: 1),
                          sig(:dst, width: 32)[10],
                          mux(
                            sig(:__VdfgRegularize_h7a35cd6a_0_33, width: 1),
                            sig(:dst, width: 32)[11],
                            mux(
                              sig(:__VdfgRegularize_h7a35cd6a_0_34, width: 1),
                              sig(:dst, width: 32)[12],
                              mux(
                                sig(:__VdfgRegularize_h7a35cd6a_0_35, width: 1),
                                sig(:dst, width: 32)[13],
                                mux(
                                  sig(:__VdfgRegularize_h7a35cd6a_0_36, width: 1),
                                  sig(:dst, width: 32)[14],
                                  mux(
                                    sig(:__VdfgRegularize_h7a35cd6a_0_37, width: 1),
                                    sig(:dst, width: 32)[15],
                                    mux(
                                      sig(:__VdfgRegularize_h7a35cd6a_0_38, width: 1),
                                      sig(:dst, width: 32)[16],
                                      mux(
                                        sig(:__VdfgRegularize_h7a35cd6a_0_39, width: 1),
                                        sig(:dst, width: 32)[17],
                                        mux(
                                          sig(:__VdfgRegularize_h7a35cd6a_0_40, width: 1),
                                          sig(:dst, width: 32)[18],
                                          mux(
                                            sig(:__VdfgRegularize_h7a35cd6a_0_41, width: 1),
                                            sig(:dst, width: 32)[19],
                                            mux(
                                              sig(:__VdfgRegularize_h7a35cd6a_0_42, width: 1),
                                              sig(:dst, width: 32)[20],
                                              mux(
                                                sig(:__VdfgRegularize_h7a35cd6a_0_43, width: 1),
                                                sig(:dst, width: 32)[21],
                                                mux(
                                                  sig(:__VdfgRegularize_h7a35cd6a_0_44, width: 1),
                                                  sig(:dst, width: 32)[22],
                                                  mux(
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_45, width: 1),
                                                    sig(:dst, width: 32)[23],
                                                    mux(
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_46, width: 1),
                                                      sig(:dst, width: 32)[24],
                                                      mux(
                                                        sig(:__VdfgRegularize_h7a35cd6a_0_47, width: 1),
                                                        sig(:dst, width: 32)[25],
                                                        mux(
                                                          sig(:__VdfgRegularize_h7a35cd6a_0_48, width: 1),
                                                          sig(:dst, width: 32)[26],
                                                          mux(
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_49, width: 1),
                                                            sig(:dst, width: 32)[27],
                                                            mux(
                                                              sig(:__VdfgRegularize_h7a35cd6a_0_50, width: 1),
                                                              sig(:dst, width: 32)[28],
                                                              mux(
                                                                sig(:__VdfgRegularize_h7a35cd6a_0_51, width: 1),
                                                                sig(:dst, width: 32)[29],
                                                                mux(
                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_52, width: 1),
                                                                  sig(:dst, width: 32)[30],
                                                                  sig(:dst, width: 32)[31]
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_22,
    (
        lit(0, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_23,
    (
        lit(1, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_24,
    (
        lit(2, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_25,
    (
        lit(3, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_26,
    (
        lit(4, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_27,
    (
        lit(5, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_28,
    (
        lit(6, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_29,
    (
        lit(7, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_30,
    (
        lit(8, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_31,
    (
        lit(9, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_32,
    (
        lit(10, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_33,
    (
        lit(11, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_34,
    (
        lit(12, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_35,
    (
        lit(13, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_36,
    (
        lit(14, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_37,
    (
        lit(15, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_38,
    (
        lit(16, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_39,
    (
        lit(17, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_40,
    (
        lit(18, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_41,
    (
        lit(19, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_42,
    (
        lit(20, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_43,
    (
        lit(21, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_44,
    (
        lit(22, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_45,
    (
        lit(23, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_46,
    (
        lit(24, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_47,
    (
        lit(25, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_48,
    (
        lit(26, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_49,
    (
        lit(27, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_50,
    (
        lit(28, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_51,
    (
        lit(29, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_52,
    (
        lit(30, width: 5, base: "h", signed: false) ==
        sig(:e_bit_selector, width: 5)
    )
  assign :e_bit_value,
    (
      ~mux(sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[39], sig(:e_bit_selected, width: 1), sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[38])
    )
  assign :e_cr0_reg,
    sig(:cr0_pg, width: 1).concat(
      sig(:cr0_cd, width: 1).concat(
        sig(:cr0_nw, width: 1).concat(
          lit(0, width: 10, base: "d", signed: false).concat(
            sig(:cr0_am, width: 1).concat(
              lit(0, width: 1, base: "d", signed: false).concat(
                sig(:cr0_wp, width: 1).concat(
                  lit(0, width: 10, base: "d", signed: false).concat(
                    sig(:cr0_ne, width: 1).concat(
                      lit(1, width: 1, base: "h", signed: false).concat(
                        sig(:cr0_ts, width: 1).concat(
                          sig(:cr0_em, width: 1).concat(
                            sig(:cr0_mp, width: 1).concat(
                              sig(:cr0_pe, width: 1)
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :e_cmpxchg_eq,
    (
        (
            sig(:exe_is_8bit, width: 1) &
            (
                sig(:eax, width: 32)[7..0] ==
                sig(:dst, width: 32)[7..0]
            )
        ) |
        (
            (
                sig(:exe_operand_16bit, width: 1) &
                (
                    sig(:eax, width: 32)[15..0] ==
                    sig(:dst, width: 32)[15..0]
                )
            ) |
            (
                sig(:exe_operand_32bit, width: 1) &
                (
                    sig(:dst, width: 32) ==
                    sig(:eax, width: 32)
                )
            )
        )
    )
  assign :exe_cmd_loop_ecx,
    mux(
      sig(:exe_address_16bit, width: 1),
      (
          lit(1, width: 16, base: "h", signed: false) !=
          sig(:ecx, width: 32)[15..0]
      ),
      (
          lit(1, width: 32, base: "h", signed: false) !=
          sig(:ecx, width: 32)
      )
    )
  assign :exe_cmd_loop_condition,
    mux(
      sig(:cond_9, width: 1),
      (
          (
            ~sig(:zflag, width: 1)
          ) &
          sig(:exe_cmd_loop_ecx, width: 1)
      ),
      mux(
        sig(:cond_67, width: 1),
        (
            sig(:exe_cmd_loop_ecx, width: 1) &
            sig(:zflag, width: 1)
        ),
        sig(:exe_cmd_loop_ecx, width: 1)
      )
    )
  assign :cond_9,
    (
        lit(0, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_67,
    (
        lit(1, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :e_bound_dst,
    mux(
      sig(:exe_operand_16bit, width: 1),
      sig(:dst, width: 32)[15].replicate(
        lit(16, width: 32, base: "h", signed: true)
      ).concat(
        sig(:dst, width: 32)[15..0]
      ),
      sig(:dst, width: 32)
    )
  assign :exe_bound_fault,
    (
        sig(:cond_244, width: 1) &
        (
            (
                sig(:e_bound_dst, width: 32) <
                mux(
                  sig(:exe_operand_16bit, width: 1),
                  sig(:exe_buffer, width: 32)[15].replicate(
                    lit(16, width: 32, base: "h", signed: true)
                  ).concat(
                    sig(:exe_buffer, width: 32)[15..0]
                  ),
                  sig(:exe_buffer, width: 32)
                )
            ) |
            (
                sig(:e_bound_dst, width: 32) >
                mux(
                  sig(:exe_operand_16bit, width: 1),
                  sig(:__VdfgRegularize_h7a35cd6a_0_65, width: 32),
                  sig(:src, width: 32)
                )
            )
        )
    )
  assign :cond_244,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[97] &
        sig(:cond_67, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_65,
    sig(:src, width: 32)[15].replicate(
      lit(16, width: 32, base: "h", signed: true)
    ).concat(
      sig(:src, width: 32)[15..0]
    )
  assign :exe_new_tss_max,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_1, width: 1),
      lit(43, width: 32, base: "h", signed: false),
      lit(103, width: 32, base: "h", signed: false)
    )
  assign :e_bcd_condition_cf,
    (
        (
            lit(153, width: 8, base: "h", signed: false) <
            sig(:dst, width: 32)[7..0]
        ) |
        sig(:cflag, width: 1)
    )
  assign :exe_bcd_condition_af,
    (
        (
            lit(9, width: 4, base: "h", signed: false) <
            sig(:dst, width: 32)[3..0]
        ) |
        sig(:aflag, width: 1)
    )
  assign :e_aaa_sum_ax,
    (
        lit(262, width: 16, base: "h", signed: false) +
        sig(:dst, width: 32)[15..0]
    )
  assign :e_aas_sub_ax,
    (
        sig(:dst, width: 32)[15..0] -
        lit(262, width: 16, base: "h", signed: false)
    )
  assign :e_daa_step1,
    mux(
      sig(:exe_bcd_condition_af, width: 1),
      (
          lit(6, width: 8, base: "h", signed: false) +
          sig(:dst, width: 32)[7..0]
      ),
      sig(:dst, width: 32)[7..0]
    )
  assign :e_das_step1,
    mux(
      sig(:exe_bcd_condition_af, width: 1),
      (
          sig(:dst, width: 32)[7..0] -
          lit(6, width: 8, base: "h", signed: false)
      ),
      sig(:dst, width: 32)[7..0]
    )
  assign :e_src_ze,
    mux(
      sig(:exe_operand_16bit, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:src, width: 32)[15..0]
      ),
      sig(:src, width: 32)
    )
  assign :cond_0,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[1] &
        sig(:cond_9, width: 1)
    )
  assign :cond_2,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[2]
  assign :cond_3,
    sig(:exe_mutex_current, width: 11)[1]
  assign :cond_6,
    (
        sig(:cond_205, width: 1) &
        sig(:cond_9, width: 1)
    )
  assign :cond_205,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[4]
  assign :cond_7,
    (
        sig(:glob_param_2, width: 32) >
        sig(:glob_desc_limit, width: 32)
    )
  assign :cond_8,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_246, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_246,
    (
        sig(:cond_9, width: 1) |
        sig(:__VdfgRegularize_h7a35cd6a_0_86, width: 1)
    )
  assign :cond_10,
    sig(:exe_mutex_current, width: 11)[4]
  assign :cond_12,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:cond_67, width: 1)
    )
  assign :cond_13,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_69,
    (
        lit(4, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_14,
    (
        sig(:glob_param_2, width: 32) >
        sig(:cs_limit, width: 32)
    )
  assign :cond_15,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_70,
    (
        lit(5, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_16,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_71, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_71,
    (
        lit(6, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_17,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_72, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_72,
    (
        lit(7, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_19,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_73,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_20,
    sig(:exe_mutex_current, width: 11)[10]
  assign :cond_24,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_76, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_76,
    (
        lit(13, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_25,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_77, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_77,
    (
        lit(14, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_26,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_78, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_78,
    (
        lit(15, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_28,
    (
        sig(:cond_205, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1)
    )
  assign :cond_29,
    (
        sig(:cond_205, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
    )
  assign :cond_30,
    (
        sig(:cond_205, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_74,
    (
        lit(9, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_31,
    (
        sig(:cond_205, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_75, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_75,
    (
        lit(10, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_34,
    (
        sig(:cond_205, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_76, width: 1)
    )
  assign :cond_35,
    (
        lit(0, width: 14, base: "h", signed: false) ==
        sig(:glob_param_3, width: 32)[15..2]
    )
  assign :cond_37,
    (
        sig(:cond_205, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_78, width: 1)
    )
  assign :cond_38,
    sig(:ss_cache, width: 64)[54]
  assign :cond_39,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[5] &
        sig(:__VdfgRegularize_h7a35cd6a_0_80, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_80,
    (
        sig(:cond_9, width: 1) |
        sig(:cond_67, width: 1)
    )
  assign :cond_40,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[5] &
        sig(:cond_165, width: 1)
    )
  assign :cond_165,
    (
        lit(2, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_41,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[5] &
        sig(:cond_188, width: 1)
    )
  assign :cond_188,
    (
        lit(3, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_42,
    sig(:glob_descriptor_2, width: 64)[54]
  assign :cond_44,
    (
        sig(:glob_param_2, width: 32) >
        sig(:glob_desc_2_limit, width: 32)
    )
  assign :cond_47,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[6] &
        (
          ~sig(:exe_cmdex, width: 4)[3]
        )
    )
  assign :cond_49,
    (
        lit(7, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_50,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[8]
  assign :cond_51,
    sig(:exe_mutex_current, width: 11)[8]
  assign :cond_54,
    (
        lit(0, width: 2, base: "h", signed: false) <
        sig(:cpl, width: 2)
    )
  assign :cond_55,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[9] &
        sig(:cond_67, width: 1)
    )
  assign :cond_63,
    (
        lit(13, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_64,
    (
        lit(14, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_65,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[15] &
        (
            lit(2, width: 4, base: "h", signed: false) !=
            sig(:exe_cmdex, width: 4)
        )
    )
  assign :cond_68,
    (
        lit(16, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_72,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:cpl, width: 2)
    )
  assign :cond_73,
    (
        sig(:cond_209, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_76, width: 1)
    )
  assign :cond_209,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[28]
  assign :cond_74,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
        sig(:__VdfgRegularize_h7a35cd6a_0_72, width: 1)
    )
  assign :exe_trigger_gp_fault,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_116, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_117, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_118, width: 1) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_119, width: 1) |
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_120, width: 1) |
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_121, width: 1) |
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_122, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h7a35cd6a_0_124, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_125, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h7a35cd6a_0_126, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h7a35cd6a_0_127, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_128, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h7a35cd6a_0_129, width: 1) |
                                                        (
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_130, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h7a35cd6a_0_131, width: 1) |
                                                                (
                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_132, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_133, width: 1) |
                                                                        (
                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_134, width: 1) |
                                                                            (
                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_135, width: 1) |
                                                                                (
                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_136, width: 1) |
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_137, width: 1) |
                                                                                        (
                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_138, width: 1) |
                                                                                            (
                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_238, width: 1) |
                                                                                                (
                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_139, width: 1) |
                                                                                                    (
                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_140, width: 1) |
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_141, width: 1) |
                                                                                                            (
                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_142, width: 1) |
                                                                                                                (
                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_143, width: 1) |
                                                                                                                    (
                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_144, width: 1) |
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_145, width: 1) |
                                                                                                                            (
                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_146, width: 1) |
                                                                                                                                (
                                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_147, width: 1) |
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_148, width: 1) |
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_149, width: 1) |
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_150, width: 1) |
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_151, width: 1) |
                                                                                                                                                    (
                                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_152, width: 1) |
                                                                                                                                                        (
                                                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_153, width: 1) |
                                                                                                                                                            (
                                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_154, width: 1) |
                                                                                                                                                                (
                                                                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_155, width: 1) |
                                                                                                                                                                    (
                                                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_156, width: 1) |
                                                                                                                                                                        (
                                                                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_236, width: 1) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_157, width: 1) |
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_158, width: 1) |
                                                                                                                                                                                    (
                                                                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_159, width: 1) |
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_160, width: 1) |
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_161, width: 1) |
                                                                                                                                                                                                (
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :__VdfgRegularize_h7a35cd6a_0_235,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ) |
                                                                                                                                                                                                    (
                                                                                                                                                                                                      sig(:__VdfgRegularize_h7a35cd6a_0_234, width: 1) |
                                                                                                                                                                                                      (sig(:__VdfgRegularize_h7a35cd6a_0_162, width: 1) | sig(:__VdfgRegularize_h7a35cd6a_0_233, width: 1))
                                                                                                                                                                                                    )
                                                                                                                                                                                                )
                                                                                                                                                                                            )
                                                                                                                                                                                        )
                                                                                                                                                                                    )
                                                                                                                                                                                )
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    )
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_116,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_240, width: 1) &
        (
            sig(:exe_jecxz_condition, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_67, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_117,
    (
        sig(:cond_6, width: 1) &
        sig(:cond_7, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_118,
    (
        sig(:cond_13, width: 1) &
        sig(:cond_14, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_119,
    (
        sig(:cond_17, width: 1) &
        (
            sig(:exe_operand_32bit, width: 1) &
            sig(:cond_14, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_120,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1) &
            (
                sig(:exe_operand_16bit, width: 1) &
                sig(:cond_14, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_121,
    (
        sig(:cond_31, width: 1) &
        sig(:cond_7, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_122,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[5] &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1) &
            sig(:cond_44, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_124,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_239, width: 1) &
        (
            sig(:exe_condition, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_67, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_125,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[9] &
        sig(:__VdfgRegularize_h7a35cd6a_1_0, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_126,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[10] &
        sig(:__VdfgRegularize_h7a35cd6a_1_0, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_127,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[11] &
        (
            sig(:cond_67, width: 1) &
            (
                (
                    sig(:exe_is_8bit, width: 1) &
                    sig(:e_io_allow_bits, width: 4)[0]
                ) |
                (
                    (
                      ~sig(:exe_is_8bit, width: 1)
                    ) &
                    (
                        (
                            sig(:exe_operand_16bit, width: 1) &
                            (
                                lit(0, width: 2, base: "h", signed: false) !=
                                sig(:e_io_allow_bits, width: 4)[1..0]
                            )
                        ) |
                        (
                            sig(:exe_operand_32bit, width: 1) &
                            (
                                lit(0, width: 4, base: "h", signed: false) !=
                                sig(:e_io_allow_bits, width: 4)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_128,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[12] &
        sig(:__VdfgRegularize_h7a35cd6a_1_0, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_129,
    (
        sig(:cond_65, width: 1) &
        sig(:cond_14, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_130,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[20] |
            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[21]
        ) &
        (
            sig(:cond_9, width: 1) &
            sig(:cond_72, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_131,
    (
        sig(:cond_74, width: 1) &
        (
            sig(:v8086_mode, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_3, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_132,
    (
        sig(:offset_new_stack, width: 1) &
        sig(:cond_44, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_133,
    (
        sig(:cond_209, width: 1) &
        (
            sig(:cond_67, width: 1) &
            (
                sig(:exc_soft_int_ib, width: 1) &
                sig(:cond_124, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_134,
    (
        sig(:offset_int_real, width: 1) &
        (
            lit(0, width: 6, base: "d", signed: false).concat(
              sig(:exc_vector, width: 8).concat(
                lit(3, width: 2, base: "h", signed: false)
              )
            ) >
            sig(:idtr_limit, width: 16)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_135,
    (
        sig(:cond_209, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1) &
            sig(:cond_14, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_136,
    (
        sig(:cond_209, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1) &
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_245, width: 13).concat(
                  lit(7, width: 3, base: "h", signed: false)
                ) >
                sig(:idtr_limit, width: 16)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_137,
    (
        sig(:cond_93, width: 1) &
        (
            sig(:glob_descriptor, width: 64)[44] |
            (
                (
                    (
                        lit(5, width: 4, base: "h", signed: false) !=
                        sig(:glob_descriptor, width: 64)[43..40]
                    ) &
                    (
                        (
                            lit(14, width: 4, base: "h", signed: false) !=
                            sig(:glob_descriptor, width: 64)[43..40]
                        ) &
                        (
                            (
                                lit(6, width: 4, base: "h", signed: false) !=
                                sig(:glob_descriptor, width: 64)[43..40]
                            ) &
                            (
                                (
                                    lit(15, width: 4, base: "h", signed: false) !=
                                    sig(:glob_descriptor, width: 64)[43..40]
                                ) &
                                (
                                    lit(7, width: 4, base: "h", signed: false) !=
                                    sig(:glob_descriptor, width: 64)[43..40]
                                )
                            )
                        )
                    )
                ) |
                (
                    sig(:exc_soft_int, width: 1) &
                    sig(:__VdfgRegularize_h7a35cd6a_0_83, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_138,
    (
        sig(:cond_96, width: 1) &
        (
            sig(:exe_int_2_int_trap_same_exception, width: 1) |
            sig(:cond_7, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_238,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[33] &
        (
            sig(:cond_9, width: 1) &
            (
                sig(:protected_mode, width: 1) &
                (
                    (
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_5, width: 1) |
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_15, width: 1) |
                                sig(:__VdfgRegularize_h7a35cd6a_0_19, width: 1)
                            )
                        ) &
                        sig(:__VdfgRegularize_h7a35cd6a_0_85, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_12, width: 1) |
                            sig(:__VdfgRegularize_h7a35cd6a_0_15, width: 1)
                        ) &
                        sig(:cond_130, width: 1)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_139,
    (
        sig(:offset_iret, width: 1) &
        sig(:cond_7, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_140,
    (
        sig(:cond_120, width: 1) &
        sig(:cond_44, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_141,
    (
        sig(:cond_123, width: 1) &
        sig(:cond_124, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_142,
    (
        sig(:cond_126, width: 1) &
        (
            sig(:cond_267, width: 1) &
            sig(:cond_14, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_143,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[40] &
        (
            sig(:cond_188, width: 1) &
            (
                sig(:glob_param_1, width: 32)[1..0] !=
                sig(:glob_param_3, width: 32)[1..0]
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_144,
    (
        sig(:cond_145, width: 1) &
        sig(:cond_54, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_145,
    (
        sig(:cond_146, width: 1) &
        sig(:cond_54, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_146,
    (
        sig(:cond_150, width: 1) &
        (
            sig(:cond_54, width: 1) |
            (
                sig(:cond_147, width: 1) &
                (
                    (
                        (
                          ~sig(:src, width: 32)[0]
                        ) &
                        sig(:src, width: 32)[31]
                    ) |
                    (
                        (
                          ~sig(:src, width: 32)[30]
                        ) &
                        sig(:src, width: 32)[29]
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_147,
    (
        sig(:cond_153, width: 1) &
        sig(:cond_72, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_148,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[58] &
        sig(:__VdfgRegularize_h7a35cd6a_1_0, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_149,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_237, width: 1) &
        (
            sig(:exe_cmd_loop_condition, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_67, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_150,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[62] &
        sig(:cond_54, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_151,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[63] &
        (
            sig(:cond_165, width: 1) &
            (
                (
                    sig(:real_mode, width: 1) |
                    sig(:v8086_mode, width: 1)
                ) &
                sig(:cond_14, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_152,
    (
        sig(:cond_183, width: 1) &
        sig(:cond_7, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_153,
    (
        sig(:cond_184, width: 1) &
        sig(:cond_44, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_154,
    (
        sig(:cond_201, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_85, width: 1) |
            (
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) &
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_83, width: 1) |
                        (
                            (
                                sig(:glob_descriptor, width: 64)[46..45] <
                                sig(:glob_param_1, width: 32)[1..0]
                            ) |
                            (
                                (
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_89, width: 1) |
                                        sig(:__VdfgRegularize_h7a35cd6a_0_90, width: 1)
                                    ) &
                                    sig(:cond_130, width: 1)
                                ) |
                                (
                                    sig(:__VdfgRegularize_h7a35cd6a_0_53, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_54, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h7a35cd6a_0_55, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h7a35cd6a_0_56, width: 1) |
                                                (
                                                    (
                                                        lit(2, width: 4, base: "h", signed: false) ==
                                                        sig(:glob_descriptor, width: 64)[43..40]
                                                    ) |
                                                    (
                                                        (
                                                            lit(3, width: 4, base: "h", signed: false) ==
                                                            sig(:glob_descriptor, width: 64)[43..40]
                                                        ) |
                                                        (
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_58, width: 1) |
                                                            (
                                                                sig(:__VdfgRegularize_h7a35cd6a_0_60, width: 1) |
                                                                (
                                                                    (
                                                                        lit(11, width: 4, base: "h", signed: false) ==
                                                                        sig(:glob_descriptor, width: 64)[43..40]
                                                                    ) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_57, width: 1) |
                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_59, width: 1)
                                                                    )
                                                                )
                                                            )
                                                        )
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
                    sig(:glob_descriptor, width: 64)[44] &
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_6, width: 1) |
                        (
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_248, width: 1) &
                                (
                                    sig(:__VdfgRegularize_h7a35cd6a_0_91, width: 1) |
                                    (
                                        sig(:glob_param_1, width: 32)[1..0] >
                                        sig(:cpl, width: 2)
                                    )
                                )
                            ) |
                            sig(:__VdfgRegularize_h7a35cd6a_0_93, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_155,
    (
        sig(:cond_207, width: 1) &
        (
            sig(:cond_130, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_18, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_156,
    (
        sig(:cond_211, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_244, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_92, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_236,
    (
        sig(:cond_220, width: 1) &
        (
            (
              ~sig(:cond_221, width: 1)
            ) &
            sig(:cond_124, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_157,
    (
        sig(:cond_225, width: 1) &
        sig(:cond_14, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_158,
    (
        sig(:cond_206, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_72, width: 1) &
            sig(:cond_14, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_159,
    (
        sig(:cond_206, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_79, width: 1) &
            sig(:cond_7, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_160,
    (
        sig(:cond_232, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_244, width: 1) |
            (
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_248, width: 1) &
                    sig(:__VdfgRegularize_h7a35cd6a_0_91, width: 1)
                ) |
                sig(:__VdfgRegularize_h7a35cd6a_0_93, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_161,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[88] &
        (
            sig(:cond_165, width: 1) &
            sig(:cond_7, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_235,
    (
        sig(:cond_240, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_123, width: 1) &
            sig(:cond_124, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_234,
    (
        sig(:cond_241, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_123, width: 1) &
            (
                (
                    sig(:protected_mode, width: 1) &
                    (
                        sig(:iopl, width: 2) <
                        sig(:cpl, width: 2)
                    )
                ) |
                (
                    sig(:v8086_mode, width: 1) &
                    (
                        lit(3, width: 2, base: "h", signed: false) !=
                        sig(:iopl, width: 2)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_162,
    (
        sig(:exe_task_switch_finished, width: 1) &
        (
            sig(:exe_eip, width: 32) >
            sig(:cs_limit, width: 32)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_233,
    (
        sig(:cond_286, width: 1) &
        (
            (
              ~sig(:cond_294, width: 1)
            ) &
            sig(:cond_54, width: 1)
        )
    )
  assign :cond_79,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[30] &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1)
        )
    )
  assign :cond_87,
    (
        sig(:cond_209, width: 1) &
        sig(:cond_188, width: 1)
    )
  assign :cond_88,
    (
        sig(:cond_209, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1)
    )
  assign :cond_93,
    (
        sig(:cond_209, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1)
    )
  assign :cond_95,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_81, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_21, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_81,
    (
      ~sig(:exe_trigger_gp_fault, width: 1)
    )
  assign :cond_96,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
        sig(:cond_9, width: 1)
    )
  assign :cond_98,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
        sig(:cond_67, width: 1)
    )
  assign :cond_99,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
        sig(:cond_165, width: 1)
    )
  assign :cond_100,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
        sig(:cond_188, width: 1)
    )
  assign :cond_101,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
        sig(:__VdfgRegularize_h7a35cd6a_0_84, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_84,
    (
        lit(10, width: 4, base: "h", signed: false) <=
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_102,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[30] &
        sig(:cond_9, width: 1)
    )
  assign :cond_103,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[30] &
        sig(:cond_67, width: 1)
    )
  assign :cond_104,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[30] &
        sig(:cond_165, width: 1)
    )
  assign :cond_105,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[30] &
        sig(:cond_188, width: 1)
    )
  assign :cond_106,
    (
        lit(31, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_108,
    (
        lit(32, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_109,
    (
        sig(:div_busy, width: 1) |
        sig(:exe_div_exception, width: 1)
    )
  assign :cond_117,
    (
        lit(9, width: 5, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)[6..2]
    )
  assign :cond_120,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[40] &
        sig(:__VdfgRegularize_h7a35cd6a_0_71, width: 1)
    )
  assign :cond_121,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[40] &
        sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
    )
  assign :cond_122,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[40] &
        sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1)
    )
  assign :cond_123,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[35] &
        sig(:cond_9, width: 1)
    )
  assign :cond_124,
    (
        sig(:v8086_mode, width: 1) &
        (
            lit(3, width: 2, base: "h", signed: false) >
            sig(:iopl, width: 2)
        )
    )
  assign :cond_126,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[35] &
        sig(:cond_165, width: 1)
    )
  assign :cond_130,
    sig(:glob_param_1, width: 32)[2]
  assign :cond_131,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[35] &
        sig(:__VdfgRegularize_h7a35cd6a_0_71, width: 1)
    )
  assign :exe_trigger_ts_fault,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_187, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_188, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_176, width: 1) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_177, width: 1) |
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_178, width: 1) |
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_179, width: 1) |
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_180, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h7a35cd6a_0_181, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_182, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h7a35cd6a_0_183, width: 1) |
                                            sig(:__VdfgRegularize_h7a35cd6a_0_185, width: 1)
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_187,
    (
        sig(:cond_34, width: 1) &
        sig(:cond_35, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_188,
    (
        sig(:cond_74, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_81, width: 1) &
            sig(:cond_35, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_176,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[35] &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1) &
            sig(:cond_130, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_177,
    (
        sig(:cond_131, width: 1) &
        (
            sig(:glob_param_2, width: 32)[1] |
            (
                sig(:glob_descriptor, width: 64)[44] |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_62, width: 1) &
                    sig(:__VdfgRegularize_h7a35cd6a_0_63, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_178,
    (
        sig(:cond_213, width: 1) &
        (
            sig(:glob_param_5, width: 32)[0] |
            (
                (
                    sig(:glob_param_1, width: 32)[1..0] !=
                    sig(:glob_descriptor_2, width: 64)[46..45]
                ) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) |
                    (
                        (
                            sig(:glob_descriptor, width: 64)[46..45] !=
                            sig(:glob_descriptor_2, width: 64)[46..45]
                        ) |
                        (
                            sig(:glob_descriptor, width: 64)[43] |
                            sig(:__VdfgRegularize_h7a35cd6a_0_8, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_179,
    (
        sig(:cond_246, width: 1) &
        (
            sig(:glob_desc_limit, width: 32) <
            sig(:exe_new_tss_max, width: 32)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_180,
    (
        sig(:cond_246, width: 1) &
        (
            sig(:tr_limit, width: 32) <
            mux(
              sig(:__VdfgRegularize_h7a35cd6a_0_95, width: 1),
              lit(41, width: 32, base: "h", signed: false),
              lit(95, width: 32, base: "h", signed: false)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_181,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[102] &
        (
            sig(:cond_165, width: 1) &
            (
                sig(:glob_param_2, width: 32)[2] |
                (
                    (
                        lit(2, width: 3, base: "h", signed: false) ==
                        sig(:glob_param_2, width: 32)[2..0]
                    ) |
                    (
                        (
                            lit(0, width: 3, base: "h", signed: false) ==
                            sig(:glob_param_2, width: 32)[2..0]
                        ) &
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_21, width: 1) |
                            sig(:__VdfgRegularize_h7a35cd6a_0_14, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_182,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_241, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_96, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_64, width: 1) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_8, width: 1) |
                    (
                        sig(:glob_descriptor, width: 64)[47] &
                        (
                            (
                                sig(:glob_descriptor, width: 64)[46..45] !=
                                sig(:wr_task_rpl, width: 2)
                            ) |
                            sig(:__VdfgRegularize_h7a35cd6a_0_20, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_183,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_220, width: 1) &
        (
            (
                lit(2, width: 2, base: "h", signed: false) ==
                sig(:glob_param_2, width: 32)[1..0]
            ) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_97, width: 1) &
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) |
                    sig(:__VdfgRegularize_h7a35cd6a_0_11, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_185,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_219, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_96, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_242, width: 1)
        )
    )
  assign :cond_138,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[41] &
        sig(:cond_9, width: 1)
    )
  assign :cond_139,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[41] &
        sig(:cond_67, width: 1)
    )
  assign :cond_140,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[41] &
        sig(:cond_165, width: 1)
    )
  assign :cond_141,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[43] |
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[42]
    )
  assign :cond_142,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[44] &
        (
            lit(1, width: 2, base: "h", signed: false) ==
            sig(:exe_decoder, width: 40)[13..12]
        )
    )
  assign :cond_143,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[44] &
        (
            lit(1, width: 2, base: "h", signed: false) !=
            sig(:exe_decoder, width: 40)[13..12]
        )
    )
  assign :cond_144,
    (
        lit(45, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_145,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[46] &
        sig(:cond_67, width: 1)
    )
  assign :cond_146,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[46] &
        sig(:cond_188, width: 1)
    )
  assign :cond_147,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:exe_modregrm_reg, width: 3)
    )
  assign :cond_148,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:exe_modregrm_reg, width: 3)
    )
  assign :cond_149,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:exe_modregrm_reg, width: 3)
    )
  assign :cond_150,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[46] &
        sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1)
    )
  assign :cond_153,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[47] |
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[48]
    )
  assign :cond_154,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[49]
  assign :cond_155,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)[2..0]
    )
  assign :cond_158,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[51]
  assign :cond_162,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[53] &
        sig(:cond_9, width: 1)
    )
  assign :cond_164,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[53] &
        sig(:__VdfgRegularize_h7a35cd6a_0_86, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_86,
    (
        sig(:cond_165, width: 1) |
        sig(:cond_188, width: 1)
    )
  assign :cond_166,
    (
        lit(54, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_168,
    (
        lit(28, width: 6, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)[6..1]
    )
  assign :cond_170,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[58] &
        sig(:cond_67, width: 1)
    )
  assign :cond_172,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)[6..3]
    )
  assign :cond_174,
    (
        lit(59, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_175,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[60]
  assign :cond_176,
    (
        sig(:cond_3, width: 1) |
        (
            sig(:cond_51, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_80, width: 1)
        )
    )
  assign :cond_178,
    (
        lit(61, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_183,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[63] &
        sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1)
    )
  assign :cond_184,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[63] &
        sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
    )
  assign :cond_185,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[63] &
        sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1)
    )
  assign :cond_186,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[63] &
        sig(:__VdfgRegularize_h7a35cd6a_0_75, width: 1)
    )
  assign :cond_187,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[63] &
        (
            sig(:cond_188, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1)
        )
    )
  assign :cond_190,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[73] &
        sig(:cond_9, width: 1)
    )
  assign :cond_191,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[73] &
        sig(:cond_67, width: 1)
    )
  assign :cond_193,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[74]
  assign :cond_196,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[77] &
        sig(:__VdfgRegularize_h7a35cd6a_0_87, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_87,
    (
        sig(:cond_67, width: 1) |
        sig(:cond_9, width: 1)
    )
  assign :cond_197,
    (
        sig(:cond_67, width: 1) &
        sig(:cond_218, width: 1)
    )
  assign :cond_218,
    sig(:exe_mutex_current, width: 11)[2]
  assign :cond_200,
    (
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_88, width: 1) |
            (
                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[81] |
                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[82]
            )
        ) &
        sig(:cond_67, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_88,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[79] |
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[80]
    )
  assign :cond_201,
    (
        (
            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
            sig(:__VdfgRegularize_h7a35cd6a_0_79, width: 1)
        ) |
        (
            sig(:cond_206, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_79,
    (
        lit(11, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_206,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[87]
  assign :cond_204,
    (
        (
            sig(:cond_205, width: 1) &
            sig(:cond_165, width: 1)
        ) |
        (
            sig(:cond_206, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_76, width: 1)
        )
    )
  assign :cond_207,
    (
        (
            sig(:cond_205, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1)
        ) |
        (
            (
                sig(:cond_206, width: 1) &
                sig(:__VdfgRegularize_h7a35cd6a_0_78, width: 1)
            ) |
            (
                sig(:cond_209, width: 1) &
                sig(:__VdfgRegularize_h7a35cd6a_0_68, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_68,
    (
        lit(12, width: 4, base: "h", signed: false) ==
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_211,
    (
        (
            sig(:cond_205, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_71, width: 1)
        ) |
        (
            sig(:cond_209, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_77, width: 1)
        )
    )
  assign :cond_213,
    (
        (
            sig(:cond_205, width: 1) &
            sig(:__VdfgRegularize_h7a35cd6a_0_77, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
            sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
        )
    )
  assign :cond_217,
    (
        lit(84, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_219,
    (
        lit(85, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_220,
    (
        lit(86, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_221,
    (
        sig(:cond_10, width: 1) |
        sig(:cond_51, width: 1)
    )
  assign :cond_222,
    (
        sig(:cond_206, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_246, width: 1)
    )
  assign :cond_223,
    (
        sig(:cond_206, width: 1) &
        sig(:cond_67, width: 1)
    )
  assign :cond_225,
    (
        sig(:cond_206, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1)
    )
  assign :cond_226,
    (
        sig(:cond_206, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1)
    )
  assign :cond_227,
    (
        sig(:cond_206, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_71, width: 1)
    )
  assign :cond_232,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[88] &
        sig(:cond_67, width: 1)
    )
  assign :cond_236,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[89] &
        sig(:__VdfgRegularize_h7a35cd6a_0_87, width: 1)
    )
  assign :cond_239,
    (
        lit(90, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_240,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[94] &
        sig(:cond_9, width: 1)
    )
  assign :cond_241,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[95] |
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[96]
    )
  assign :cond_246,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        sig(:cond_67, width: 1)
    )
  assign :cond_249,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        sig(:cond_165, width: 1)
    )
  assign :cond_250,
    (
      ~(
          sig(:tlbcheck_done, width: 1) |
          sig(:tlbcheck_page_fault, width: 1)
      )
    )
  assign :cond_252,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        sig(:cond_188, width: 1)
    )
  assign :cond_253,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        sig(:__VdfgRegularize_h7a35cd6a_0_69, width: 1)
    )
  assign :cond_254,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1)
    )
  assign :cond_255,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        sig(:__VdfgRegularize_h7a35cd6a_0_72, width: 1)
    )
  assign :cond_256,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
    )
  assign :cond_259,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[100]
  assign :cond_260,
    (
        lit(7, width: 4, base: "h", signed: false) >=
        sig(:exe_cmdex, width: 4)
    )
  assign :cond_267,
    (
      ~sig(:v8086_mode, width: 1)
    )
  assign :cond_270,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[102] &
        (
            (
                lit(4, width: 4, base: "h", signed: false) <=
                sig(:exe_cmdex, width: 4)
            ) &
            sig(:cond_260, width: 1)
        )
    )
  assign :cond_272,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_97, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_243, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_97,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:glob_param_2, width: 32)[1..0]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_243,
    (
        (
          ~sig(:exe_trigger_ts_fault, width: 1)
        ) &
        sig(:__VdfgRegularize_h7a35cd6a_0_21, width: 1)
    )
  assign :cond_273,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[102] &
        sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
    )
  assign :cond_279,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[104]
  assign :cond_282,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[105]
  assign :cond_284,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_99, width: 1) |
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[107]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_99,
    (
        lit(108, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_285,
    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[109]
  assign :cond_286,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[110] &
        sig(:__VdfgRegularize_h7a35cd6a_0_80, width: 1)
    )
  assign :cond_294,
    sig(:dr7, width: 32)[13]
  assign :cond_295,
    (
        lit(111, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_296,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_100, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_101, width: 1) |
            (
                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[114] |
                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[115]
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_100,
    (
        lit(112, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_101,
    (
        lit(113, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :cond_297,
    (
        lit(58, width: 6, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)[6..1]
    )
  assign :exe_buffer_to_reg,
    mux(
      sig(:cond_0, width: 1),
      sig(:dst, width: 32),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_102, width: 1),
        sig(:src, width: 32),
        mux(
          sig(:cond_139, width: 1),
          sig(:src, width: 32),
          mux(
            (
                (
                  ~sig(:cond_10, width: 1)
                ) &
                sig(:cond_162, width: 1)
            ),
            sig(:exe_enter_offset, width: 32),
            mux(
              sig(:cond_191, width: 1),
              sig(:dst, width: 32),
              mux(
                (
                    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[97] &
                    sig(:cond_9, width: 1)
                ),
                sig(:src, width: 32),
                mux(
                  sig(:__VdfgRegularize_h7a35cd6a_0_103, width: 1),
                  sig(:src, width: 32),
                  mux(
                    sig(:__VdfgRegularize_h7a35cd6a_0_104, width: 1),
                    mux(
                      (
                          sig(:__VdfgRegularize_h7a35cd6a_0_78, width: 1) &
                          sig(:__VdfgRegularize_h7a35cd6a_0_1, width: 1)
                      ),
                      lit(0, width: 32, base: "h", signed: false),
                      sig(:src, width: 32)
                    ),
                    mux(
                      sig(:__VdfgRegularize_h7a35cd6a_0_105, width: 1),
                      sig(:src, width: 32),
                      sig(:exe_buffer, width: 32)
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_102,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[35] &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_84, width: 1) &
            sig(:exe_ready, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_103,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
        (
            (
                (
                    lit(12, width: 4, base: "h", signed: false) <=
                    sig(:exe_cmdex, width: 4)
                ) &
                (
                    lit(14, width: 4, base: "h", signed: false) >=
                    sig(:exe_cmdex, width: 4)
                )
            ) &
            sig(:exe_ready, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_104,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[101] &
        sig(:exe_ready, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_105,
    (
        sig(:cond_285, width: 1) &
        sig(:exe_ready, width: 1)
    )
  assign :tlbcheck_rw,
    (
        (
          ~sig(:cond_249, width: 1)
        ) &
        (
            (
              ~sig(:cond_252, width: 1)
            ) &
            sig(:__VdfgRegularize_h7a35cd6a_0_106, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_106,
    (
        sig(:cond_253, width: 1) |
        (
            sig(:cond_254, width: 1) |
            (
                sig(:cond_255, width: 1) |
                sig(:cond_256, width: 1)
            )
        )
    )
  assign :wbinvddata_do,
    (
        (
          ~sig(:e_wbinvd_data_done, width: 1)
        ) &
        sig(:cond_170, width: 1)
    )
  assign :exe_trigger_ss_fault,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_107, width: 1) |
        sig(:__VdfgRegularize_h7a35cd6a_0_108, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_107,
    (
        sig(:cond_213, width: 1) &
        (
            (
              ~sig(:glob_param_5, width: 32)[0]
            ) &
            sig(:__VdfgRegularize_h7a35cd6a_0_243, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_108,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_241, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_97, width: 1) &
            (
                sig(:glob_descriptor, width: 64)[44] &
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_21, width: 1) &
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_6, width: 1) &
                        sig(:glob_descriptor, width: 64)[41]
                    )
                )
            )
        )
    )
  assign :offset_ret,
    (
        (
            sig(:cond_65, width: 1) &
            sig(:cond_67, width: 1)
        ) |
        mux(
          sig(:cond_183, width: 1),
          sig(:__VdfgRegularize_h7a35cd6a_0_109, width: 1),
          (
              sig(:__VdfgRegularize_h7a35cd6a_0_109, width: 1) &
              sig(:offset_ret_far_se, width: 1)
          )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_109,
    (
      ~sig(:exe_decoder, width: 40)[0]
    )
  assign :offset_ret_far_se,
    (
        sig(:cond_187, width: 1) &
        sig(:cond_188, width: 1)
    )
  assign :exe_buffer_shift_word,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_104, width: 1) &
        (
            lit(8, width: 4, base: "h", signed: false) <
            sig(:exe_cmdex, width: 4)
        )
    )
  assign :exe_buffer_shift,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_102, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_103, width: 1) |
            mux(
              sig(:__VdfgRegularize_h7a35cd6a_0_104, width: 1),
              (
                  lit(8, width: 4, base: "h", signed: false) >=
                  sig(:exe_cmdex, width: 4)
              ),
              sig(:__VdfgRegularize_h7a35cd6a_0_105, width: 1)
            )
        )
    )
  assign :exe_eip_from_glob_param_2,
    (
        sig(:cond_13, width: 1) |
        (
            (
                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
                sig(:__VdfgRegularize_h7a35cd6a_0_75, width: 1)
            ) |
            (
                (
                    sig(:cond_205, width: 1) &
                    sig(:cond_67, width: 1)
                ) |
                (
                    (
                        sig(:cond_205, width: 1) &
                        sig(:__VdfgRegularize_h7a35cd6a_0_79, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[5] &
                            sig(:__VdfgRegularize_h7a35cd6a_0_71, width: 1)
                        ) |
                        (
                            sig(:cond_65, width: 1) |
                            (
                                (
                                    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
                                    sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1)
                                ) |
                                (
                                    (
                                        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[30] &
                                        sig(:__VdfgRegularize_h7a35cd6a_0_71, width: 1)
                                    ) |
                                    (
                                        (
                                            sig(:cond_209, width: 1) &
                                            sig(:__VdfgRegularize_h7a35cd6a_0_72, width: 1)
                                        ) |
                                        (
                                            (
                                                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[40] &
                                                sig(:cond_165, width: 1)
                                            ) |
                                            (
                                                sig(:cond_122, width: 1) |
                                                (
                                                    (
                                                        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[35] &
                                                        sig(:cond_188, width: 1)
                                                    ) |
                                                    (
                                                        sig(:cond_186, width: 1) |
                                                        (
                                                            sig(:cond_187, width: 1) |
                                                            (
                                                                sig(:cond_225, width: 1) |
                                                                (
                                                                    (
                                                                        sig(:cond_206, width: 1) &
                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_73, width: 1)
                                                                    ) |
                                                                    (
                                                                        (
                                                                            sig(:cond_206, width: 1) &
                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_68, width: 1)
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[88] &
                                                                                sig(:cond_188, width: 1)
                                                                            ) |
                                                                            sig(:exe_task_switch_finished, width: 1)
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :exe_task_switch_finished,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[102] &
        sig(:__VdfgRegularize_h7a35cd6a_0_75, width: 1)
    )
  assign :offset_esp,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] &
        sig(:__VdfgRegularize_h7a35cd6a_0_68, width: 1)
    )
  assign :exe_trigger_np_fault,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_110, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_111, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_112, width: 1) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_113, width: 1) |
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_114, width: 1) |
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_115, width: 1) |
                            (
                                (
                                    sig(:cond_270, width: 1) |
                                    sig(:cond_273, width: 1)
                                ) &
                                (
                                    sig(:cond_267, width: 1) &
                                    sig(:cond_272, width: 1)
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_110,
    (
        sig(:cond_93, width: 1) &
        sig(:cond_95, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_111,
    (
        sig(:cond_131, width: 1) &
        (
            (
              ~sig(:glob_param_2, width: 32)[1]
            ) &
            sig(:__VdfgRegularize_h7a35cd6a_0_243, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_112,
    (
        sig(:cond_201, width: 1) &
        (
            sig(:cond_95, width: 1) &
            (
                sig(:glob_descriptor, width: 64)[44] |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_89, width: 1) |
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_90, width: 1) |
                        (
                            (
                                lit(4, width: 4, base: "h", signed: false) ==
                                sig(:glob_descriptor, width: 64)[43..40]
                            ) |
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_94, width: 1) |
                                (
                                    lit(5, width: 4, base: "h", signed: false) ==
                                    sig(:glob_descriptor, width: 64)[43..40]
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_113,
    (
        sig(:cond_207, width: 1) &
        sig(:cond_95, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_114,
    (
        sig(:cond_211, width: 1) &
        sig(:cond_95, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_115,
    (
        sig(:cond_232, width: 1) &
        sig(:cond_95, width: 1)
    )
  assign :offset_iret,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[40] &
        sig(:cond_67, width: 1)
    )
  assign :exe_eip_from_glob_param_2_16bit,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[40] &
        sig(:__VdfgRegularize_h7a35cd6a_0_75, width: 1)
    )
  assign :exe_glob_descriptor_value,
    mux(
      sig(:cond_24, width: 1),
      sig(:ss_cache, width: 64),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_232, width: 1),
        sig(:glob_descriptor_2, width: 64),
        mux(
          sig(:__VdfgRegularize_h7a35cd6a_0_163, width: 1),
          sig(:glob_descriptor_2, width: 64),
          mux(
            sig(:__VdfgRegularize_h7a35cd6a_0_164, width: 1),
            sig(:glob_descriptor_2, width: 64),
            mux(
              sig(:__VdfgRegularize_h7a35cd6a_0_231, width: 1),
              sig(:glob_descriptor_2, width: 64),
              mux(
                sig(:cond_121, width: 1),
                sig(:glob_descriptor_2, width: 64),
                mux(
                  sig(:__VdfgRegularize_h7a35cd6a_0_230, width: 1),
                  sig(:glob_descriptor_2, width: 64),
                  mux(
                    sig(:cond_185, width: 1),
                    sig(:glob_descriptor_2, width: 64),
                    lit(0, width: 64, base: "h", signed: false)
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_232,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_82, width: 1) &
        sig(:cond_26, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_163,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[5] &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_70, width: 1) &
            sig(:exe_ready, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_164,
    (
        sig(:cond_79, width: 1) &
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_82, width: 1) &
            sig(:exe_ready, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_231,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_165, width: 1) &
        sig(:cond_120, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_230,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_165, width: 1) &
        sig(:cond_184, width: 1)
    )
  assign :offset_task,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[102] &
        sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1)
    )
  assign :exe_glob_param_2_set,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_166, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_229, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_168, width: 1) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_228, width: 1) |
                    (
                        sig(:cond_28, width: 1) |
                        (
                            sig(:cond_73, width: 1) |
                            (
                                sig(:cond_200, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h7a35cd6a_0_169, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_227, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h7a35cd6a_0_170, width: 1) |
                                            (
                                                sig(:__VdfgRegularize_h7a35cd6a_0_226, width: 1) |
                                                sig(:exe_task_switch_finished, width: 1)
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_166,
    (
        sig(:cond_8, width: 1) &
        sig(:exe_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_229,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_167, width: 1) &
        sig(:cond_8, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_168,
    (
        sig(:cond_12, width: 1) &
        sig(:exe_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_228,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_167, width: 1) &
        sig(:cond_12, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_169,
    (
        sig(:cond_222, width: 1) &
        sig(:exe_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_227,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_167, width: 1) &
        sig(:cond_222, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_170,
    (
        sig(:cond_223, width: 1) &
        sig(:exe_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_226,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_167, width: 1) &
        sig(:cond_223, width: 1)
    )
  assign :offset_pop,
    (
        (
            sig(:cond_65, width: 1) &
            sig(:cond_9, width: 1)
        ) |
        (
            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[34] |
            (
                sig(:cond_123, width: 1) |
                (
                    (
                        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[35] &
                        sig(:cond_67, width: 1)
                    ) |
                    (
                        sig(:cond_126, width: 1) |
                        (
                            sig(:cond_138, width: 1) |
                            (
                                sig(:cond_139, width: 1) |
                                (
                                    sig(:cond_140, width: 1) |
                                    (
                                        (
                                            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[63] &
                                            sig(:cond_67, width: 1)
                                        ) |
                                        mux(
                                          sig(:cond_183, width: 1),
                                          sig(:exe_decoder, width: 40)[0],
                                          mux(
                                            sig(:offset_ret_far_se, width: 1),
                                            sig(:exe_decoder, width: 40)[0],
                                            (
                                                sig(:cond_240, width: 1) |
                                                sig(:cond_285, width: 1)
                                            )
                                          )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :exe_result2,
    mux(
      sig(:cond_106, width: 1),
      sig(:mult_result, width: 66)[63..32],
      mux(
        sig(:cond_108, width: 1),
        sig(:div_result_remainder, width: 32),
        mux(
          sig(:cond_141, width: 1),
          sig(:div_result_remainder, width: 32),
          mux(
            sig(:cond_145, width: 1),
            sig(:src, width: 32),
            mux(
              sig(:cond_150, width: 1),
              sig(:src, width: 32),
              mux(
                sig(:cond_153, width: 1),
                sig(:src, width: 32),
                mux(
                  sig(:exe_cmpxchg_switch, width: 1),
                  sig(:dst, width: 32),
                  mux(
                    sig(:cond_166, width: 1),
                    sig(:mult_result, width: 66)[63..32],
                    mux(
                      sig(:cond_174, width: 1),
                      sig(:mult_result, width: 66)[63..32],
                      mux(
                        (
                            lit(72, width: 7, base: "h", signed: false) ==
                            sig(:exe_cmd, width: 7)
                        ),
                        sig(:src, width: 32),
                        mux(
                          sig(:cond_190, width: 1),
                          sig(:dst, width: 32),
                          mux(
                            (
                                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[77] &
                                sig(:cond_165, width: 1)
                            ),
                            sig(:src, width: 32),
                            mux(
                              sig(:cond_196, width: 1),
                              sig(:src, width: 32),
                              mux(
                                sig(:cond_239, width: 1),
                                sig(:dst, width: 32),
                                mux(
                                  sig(:cond_240, width: 1),
                                  sig(:src, width: 32),
                                  mux(
                                    (
                                        sig(:cond_259, width: 1) &
                                        sig(:cond_260, width: 1)
                                    ),
                                    sig(:src, width: 32),
                                    mux(
                                      (
                                          sig(:cond_259, width: 1) &
                                          (
                                              lit(7, width: 4, base: "h", signed: false) <
                                              sig(:exe_cmdex, width: 4)
                                          )
                                      ),
                                      sig(:__VdfgRegularize_h7a35cd6a_0_225, width: 32),
                                      mux(
                                        (
                                            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[102] &
                                            sig(:cond_9, width: 1)
                                        ),
                                        sig(:src, width: 32),
                                        mux(
                                          (
                                              sig(:cond_286, width: 1) &
                                              sig(:cond_67, width: 1)
                                          ),
                                          sig(:src, width: 32),
                                          mux(
                                            sig(:cond_295, width: 1),
                                            sig(:dst, width: 32),
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
  assign :__VdfgRegularize_h7a35cd6a_0_225,
    lit(0, width: 16, base: "d", signed: false).concat(
      (
          (
              mux(
                (
                    lit(0, width: 3, base: "h", signed: false) ==
                    sig(:exe_cmdex, width: 4)[2..0]
                ),
                sig(:es, width: 16),
                mux(
                  (
                      lit(1, width: 3, base: "h", signed: false) ==
                      sig(:exe_cmdex, width: 4)[2..0]
                  ),
                  sig(:cs, width: 16),
                  mux(
                    (
                        lit(2, width: 3, base: "h", signed: false) ==
                        sig(:exe_cmdex, width: 4)[2..0]
                    ),
                    sig(:ss, width: 16),
                    mux(
                      (
                          lit(3, width: 3, base: "h", signed: false) ==
                          sig(:exe_cmdex, width: 4)[2..0]
                      ),
                      sig(:ds, width: 16),
                      mux(
                        sig(:cond_155, width: 1),
                        sig(:fs, width: 16),
                        case_select(
                          sig(:exe_cmdex, width: 4)[2..0],
                          cases: {
                            5 => sig(:gs, width: 16),
                            6 => sig(:ldtr, width: 16)
                          },
                          default: sig(:tr, width: 16)
                        )
                      )
                    )
                  )
                )
              ) >>
              lit(0, width: nil, base: "d", signed: false)
          ) &
          (
              (
                  lit(1, width: 32, base: "d") <<
                  (
                        (
                          lit(15, width: nil, base: "d", signed: false)
                        ) -
                        (
                          lit(0, width: nil, base: "d", signed: false)
                        ) +
                      lit(1, width: 32, base: "d")
                  )
              ) -
              lit(1, width: 32, base: "d")
          )
      )
    )
  assign :offset_new_stack_continue,
    (
        sig(:cond_37, width: 1) |
        (
            sig(:cond_39, width: 1) |
            (
                sig(:cond_40, width: 1) |
                (
                    sig(:cond_41, width: 1) |
                    (
                        sig(:cond_101, width: 1) |
                        (
                            sig(:cond_102, width: 1) |
                            (
                                sig(:cond_103, width: 1) |
                                (
                                    sig(:cond_104, width: 1) |
                                    sig(:cond_105, width: 1)
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :tlbflushsingle_do,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[10] &
        sig(:cond_67, width: 1)
    )
  assign :tlbflushsingle_address,
    mux(
      sig(:tlbflushsingle_do, width: 1),
      sig(:exe_linear, width: 32),
      lit(0, width: 32, base: "h", signed: false)
    )
  assign :exe_result_signals,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_240, width: 1),
      sig(:exe_jecxz_condition, width: 1),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_239, width: 1),
        sig(:exe_condition, width: 1),
        mux(
          sig(:cond_68, width: 1),
          (
              sig(:dst, width: 32)[1..0] <
              sig(:src, width: 32)[1..0]
          ),
          mux(
            sig(:cond_117, width: 1),
            sig(:e_bit_selected, width: 1),
            mux(
              sig(:cond_142, width: 1),
              sig(:__VdfgRegularize_h7a35cd6a_0_171, width: 5),
              mux(
                sig(:cond_143, width: 1),
                sig(:__VdfgRegularize_h7a35cd6a_0_171, width: 5),
                mux(
                  sig(:exe_cmpxchg_switch, width: 1),
                  sig(:e_cmpxchg_eq, width: 1),
                  mux(
                    sig(:cond_168, width: 1),
                    sig(:__VdfgRegularize_h7a35cd6a_0_171, width: 5),
                    mux(
                      sig(:__VdfgRegularize_h7a35cd6a_0_237, width: 1),
                      sig(:exe_cmd_loop_condition, width: 1),
                      mux(
                        sig(:cond_296, width: 1),
                        lit(0, width: 3, base: "d", signed: false).concat(
                          sig(:exe_bcd_condition_af, width: 1).concat(
                            (
                                sig(:e_bcd_condition_cf, width: 1) |
                                (
                                    sig(:exe_bcd_condition_af, width: 1) &
                                    mux(
                                      (
                                          sig(:cflag, width: 1) |
                                          sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[114]
                                      ),
                                      (
                                          lit(249, width: 8, base: "h", signed: false) <
                                          sig(:dst, width: 32)[7..0]
                                      ),
                                      (
                                          lit(6, width: 8, base: "h", signed: false) >
                                          sig(:dst, width: 32)[7..0]
                                      )
                                    )
                                )
                            )
                          )
                        ),
                        mux(
                          sig(:cond_297, width: 1),
                          mux(
                            sig(:exe_operand_16bit, width: 1),
                            (
                                lit(0, width: 16, base: "h", signed: false) ==
                                sig(:src, width: 32)[15..0]
                            ),
                            (
                                lit(0, width: 32, base: "h", signed: false) ==
                                sig(:src, width: 32)
                            )
                          ),
                          lit(0, width: 5, base: "h", signed: false)
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_240,
    (
        (
          ~sig(:cond_3, width: 1)
        ) &
        sig(:cond_2, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_239,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_123, width: 1) &
        sig(:cond_50, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_171,
    sig(:e_shift_no_write, width: 1).concat(
      sig(:e_shift_oszapc_update, width: 1).concat(
        sig(:e_shift_cf_of_update, width: 1).concat(
          sig(:e_shift_oflag, width: 1).concat(
            sig(:e_shift_cflag, width: 1)
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_237,
    (
        (
          ~sig(:cond_176, width: 1)
        ) &
        sig(:cond_175, width: 1)
    )
  assign :exe_result_push,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_172, width: 1),
      sig(:exe_eip, width: 32),
      mux(
        sig(:cond_12, width: 1),
        sig(:exe_eip, width: 32),
        mux(
          sig(:cond_17, width: 1),
          sig(:__VdfgRegularize_h7a35cd6a_0_224, width: 32),
          mux(
            sig(:cond_19, width: 1),
            sig(:exe_eip, width: 32),
            mux(
              sig(:cond_24, width: 1),
              sig(:__VdfgRegularize_h7a35cd6a_0_224, width: 32),
              mux(
                sig(:cond_25, width: 1),
                sig(:exe_eip, width: 32),
                mux(
                  sig(:cond_29, width: 1),
                  sig(:__VdfgRegularize_h7a35cd6a_0_224, width: 32),
                  mux(
                    sig(:cond_30, width: 1),
                    sig(:exe_eip, width: 32),
                    mux(
                      (
                          sig(:cond_37, width: 1) &
                          sig(:cond_38, width: 1)
                      ),
                      sig(:esp, width: 32),
                      mux(
                        (
                            (
                              ~sig(:cond_38, width: 1)
                            ) &
                            sig(:cond_37, width: 1)
                        ),
                        lit(0, width: 16, base: "d", signed: false).concat(
                          sig(:esp, width: 32)[15..0]
                        ),
                        mux(
                          sig(:cond_39, width: 1),
                          sig(:glob_param_5, width: 32),
                          mux(
                            sig(:cond_40, width: 1),
                            sig(:__VdfgRegularize_h7a35cd6a_0_224, width: 32),
                            mux(
                              (
                                  sig(:cond_41, width: 1) &
                                  sig(:cond_42, width: 1)
                              ),
                              sig(:exe_eip, width: 32),
                              mux(
                                (
                                    (
                                      ~sig(:cond_42, width: 1)
                                    ) &
                                    sig(:cond_41, width: 1)
                                ),
                                lit(0, width: 16, base: "d", signed: false).concat(
                                  sig(:exe_eip, width: 32)[15..0]
                                ),
                                mux(
                                  sig(:cond_47, width: 1),
                                  sig(:__VdfgRegularize_h7a35cd6a_0_225, width: 32),
                                  mux(
                                    sig(:offset_int_real, width: 1),
                                    sig(:exe_push_eflags, width: 32),
                                    mux(
                                      sig(:cond_87, width: 1),
                                      sig(:__VdfgRegularize_h7a35cd6a_0_224, width: 32),
                                      mux(
                                        sig(:cond_88, width: 1),
                                        sig(:exe_eip, width: 32),
                                        mux(
                                          sig(:cond_96, width: 1),
                                          sig(:exe_push_eflags, width: 32),
                                          mux(
                                            sig(:cond_98, width: 1),
                                            sig(:__VdfgRegularize_h7a35cd6a_0_224, width: 32),
                                            mux(
                                              sig(:cond_99, width: 1),
                                              sig(:exe_eip, width: 32),
                                              mux(
                                                sig(:cond_100, width: 1),
                                                sig(:__VdfgRegularize_h7a35cd6a_0_223, width: 32),
                                                mux(
                                                  sig(:cond_101, width: 1),
                                                  mux(
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_75, width: 1),
                                                    lit(0, width: 16, base: "d", signed: false).concat(
                                                      sig(:gs, width: 16)
                                                    ),
                                                    mux(
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_79, width: 1),
                                                      lit(0, width: 16, base: "d", signed: false).concat(
                                                        sig(:fs, width: 16)
                                                      ),
                                                      mux(
                                                        sig(:__VdfgRegularize_h7a35cd6a_0_68, width: 1),
                                                        lit(0, width: 16, base: "d", signed: false).concat(
                                                          sig(:ds, width: 16)
                                                        ),
                                                        mux(
                                                          sig(:__VdfgRegularize_h7a35cd6a_0_76, width: 1),
                                                          lit(0, width: 16, base: "d", signed: false).concat(
                                                            sig(:es, width: 16)
                                                          ),
                                                          mux(
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_77, width: 1),
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_222, width: 32),
                                                            sig(:esp, width: 32)
                                                          )
                                                        )
                                                      )
                                                    )
                                                  ),
                                                  mux(
                                                    sig(:cond_102, width: 1),
                                                    sig(:exe_push_eflags, width: 32),
                                                    mux(
                                                      sig(:cond_103, width: 1),
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_224, width: 32),
                                                      mux(
                                                        sig(:cond_104, width: 1),
                                                        sig(:exe_eip, width: 32),
                                                        mux(
                                                          sig(:cond_105, width: 1),
                                                          sig(:__VdfgRegularize_h7a35cd6a_0_223, width: 32),
                                                          mux(
                                                            (
                                                                sig(:cond_154, width: 1) &
                                                                sig(:cond_155, width: 1)
                                                            ),
                                                            sig(:wr_esp_prev, width: 32),
                                                            mux(
                                                              (
                                                                  (
                                                                    ~sig(:cond_155, width: 1)
                                                                  ) &
                                                                  sig(:cond_154, width: 1)
                                                              ),
                                                              sig(:src, width: 32),
                                                              mux(
                                                                sig(:cond_162, width: 1),
                                                                sig(:ebp, width: 32),
                                                                mux(
                                                                  (
                                                                      sig(:cond_164, width: 1) &
                                                                      sig(:cond_165, width: 1)
                                                                  ),
                                                                  sig(:exe_buffer, width: 32),
                                                                  mux(
                                                                    (
                                                                        (
                                                                          ~sig(:cond_165, width: 1)
                                                                        ) &
                                                                        sig(:cond_164, width: 1)
                                                                    ),
                                                                    sig(:src, width: 32),
                                                                    mux(
                                                                      sig(:offset_leave, width: 1),
                                                                      sig(:src, width: 32),
                                                                      mux(
                                                                        (
                                                                            sig(:cond_193, width: 1) &
                                                                            sig(:cond_67, width: 1)
                                                                        ),
                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_173, width: 32),
                                                                        mux(
                                                                          (
                                                                              (
                                                                                ~sig(:cond_67, width: 1)
                                                                              ) &
                                                                              sig(:cond_193, width: 1)
                                                                          ),
                                                                          sig(:src, width: 32),
                                                                          mux(
                                                                            sig(:offset_new_stack_minus, width: 1),
                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_222, width: 32),
                                                                            mux(
                                                                              (
                                                                                  lit(83, width: 7, base: "h", signed: false) ==
                                                                                  sig(:exe_cmd, width: 7)
                                                                              ),
                                                                              sig(:src, width: 32),
                                                                              mux(
                                                                                sig(:cond_217, width: 1),
                                                                                sig(:src, width: 32),
                                                                                mux(
                                                                                  sig(:cond_219, width: 1),
                                                                                  sig(:src, width: 32),
                                                                                  mux(
                                                                                    sig(:cond_220, width: 1),
                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_253, width: 11).concat(
                                                                                      lit(0, width: 2, base: "d", signed: false).concat(
                                                                                        sig(:acflag, width: 1).concat(
                                                                                          lit(0, width: 3, base: "d", signed: false).concat(
                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_0, width: 15)
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    ),
                                                                                    mux(
                                                                                      sig(:cond_236, width: 1),
                                                                                      sig(:src, width: 32),
                                                                                      mux(
                                                                                        (
                                                                                            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[89] &
                                                                                            sig(:cond_165, width: 1)
                                                                                        ),
                                                                                        sig(:src, width: 32),
                                                                                        mux(
                                                                                          (
                                                                                              sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[99] &
                                                                                              sig(:__VdfgRegularize_h7a35cd6a_0_75, width: 1)
                                                                                          ),
                                                                                          sig(:exe_push_eflags, width: 32),
                                                                                          mux(
                                                                                            sig(:offset_task, width: 1),
                                                                                            lit(0, width: 16, base: "d", signed: false).concat(
                                                                                              sig(:glob_param_3, width: 32)[15..0]
                                                                                            ),
                                                                                            mux(
                                                                                              sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[106],
                                                                                              sig(:src, width: 32),
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
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_172,
    (
        sig(:cond_8, width: 1) &
        sig(:cond_9, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_224,
    lit(0, width: 16, base: "d", signed: false).concat(
      sig(:cs, width: 16)
    )
  assign :offset_int_real,
    (
        sig(:cond_209, width: 1) &
        sig(:cond_165, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_223,
    lit(0, width: 16, base: "d", signed: false).concat(
      sig(:exc_error_code, width: 16)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_222,
    lit(0, width: 16, base: "d", signed: false).concat(
      sig(:ss, width: 16)
    )
  assign :offset_leave,
    (
        lit(55, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_173,
    sig(:src, width: 32)[7].replicate(
      lit(24, width: 32, base: "h", signed: true)
    ).concat(
      sig(:src, width: 32)[7..0]
    )
  assign :offset_new_stack_minus,
    (
        sig(:cond_213, width: 1) &
        sig(:cond_205, width: 1)
    )
  assign :exe_error_code,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_131, width: 1),
      sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_136, width: 1),
        sig(:__VdfgRegularize_h7a35cd6a_0_175, width: 16),
        mux(
          sig(:__VdfgRegularize_h7a35cd6a_0_137, width: 1),
          sig(:__VdfgRegularize_h7a35cd6a_0_175, width: 16),
          mux(
            sig(:__VdfgRegularize_h7a35cd6a_0_110, width: 1),
            sig(:__VdfgRegularize_h7a35cd6a_0_175, width: 16),
            mux(
              sig(:__VdfgRegularize_h7a35cd6a_0_138, width: 1),
              mux(
                sig(:exe_int_2_int_trap_same_exception, width: 1),
                sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                lit(0, width: 16, base: "h", signed: false)
              ),
              mux(
                sig(:__VdfgRegularize_h7a35cd6a_0_238, width: 1),
                sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                mux(
                  sig(:__VdfgRegularize_h7a35cd6a_0_221, width: 1),
                  sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                  mux(
                    sig(:__VdfgRegularize_h7a35cd6a_0_176, width: 1),
                    sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                    mux(
                      sig(:__VdfgRegularize_h7a35cd6a_0_177, width: 1),
                      sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                      mux(
                        sig(:__VdfgRegularize_h7a35cd6a_0_111, width: 1),
                        sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                        mux(
                          sig(:__VdfgRegularize_h7a35cd6a_0_143, width: 1),
                          sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                          mux(
                            sig(:__VdfgRegularize_h7a35cd6a_0_154, width: 1),
                            sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                            mux(
                              sig(:__VdfgRegularize_h7a35cd6a_0_112, width: 1),
                              sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                              mux(
                                sig(:__VdfgRegularize_h7a35cd6a_0_155, width: 1),
                                sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                mux(
                                  sig(:__VdfgRegularize_h7a35cd6a_0_113, width: 1),
                                  sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                  mux(
                                    sig(:__VdfgRegularize_h7a35cd6a_0_156, width: 1),
                                    sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                    mux(
                                      sig(:__VdfgRegularize_h7a35cd6a_0_114, width: 1),
                                      sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                      mux(
                                        sig(:__VdfgRegularize_h7a35cd6a_0_178, width: 1),
                                        sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                        mux(
                                          sig(:__VdfgRegularize_h7a35cd6a_0_107, width: 1),
                                          sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                          mux(
                                            sig(:__VdfgRegularize_h7a35cd6a_0_160, width: 1),
                                            sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                            mux(
                                              sig(:__VdfgRegularize_h7a35cd6a_0_115, width: 1),
                                              sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                              mux(
                                                sig(:__VdfgRegularize_h7a35cd6a_0_179, width: 1),
                                                sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                                mux(
                                                  sig(:__VdfgRegularize_h7a35cd6a_0_180, width: 1),
                                                  sig(:tr, width: 16)[15..2].concat(
                                                    lit(0, width: 2, base: "h", signed: false)
                                                  ),
                                                  mux(
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_181, width: 1),
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                                    mux(
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_182, width: 1),
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                                      mux(
                                                        sig(:__VdfgRegularize_h7a35cd6a_0_108, width: 1),
                                                        sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                                        mux(
                                                          sig(:__VdfgRegularize_h7a35cd6a_0_183, width: 1),
                                                          sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                                          mux(
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_184, width: 1),
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                                            mux(
                                                              sig(:__VdfgRegularize_h7a35cd6a_0_185, width: 1),
                                                              sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
                                                              mux(
                                                                sig(:__VdfgRegularize_h7a35cd6a_0_186, width: 1),
                                                                sig(:__VdfgRegularize_h7a35cd6a_0_174, width: 16),
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
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_174,
    sig(:glob_param_1, width: 32)[15..2].concat(
      lit(0, width: 2, base: "h", signed: false)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_175,
    sig(:__VdfgRegularize_h7a35cd6a_0_245, width: 13).concat(
      lit(2, width: 3, base: "h", signed: false)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_221,
    (
        (
          ~(
              sig(:protected_mode, width: 1) &
              sig(:__VdfgRegularize_h7a35cd6a_0_85, width: 1)
          )
        ) &
        sig(:cond_113, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_184,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_220, width: 1) &
        sig(:cond_272, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_186,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_219, width: 1) &
        sig(:cond_272, width: 1)
    )
  assign :exe_waiting,
    (
        (
            sig(:cond_2, width: 1) &
            sig(:cond_3, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_116, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_117, width: 1) |
                (
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_172, width: 1) &
                        sig(:cond_10, width: 1)
                    ) |
                    (
                        (
                            sig(:cond_12, width: 1) &
                            sig(:cond_10, width: 1)
                        ) |
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_118, width: 1) |
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_119, width: 1) |
                                (
                                    (
                                        sig(:cond_19, width: 1) &
                                        sig(:cond_20, width: 1)
                                    ) |
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_120, width: 1) |
                                        (
                                            (
                                                sig(:cond_26, width: 1) &
                                                sig(:cond_20, width: 1)
                                            ) |
                                            (
                                                sig(:__VdfgRegularize_h7a35cd6a_0_121, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_187, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h7a35cd6a_0_122, width: 1) |
                                                        (
                                                            (
                                                                sig(:cond_47, width: 1) &
                                                                sig(:cond_10, width: 1)
                                                            ) |
                                                            (
                                                                (
                                                                    sig(:cond_50, width: 1) &
                                                                    sig(:cond_51, width: 1)
                                                                ) |
                                                                (
                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_124, width: 1) |
                                                                    (
                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_125, width: 1) |
                                                                        (
                                                                            (
                                                                                (
                                                                                  ~(
                                                                                      sig(:e_invd_code_done, width: 1) &
                                                                                      sig(:e_invd_data_done, width: 1)
                                                                                  )
                                                                                ) &
                                                                                sig(:cond_55, width: 1)
                                                                            ) |
                                                                            (
                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_126, width: 1) |
                                                                                (
                                                                                    (
                                                                                        (
                                                                                          ~sig(:tlbflushsingle_done, width: 1)
                                                                                        ) &
                                                                                        sig(:tlbflushsingle_do, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_127, width: 1) |
                                                                                        (
                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_128, width: 1) |
                                                                                            (
                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_129, width: 1) |
                                                                                                (
                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_130, width: 1) |
                                                                                                    (
                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_131, width: 1) |
                                                                                                        (
                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_188, width: 1) |
                                                                                                            (
                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_132, width: 1) |
                                                                                                                (
                                                                                                                    (
                                                                                                                        sig(:cond_79, width: 1) &
                                                                                                                        sig(:cond_20, width: 1)
                                                                                                                    ) |
                                                                                                                    (
                                                                                                                        (
                                                                                                                            sig(:cond_209, width: 1) &
                                                                                                                            (
                                                                                                                                sig(:cond_9, width: 1) &
                                                                                                                                sig(:cond_20, width: 1)
                                                                                                                            )
                                                                                                                        ) |
                                                                                                                        (
                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_133, width: 1) |
                                                                                                                            (
                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_134, width: 1) |
                                                                                                                                (
                                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_135, width: 1) |
                                                                                                                                    (
                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_136, width: 1) |
                                                                                                                                        (
                                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_137, width: 1) |
                                                                                                                                            (
                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_110, width: 1) |
                                                                                                                                                (
                                                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_138, width: 1) |
                                                                                                                                                    (
                                                                                                                                                        (
                                                                                                                                                            sig(:cond_106, width: 1) &
                                                                                                                                                            sig(:mult_busy, width: 1)
                                                                                                                                                        ) |
                                                                                                                                                        (
                                                                                                                                                            (
                                                                                                                                                                sig(:cond_108, width: 1) &
                                                                                                                                                                sig(:cond_109, width: 1)
                                                                                                                                                            ) |
                                                                                                                                                            (
                                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_238, width: 1) |
                                                                                                                                                                (
                                                                                                                                                                    (
                                                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_221, width: 1) &
                                                                                                                                                                        (
                                                                                                                                                                            sig(:exe_load_seg_gp_fault, width: 1) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:exe_load_seg_ss_fault, width: 1) |
                                                                                                                                                                                sig(:exe_load_seg_np_fault, width: 1)
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    ) |
                                                                                                                                                                    (
                                                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_139, width: 1) |
                                                                                                                                                                        (
                                                                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_140, width: 1) |
                                                                                                                                                                            (
                                                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_141, width: 1) |
                                                                                                                                                                                (
                                                                                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_142, width: 1) |
                                                                                                                                                                                    (
                                                                                                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_176, width: 1) |
                                                                                                                                                                                        (
                                                                                                                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_177, width: 1) |
                                                                                                                                                                                            (
                                                                                                                                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_111, width: 1) |
                                                                                                                                                                                                (
                                                                                                                                                                                                    sig(
                                                                                                                                                                                                      :__VdfgRegularize_h7a35cd6a_0_143,
                                                                                                                                                                                                      width: 1
                                                                                                                                                                                                    ) |
                                                                                                                                                                                                    (
                                                                                                                                                                                                      (sig(:cond_141, width: 1) & sig(:cond_109, width: 1)) |
                                                                                                                                                                                                      ((sig(:cond_142, width: 1) & sig(:cond_51, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_144, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_145, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_146, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_147, width: 1) | ((sig(:cond_154, width: 1) & sig(:cond_10, width: 1)) | (sig(:exe_trigger_nm_fault, width: 1) | ((sig(:cond_158, width: 1) & sig(:cond_51, width: 1)) | ((sig(:exe_cmpxchg_switch, width: 1) & sig(:exe_mutex_current, width: 11)[0]) | ((sig(:cond_162, width: 1) & sig(:cond_10, width: 1)) | ((sig(:cond_164, width: 1) & sig(:cond_10, width: 1)) | ((sig(:cond_166, width: 1) & sig(:mult_busy, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_148, width: 1) | (((~(sig(:e_wbinvd_code_done, width: 1) & sig(:e_wbinvd_data_done, width: 1))) & sig(:cond_170, width: 1)) | ((sig(:cond_172, width: 1) & ((lit(1, width: 2, base: "h", signed: false) == sig(:exe_cmd, width: 7)[2..1]) & sig(:cond_51, width: 1))) | ((sig(:cond_174, width: 1) & sig(:mult_busy, width: 1)) | ((sig(:cond_175, width: 1) & sig(:cond_176, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_149, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_150, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_151, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_152, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_153, width: 1) | ((sig(:cond_186, width: 1) & sig(:cond_20, width: 1)) | ((sig(:cond_193, width: 1) & sig(:cond_10, width: 1)) | ((sig(:cond_196, width: 1) & sig(:cond_197, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_154, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_112, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_155, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_113, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_156, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_114, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_178, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_107, width: 1) | ((sig(:cond_217, width: 1) & sig(:cond_218, width: 1)) | ((sig(:cond_219, width: 1) & sig(:cond_218, width: 1)) | ((sig(:cond_220, width: 1) & sig(:cond_221, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_236, width: 1) | ((sig(:cond_223, width: 1) & (sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[3] & sig(:cond_10, width: 1))) | (sig(:__VdfgRegularize_h7a35cd6a_0_157, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_158, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_159, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_160, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_115, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_161, width: 1) | ((sig(:cond_236, width: 1) & sig(:cond_197, width: 1)) | ((sig(:cond_240, width: 1) & sig(:cond_51, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_235, width: 1) | ((sig(:cond_241, width: 1) & sig(:cond_51, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_234, width: 1) | ((sig(:cond_244, width: 1) & sig(:exe_bound_fault, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_179, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_180, width: 1) | ((sig(:cond_250, width: 1) & sig(:cond_249, width: 1)) | ((sig(:cond_249, width: 1) & sig(:tlbcheck_page_fault, width: 1)) | ((sig(:cond_250, width: 1) & sig(:cond_252, width: 1)) | ((sig(:cond_252, width: 1) & sig(:tlbcheck_page_fault, width: 1)) | ((sig(:cond_250, width: 1) & sig(:cond_253, width: 1)) | ((sig(:cond_253, width: 1) & sig(:tlbcheck_page_fault, width: 1)) | ((sig(:cond_250, width: 1) & sig(:cond_254, width: 1)) | ((sig(:cond_254, width: 1) & sig(:tlbcheck_page_fault, width: 1)) | ((sig(:cond_250, width: 1) & sig(:cond_255, width: 1)) | ((sig(:cond_255, width: 1) & sig(:tlbcheck_page_fault, width: 1)) | ((sig(:cond_250, width: 1) & sig(:cond_256, width: 1)) | ((sig(:cond_256, width: 1) & sig(:tlbcheck_page_fault, width: 1)) | (sig(:__VdfgRegularize_h7a35cd6a_0_181, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_182, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_108, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_183, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_184, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_185, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_186, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_162, width: 1) | (sig(:dr6_bd_set, width: 1) | (sig(:__VdfgRegularize_h7a35cd6a_0_233, width: 1) | (sig(:cond_296, width: 1) & sig(:cond_51, width: 1))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
                                                                                                                                                                                                    )
                                                                                                                                                                                                )
                                                                                                                                                                                            )
                                                                                                                                                                                        )
                                                                                                                                                                                    )
                                                                                                                                                                                )
                                                                                                                                                                            )
                                                                                                                                                                        )
                                                                                                                                                                    )
                                                                                                                                                                )
                                                                                                                                                            )
                                                                                                                                                        )
                                                                                                                                                    )
                                                                                                                                                )
                                                                                                                                            )
                                                                                                                                        )
                                                                                                                                    )
                                                                                                                                )
                                                                                                                            )
                                                                                                                        )
                                                                                                                    )
                                                                                                                )
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                )
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :exe_trigger_nm_fault,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[50] &
        (
            sig(:cond_67, width: 1) &
            (
                sig(:cr0_em, width: 1) |
                sig(:cr0_ts, width: 1)
            )
        )
    )
  assign :dr6_bd_set,
    (
        sig(:cond_286, width: 1) &
        sig(:cond_294, width: 1)
    )
  assign :exe_trigger_pf_fault,
    (
        sig(:tlbcheck_do, width: 1) &
        sig(:tlbcheck_page_fault, width: 1)
    )
  assign :tlbcheck_do,
    (
        sig(:cond_249, width: 1) |
        (
            sig(:cond_252, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_106, width: 1)
        )
    )
  assign :exe_branch,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_240, width: 1),
      sig(:exe_jecxz_condition, width: 1),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_239, width: 1),
        sig(:exe_condition, width: 1),
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_237, width: 1) &
            sig(:exe_cmd_loop_condition, width: 1)
        )
      )
    )
  assign :offset_call,
    (
        sig(:cond_24, width: 1) |
        sig(:cond_25, width: 1)
    )
  assign :invddata_do,
    (
        (
          ~sig(:e_invd_data_done, width: 1)
        ) &
        sig(:cond_55, width: 1)
    )
  assign :offset_iret_glob_param_4,
    (
        sig(:cond_122, width: 1) |
        (
            sig(:cond_186, width: 1) &
            sig(:exe_decoder, width: 40)[0]
        )
    )
  assign :offset_call_int_same_first,
    (
        sig(:cond_29, width: 1) |
        sig(:cond_96, width: 1)
    )
  assign :exe_trigger_db_fault,
    sig(:dr6_bd_set, width: 1)
  assign :exe_glob_descriptor_2_set,
    (
        sig(:cond_24, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_189, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_190, width: 1) |
                sig(:__VdfgRegularize_h7a35cd6a_0_191, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_189,
    (
        sig(:cond_34, width: 1) &
        sig(:exe_ready, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_190,
    (
        sig(:cond_74, width: 1) &
        sig(:exe_ready, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_191,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_164, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_231, width: 1) |
            (
                sig(:cond_121, width: 1) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_230, width: 1) |
                    (
                        sig(:cond_185, width: 1) &
                        sig(:exe_ready, width: 1)
                    )
                )
            )
        )
    )
  assign :exe_glob_param_1_value,
    mux(
      sig(:cond_15, width: 1),
      sig(:__VdfgRegularize_h7a35cd6a_0_192, width: 32),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_193, width: 1),
        sig(:__VdfgRegularize_h7a35cd6a_0_194, width: 32),
        mux(
          sig(:__VdfgRegularize_h7a35cd6a_0_218, width: 1),
          sig(:__VdfgRegularize_h7a35cd6a_0_195, width: 32),
          mux(
            sig(:cond_28, width: 1),
            lit(0, width: 7, base: "d", signed: false).concat(
              sig(:glob_descriptor, width: 64)[36..32].concat(
                sig(:__VdfgRegularize_h7a35cd6a_0_94, width: 1).concat(
                  sig(:__VdfgRegularize_h7a35cd6a_0_196, width: 19)
                )
              )
            ),
            mux(
              sig(:__VdfgRegularize_h7a35cd6a_0_189, width: 1),
              sig(:__VdfgRegularize_h7a35cd6a_0_197, width: 32),
              mux(
                sig(:__VdfgRegularize_h7a35cd6a_0_163, width: 1),
                sig(:glob_param_3, width: 32),
                mux(
                  sig(:cond_73, width: 1),
                  lit(0, width: 11, base: "d", signed: false).concat(
                    sig(:glob_descriptor, width: 64)[40].concat(
                      sig(:__VdfgRegularize_h7a35cd6a_0_198, width: 1).concat(
                        sig(:__VdfgRegularize_h7a35cd6a_0_196, width: 19)
                      )
                    )
                  ),
                  mux(
                    sig(:__VdfgRegularize_h7a35cd6a_0_190, width: 1),
                    sig(:__VdfgRegularize_h7a35cd6a_0_197, width: 32),
                    mux(
                      sig(:__VdfgRegularize_h7a35cd6a_0_164, width: 1),
                      sig(:glob_param_3, width: 32),
                      mux(
                        sig(:__VdfgRegularize_h7a35cd6a_0_231, width: 1),
                        sig(:glob_param_3, width: 32),
                        mux(
                          sig(:cond_121, width: 1),
                          sig(:glob_param_3, width: 32),
                          mux(
                            sig(:__VdfgRegularize_h7a35cd6a_0_230, width: 1),
                            sig(:glob_param_3, width: 32),
                            mux(
                              sig(:cond_185, width: 1),
                              sig(:glob_param_3, width: 32),
                              mux(
                                sig(:__VdfgRegularize_h7a35cd6a_0_217, width: 1),
                                sig(:__VdfgRegularize_h7a35cd6a_0_200, width: 32),
                                mux(
                                  sig(:__VdfgRegularize_h7a35cd6a_0_201, width: 1),
                                  sig(:__VdfgRegularize_h7a35cd6a_0_202, width: 32),
                                  mux(
                                    sig(:__VdfgRegularize_h7a35cd6a_0_203, width: 1),
                                    sig(:__VdfgRegularize_h7a35cd6a_0_204, width: 32),
                                    mux(
                                      sig(:__VdfgRegularize_h7a35cd6a_0_205, width: 1),
                                      sig(:__VdfgRegularize_h7a35cd6a_0_202, width: 32),
                                      mux(
                                        sig(:__VdfgRegularize_h7a35cd6a_0_206, width: 1),
                                        sig(:__VdfgRegularize_h7a35cd6a_0_204, width: 32),
                                        mux(
                                          sig(:__VdfgRegularize_h7a35cd6a_0_207, width: 1),
                                          lit(1, width: 16, base: "h", signed: false).concat(
                                            sig(:exe_selector, width: 16)
                                          ),
                                          mux(
                                            sig(:__VdfgRegularize_h7a35cd6a_0_216, width: 1),
                                            lit(0, width: 16, base: "d", signed: false).concat(
                                              sig(:edx, width: 32)[15..0]
                                            ),
                                            mux(
                                              sig(:__VdfgRegularize_h7a35cd6a_0_215, width: 1),
                                              lit(0, width: 16, base: "d", signed: false).concat(
                                                sig(:edx, width: 32)[15..0]
                                              ),
                                              mux(
                                                sig(:cond_226, width: 1),
                                                sig(:__VdfgRegularize_h7a35cd6a_0_192, width: 32),
                                                mux(
                                                  sig(:__VdfgRegularize_h7a35cd6a_0_209, width: 1),
                                                  sig(:__VdfgRegularize_h7a35cd6a_0_194, width: 32),
                                                  mux(
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_214, width: 1),
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_195, width: 32),
                                                    mux(
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_213, width: 1),
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_200, width: 32),
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
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_192,
    lit(1, width: 16, base: "h", signed: false).concat(
      sig(:src, width: 32)[15..0]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_193,
    (
        sig(:cond_16, width: 1) &
        sig(:exe_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_194,
    lit(1, width: 16, base: "h", signed: false).concat(
      sig(:exe_extra, width: 32)[31..16]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_218,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_167, width: 1) &
        sig(:cond_16, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_195,
    lit(1, width: 16, base: "h", signed: false).concat(
      sig(:exe_extra, width: 32)[15..0]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_94,
    (
        lit(12, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_196,
    lit(1, width: 3, base: "h", signed: false).concat(
      sig(:glob_descriptor, width: 64)[31..16]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_197,
    lit(2, width: 16, base: "h", signed: false).concat(
      sig(:glob_param_3, width: 32)[15..0]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_198,
    (
        lit(14, width: 4, base: "h", signed: false) <=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_217,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_199, width: 1) &
        sig(:cond_196, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_200,
    mux(
      sig(:cond_67, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:edx, width: 32)[15..0]
      ),
      lit(0, width: 24, base: "d", signed: false).concat(
        sig(:exe_decoder, width: 40)[15..8]
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_201,
    (
        sig(:cond_204, width: 1) &
        sig(:cond_205, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_202,
    lit(2, width: 16, base: "h", signed: false).concat(
      sig(:exe_selector, width: 16)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_203,
    (
        sig(:cond_204, width: 1) &
        sig(:cond_206, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_204,
    lit(3, width: 16, base: "h", signed: false).concat(
      sig(:exe_selector, width: 16)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_205,
    (
        sig(:cond_207, width: 1) &
        sig(:cond_205, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_206,
    (
        sig(:cond_207, width: 1) &
        sig(:cond_206, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_207,
    (
        sig(:cond_207, width: 1) &
        sig(:cond_209, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_216,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_208, width: 1) &
        sig(:cond_217, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_215,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_208, width: 1) &
        sig(:cond_219, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_209,
    (
        sig(:cond_227, width: 1) &
        sig(:exe_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_214,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_167, width: 1) &
        sig(:cond_227, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_213,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_199, width: 1) &
        sig(:cond_236, width: 1)
    )
  assign :exe_glob_param_1_set,
    (
        sig(:cond_15, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_193, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_218, width: 1) |
                (
                    sig(:cond_28, width: 1) |
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_189, width: 1) |
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_163, width: 1) |
                            (
                                sig(:cond_73, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h7a35cd6a_0_190, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_164, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h7a35cd6a_0_231, width: 1) |
                                            (
                                                sig(:cond_121, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_230, width: 1) |
                                                    mux(
                                                      sig(:cond_185, width: 1),
                                                      sig(:exe_ready, width: 1),
                                                      (
                                                          sig(:__VdfgRegularize_h7a35cd6a_0_217, width: 1) |
                                                          (
                                                              sig(:__VdfgRegularize_h7a35cd6a_0_201, width: 1) |
                                                              (
                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_203, width: 1) |
                                                                  (
                                                                      sig(:__VdfgRegularize_h7a35cd6a_0_205, width: 1) |
                                                                      (
                                                                          sig(:__VdfgRegularize_h7a35cd6a_0_206, width: 1) |
                                                                          (
                                                                              sig(:__VdfgRegularize_h7a35cd6a_0_207, width: 1) |
                                                                              (
                                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_216, width: 1) |
                                                                                  (
                                                                                      sig(:__VdfgRegularize_h7a35cd6a_0_215, width: 1) |
                                                                                      (
                                                                                          sig(:cond_226, width: 1) |
                                                                                          (
                                                                                              sig(:__VdfgRegularize_h7a35cd6a_0_209, width: 1) |
                                                                                              (
                                                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_214, width: 1) |
                                                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_213, width: 1)
                                                                                              )
                                                                                          )
                                                                                      )
                                                                                  )
                                                                              )
                                                                          )
                                                                      )
                                                                  )
                                                              )
                                                          )
                                                      )
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :offset_call_int_same_next,
    (
        sig(:cond_30, width: 1) |
        (
            sig(:cond_98, width: 1) |
            (
                sig(:cond_99, width: 1) |
                sig(:cond_100, width: 1)
            )
        )
    )
  assign :offset_call_keep,
    (
        sig(:cond_26, width: 1) |
        (
            sig(:cond_31, width: 1) |
            sig(:cond_6, width: 1)
        )
    )
  assign :invdcode_do,
    mux(
      sig(:cond_55, width: 1),
      (
        ~sig(:e_invd_code_done, width: 1)
      ),
      (
          (
            ~sig(:e_wbinvd_code_done, width: 1)
          ) &
          sig(:cond_170, width: 1)
      )
    )
  assign :exe_is_8bit_clear,
    (
        sig(:cond_284, width: 1) &
        sig(:exe_is_8bit, width: 1)
    )
  assign :exe_glob_param_3_value,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_189, width: 1),
      sig(:glob_param_1, width: 32),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_190, width: 1),
        sig(:glob_param_1, width: 32),
        mux(
          sig(:__VdfgRegularize_h7a35cd6a_0_164, width: 1),
          sig(:glob_param_1, width: 32),
          mux(
            sig(:__VdfgRegularize_h7a35cd6a_0_231, width: 1),
            sig(:glob_param_1, width: 32),
            mux(
              sig(:cond_121, width: 1),
              sig(:glob_param_1, width: 32),
              mux(
                sig(:__VdfgRegularize_h7a35cd6a_0_230, width: 1),
                sig(:glob_param_1, width: 32),
                mux(
                  sig(:cond_185, width: 1),
                  sig(:glob_param_1, width: 32),
                  mux(
                    sig(:cond_204, width: 1),
                    sig(:__VdfgRegularize_h7a35cd6a_0_210, width: 32),
                    mux(
                      (
                          (
                            ~sig(:cond_209, width: 1)
                          ) &
                          sig(:cond_207, width: 1)
                      ),
                      sig(:__VdfgRegularize_h7a35cd6a_0_210, width: 32),
                      mux(
                        sig(:__VdfgRegularize_h7a35cd6a_0_207, width: 1),
                        sig(:__VdfgRegularize_h7a35cd6a_0_212, width: 14).concat(
                          lit(0, width: 1, base: "d", signed: false).concat(
                            sig(:exc_push_error, width: 1).concat(
                              sig(:exc_error_code, width: 16)
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
  assign :__VdfgRegularize_h7a35cd6a_0_210,
    sig(:__VdfgRegularize_h7a35cd6a_0_212, width: 14).concat(
      lit(0, width: 18, base: "h", signed: false)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_212,
    lit(0, width: 10, base: "d", signed: false).concat(
      sig(:exe_consumed, width: 4)
    )
  assign :offset_int_real_next,
    (
        sig(:cond_87, width: 1) |
        sig(:cond_88, width: 1)
    )
  assign :tlbcheck_address,
    mux(
      sig(:cond_249, width: 1),
      sig(:glob_desc_base, width: 32),
      mux(
        sig(:cond_252, width: 1),
        (
            sig(:glob_desc_base, width: 32) +
            sig(:exe_new_tss_max, width: 32)
        ),
        mux(
          sig(:cond_253, width: 1),
          sig(:glob_desc_base, width: 32),
          mux(
            sig(:cond_254, width: 1),
            (
                lit(1, width: 32, base: "h", signed: false) +
                sig(:glob_desc_base, width: 32)
            ),
            mux(
              sig(:cond_255, width: 1),
              mux(
                sig(:__VdfgRegularize_h7a35cd6a_0_95, width: 1),
                (
                    lit(14, width: 32, base: "h", signed: false) +
                    sig(:tr_base, width: 32)
                ),
                (
                    lit(32, width: 32, base: "h", signed: false) +
                    sig(:tr_base, width: 32)
                )
              ),
              mux(
                sig(:cond_256, width: 1),
                mux(
                  sig(:__VdfgRegularize_h7a35cd6a_0_95, width: 1),
                  (
                      lit(41, width: 32, base: "h", signed: false) +
                      sig(:tr_base, width: 32)
                  ),
                  (
                      lit(93, width: 32, base: "h", signed: false) +
                      sig(:tr_base, width: 32)
                  )
                ),
                lit(0, width: 32, base: "h", signed: false)
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_95,
    (
        lit(3, width: 4, base: "h", signed: false) >=
        sig(:tr_cache, width: 64)[43..40]
    )
  assign :exe_glob_param_2_value,
    mux(
      sig(:__VdfgRegularize_h7a35cd6a_0_166, width: 1),
      sig(:src, width: 32),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_229, width: 1),
        lit(0, width: 16, base: "d", signed: false).concat(
          sig(:src, width: 32)[15..0]
        ),
        mux(
          sig(:__VdfgRegularize_h7a35cd6a_0_168, width: 1),
          sig(:exe_arith_add, width: 33)[31..0],
          mux(
            sig(:__VdfgRegularize_h7a35cd6a_0_228, width: 1),
            lit(0, width: 16, base: "d", signed: false).concat(
              sig(:exe_arith_add, width: 33)[15..0]
            ),
            mux(
              sig(:cond_28, width: 1),
              mux(
                sig(:__VdfgRegularize_h7a35cd6a_0_94, width: 1),
                sig(:__VdfgRegularize_h7a35cd6a_0_211, width: 32),
                lit(0, width: 16, base: "d", signed: false).concat(
                  sig(:glob_descriptor, width: 64)[15..0]
                )
              ),
              mux(
                sig(:cond_73, width: 1),
                mux(
                  sig(:__VdfgRegularize_h7a35cd6a_0_198, width: 1),
                  sig(:__VdfgRegularize_h7a35cd6a_0_211, width: 32),
                  lit(0, width: 16, base: "d", signed: false).concat(
                    sig(:glob_descriptor, width: 64)[15..0]
                  )
                ),
                mux(
                  sig(:cond_200, width: 1),
                  lit(0, width: 26, base: "d", signed: false).concat(
                    (
                        sig(:__VdfgRegularize_h7a35cd6a_0_64, width: 1) |
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_8, width: 1) |
                            sig(:exe_privilege_not_accepted, width: 1)
                        )
                    ).concat(
                      (
                          sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) |
                          (
                              sig(:__VdfgRegularize_h7a35cd6a_0_249, width: 1) |
                              (
                                  (
                                      sig(:__VdfgRegularize_h7a35cd6a_0_248, width: 1) |
                                      sig(:__VdfgRegularize_h7a35cd6a_0_6, width: 1)
                                  ) &
                                  sig(:exe_privilege_not_accepted, width: 1)
                              )
                          )
                      ).concat(
                        (
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) &
                                (
                                    sig(:__VdfgRegularize_h7a35cd6a_0_16, width: 1) &
                                    (
                                        sig(:__VdfgRegularize_h7a35cd6a_0_62, width: 1) &
                                        (
                                            sig(:__VdfgRegularize_h7a35cd6a_0_17, width: 1) &
                                            (
                                                sig(:__VdfgRegularize_h7a35cd6a_0_63, width: 1) &
                                                sig(:__VdfgRegularize_h7a35cd6a_0_13, width: 1)
                                            )
                                        )
                                    )
                                )
                            ) |
                            (
                                sig(:__VdfgRegularize_h7a35cd6a_0_61, width: 1) |
                                sig(:__VdfgRegularize_h7a35cd6a_0_247, width: 1)
                            )
                        ).concat(
                          (
                              (
                                  sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) &
                                  (
                                      sig(:__VdfgRegularize_h7a35cd6a_0_53, width: 1) |
                                      (
                                          sig(:__VdfgRegularize_h7a35cd6a_0_54, width: 1) |
                                          (
                                              sig(:__VdfgRegularize_h7a35cd6a_0_55, width: 1) |
                                              sig(:__VdfgRegularize_h7a35cd6a_0_56, width: 1)
                                          )
                                      )
                                  )
                              ) |
                              (
                                  sig(:__VdfgRegularize_h7a35cd6a_0_247, width: 1) |
                                  (
                                      (
                                          sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) &
                                          (
                                              sig(:__VdfgRegularize_h7a35cd6a_0_57, width: 1) |
                                              (
                                                  sig(:__VdfgRegularize_h7a35cd6a_0_58, width: 1) |
                                                  (
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_59, width: 1) |
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_60, width: 1)
                                                  )
                                              )
                                          )
                                      ) |
                                      sig(:__VdfgRegularize_h7a35cd6a_0_61, width: 1)
                                  )
                              )
                          ).concat(
                            sig(:glob_param_2, width: 32)[1..0]
                          )
                        )
                      )
                    )
                  ),
                  mux(
                    sig(:__VdfgRegularize_h7a35cd6a_0_169, width: 1),
                    sig(:src, width: 32),
                    mux(
                      sig(:__VdfgRegularize_h7a35cd6a_0_227, width: 1),
                      lit(0, width: 16, base: "d", signed: false).concat(
                        sig(:src, width: 32)[15..0]
                      ),
                      mux(
                        sig(:__VdfgRegularize_h7a35cd6a_0_170, width: 1),
                        sig(:exe_arith_add, width: 33)[31..0],
                        mux(
                          sig(:__VdfgRegularize_h7a35cd6a_0_226, width: 1),
                          lit(0, width: 16, base: "d", signed: false).concat(
                            sig(:exe_arith_add, width: 33)[15..0]
                          ),
                          mux(
                            sig(:exe_task_switch_finished, width: 1),
                            sig(:exe_eip, width: 32),
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
  assign :__VdfgRegularize_h7a35cd6a_0_211,
    sig(:glob_descriptor, width: 64)[63..48].concat(
      sig(:glob_descriptor, width: 64)[15..0]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_64,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) |
        sig(:glob_descriptor, width: 64)[43]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_249,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_7, width: 1) &
        sig(:glob_descriptor, width: 64)[43]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_248,
    (
        (
          ~sig(:glob_descriptor, width: 64)[42]
        ) &
        sig(:glob_descriptor, width: 64)[43]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_6,
    (
      ~sig(:glob_descriptor, width: 64)[43]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_16,
    (
        lit(9, width: 4, base: "h", signed: false) !=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_62,
    (
        lit(11, width: 4, base: "h", signed: false) !=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_17,
    (
        lit(1, width: 4, base: "h", signed: false) !=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_63,
    (
        lit(3, width: 4, base: "h", signed: false) !=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_13,
    (
        lit(2, width: 4, base: "h", signed: false) !=
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_61,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) &
        sig(:exe_privilege_not_accepted, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_247,
    (
        sig(:glob_descriptor, width: 64)[44] &
        sig(:__VdfgRegularize_h7a35cd6a_0_10, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_53,
    (
        lit(0, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_54,
    (
        lit(8, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_55,
    (
        lit(10, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_56,
    (
        lit(13, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_57,
    (
        lit(14, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_58,
    (
        lit(6, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_59,
    (
        lit(15, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_60,
    (
        lit(7, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :exe_arith_index,
    mux(
      sig(:cond_0, width: 1),
      lit(8, width: 4, base: "h", signed: false),
      mux(
        sig(:cond_49, width: 1),
        lit(13, width: 4, base: "h", signed: false),
        mux(
          sig(:cond_63, width: 1),
          lit(13, width: 4, base: "h", signed: false),
          mux(
            sig(:cond_64, width: 1),
            mux(
              sig(:exe_cmdex, width: 4)[0],
              lit(13, width: 4, base: "h", signed: false),
              lit(8, width: 4, base: "h", signed: false)
            ),
            mux(
              sig(:cond_144, width: 1),
              lit(13, width: 4, base: "h", signed: false),
              mux(
                sig(:exe_cmpxchg_switch, width: 1),
                lit(13, width: 4, base: "h", signed: false),
                mux(
                  sig(:cond_172, width: 1),
                  lit(1, width: 1, base: "h", signed: false).concat(
                    sig(:exe_cmd, width: 7)[2..0]
                  ),
                  mux(
                    sig(:cond_178, width: 1),
                    lit(12, width: 4, base: "h", signed: false),
                    lit(0, width: 4, base: "h", signed: false)
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :exe_glob_descriptor_set,
    (
        sig(:cond_24, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_232, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_163, width: 1) |
                sig(:__VdfgRegularize_h7a35cd6a_0_191, width: 1)
            )
        )
    )
  assign :exe_result,
    mux(
      sig(:cond_0, width: 1),
      sig(:exe_arith_add, width: 33)[31..0],
      mux(
        (
            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[1] &
            sig(:cond_67, width: 1)
        ),
        sig(:exe_buffer, width: 32),
        mux(
          (
              sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[6] &
              sig(:exe_cmdex, width: 4)[3]
          ),
          sig(:__VdfgRegularize_h7a35cd6a_0_225, width: 32),
          mux(
            sig(:cond_49, width: 1),
            sig(:exe_arith_sub, width: 33)[31..0],
            mux(
              sig(:cond_63, width: 1),
              sig(:exe_arith_sub, width: 33)[31..0],
              mux(
                sig(:cond_64, width: 1),
                mux(
                  sig(:exe_cmdex, width: 4)[0],
                  sig(:exe_arith_sub, width: 33)[31..0],
                  sig(:exe_arith_add, width: 33)[31..0]
                ),
                mux(
                  sig(:cond_68, width: 1),
                  lit(0, width: 16, base: "d", signed: false).concat(
                    sig(:dst, width: 32)[15..2].concat(
                      sig(:src, width: 32)[1..0]
                    )
                  ),
                  mux(
                    (
                        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[17] &
                        sig(:exe_operand_32bit, width: 1)
                    ),
                    sig(:dst, width: 32)[7..0].concat(
                      sig(:dst, width: 32)[15..8].concat(
                        sig(:dst, width: 32)[23..16].concat(
                          sig(:dst, width: 32)[31..24]
                        )
                      )
                    ),
                    mux(
                      (
                          lit(18, width: 7, base: "h", signed: false) ==
                          sig(:exe_cmd, width: 7)
                      ),
                      sig(:glob_param_2, width: 32),
                      mux(
                        sig(:cond_106, width: 1),
                        lit(0, width: 24, base: "d", signed: false).concat(
                          (
                              (
                                  (
                                      sig(:mult_result, width: 66)[7..0] +
                                      sig(:dst, width: 32)[7..0]
                                  ) >>
                                  lit(0, width: nil, base: "d", signed: false)
                              ) &
                              (
                                  (
                                      lit(1, width: 32, base: "d") <<
                                      (
                                            (
                                              lit(7, width: nil, base: "d", signed: false)
                                            ) -
                                            (
                                              lit(0, width: nil, base: "d", signed: false)
                                            ) +
                                          lit(1, width: 32, base: "d")
                                      )
                                  ) -
                                  lit(1, width: 32, base: "d")
                              )
                          )
                        ),
                        mux(
                          sig(:cond_108, width: 1),
                          lit(0, width: 16, base: "d", signed: false).concat(
                            sig(:div_result_quotient, width: 32)[7..0].concat(
                              sig(:div_result_remainder, width: 32)[7..0]
                            )
                          ),
                          mux(
                            sig(:cond_117, width: 1),
                            mux(
                              sig(:__VdfgRegularize_h7a35cd6a_0_22, width: 1),
                              sig(:dst, width: 32)[31..1].concat(
                                sig(:e_bit_value, width: 1)
                              ),
                              mux(
                                sig(:__VdfgRegularize_h7a35cd6a_0_23, width: 1),
                                sig(:dst, width: 32)[31..2].concat(
                                  sig(:e_bit_value, width: 1).concat(
                                    sig(:dst, width: 32)[0]
                                  )
                                ),
                                mux(
                                  sig(:__VdfgRegularize_h7a35cd6a_0_24, width: 1),
                                  sig(:dst, width: 32)[31..3].concat(
                                    sig(:e_bit_value, width: 1).concat(
                                      sig(:dst, width: 32)[1..0]
                                    )
                                  ),
                                  mux(
                                    sig(:__VdfgRegularize_h7a35cd6a_0_25, width: 1),
                                    sig(:dst, width: 32)[31..4].concat(
                                      sig(:e_bit_value, width: 1).concat(
                                        sig(:dst, width: 32)[2..0]
                                      )
                                    ),
                                    mux(
                                      sig(:__VdfgRegularize_h7a35cd6a_0_26, width: 1),
                                      sig(:dst, width: 32)[31..5].concat(
                                        sig(:e_bit_value, width: 1).concat(
                                          sig(:dst, width: 32)[3..0]
                                        )
                                      ),
                                      mux(
                                        sig(:__VdfgRegularize_h7a35cd6a_0_27, width: 1),
                                        sig(:dst, width: 32)[31..6].concat(
                                          sig(:e_bit_value, width: 1).concat(
                                            sig(:dst, width: 32)[4..0]
                                          )
                                        ),
                                        mux(
                                          sig(:__VdfgRegularize_h7a35cd6a_0_28, width: 1),
                                          sig(:dst, width: 32)[31..7].concat(
                                            sig(:e_bit_value, width: 1).concat(
                                              sig(:dst, width: 32)[5..0]
                                            )
                                          ),
                                          mux(
                                            sig(:__VdfgRegularize_h7a35cd6a_0_29, width: 1),
                                            sig(:dst, width: 32)[31..8].concat(
                                              sig(:e_bit_value, width: 1).concat(
                                                sig(:dst, width: 32)[6..0]
                                              )
                                            ),
                                            mux(
                                              sig(:__VdfgRegularize_h7a35cd6a_0_30, width: 1),
                                              sig(:dst, width: 32)[31..9].concat(
                                                sig(:e_bit_value, width: 1).concat(
                                                  sig(:dst, width: 32)[7..0]
                                                )
                                              ),
                                              mux(
                                                sig(:__VdfgRegularize_h7a35cd6a_0_31, width: 1),
                                                sig(:dst, width: 32)[31..10].concat(
                                                  sig(:e_bit_value, width: 1).concat(
                                                    sig(:dst, width: 32)[8..0]
                                                  )
                                                ),
                                                mux(
                                                  sig(:__VdfgRegularize_h7a35cd6a_0_32, width: 1),
                                                  sig(:dst, width: 32)[31..11].concat(
                                                    sig(:e_bit_value, width: 1).concat(
                                                      sig(:dst, width: 32)[9..0]
                                                    )
                                                  ),
                                                  mux(
                                                    sig(:__VdfgRegularize_h7a35cd6a_0_33, width: 1),
                                                    sig(:dst, width: 32)[31..12].concat(
                                                      sig(:e_bit_value, width: 1).concat(
                                                        sig(:dst, width: 32)[10..0]
                                                      )
                                                    ),
                                                    mux(
                                                      sig(:__VdfgRegularize_h7a35cd6a_0_34, width: 1),
                                                      sig(:dst, width: 32)[31..13].concat(
                                                        sig(:e_bit_value, width: 1).concat(
                                                          sig(:dst, width: 32)[11..0]
                                                        )
                                                      ),
                                                      mux(
                                                        sig(:__VdfgRegularize_h7a35cd6a_0_35, width: 1),
                                                        sig(:dst, width: 32)[31..14].concat(
                                                          sig(:e_bit_value, width: 1).concat(
                                                            sig(:dst, width: 32)[12..0]
                                                          )
                                                        ),
                                                        mux(
                                                          sig(:__VdfgRegularize_h7a35cd6a_0_36, width: 1),
                                                          sig(:dst, width: 32)[31..15].concat(
                                                            sig(:e_bit_value, width: 1).concat(
                                                              sig(:dst, width: 32)[13..0]
                                                            )
                                                          ),
                                                          mux(
                                                            sig(:__VdfgRegularize_h7a35cd6a_0_37, width: 1),
                                                            sig(:dst, width: 32)[31..16].concat(
                                                              sig(:e_bit_value, width: 1).concat(
                                                                sig(:dst, width: 32)[14..0]
                                                              )
                                                            ),
                                                            mux(
                                                              sig(:__VdfgRegularize_h7a35cd6a_0_38, width: 1),
                                                              sig(:dst, width: 32)[31..17].concat(
                                                                sig(:e_bit_value, width: 1).concat(
                                                                  sig(:dst, width: 32)[15..0]
                                                                )
                                                              ),
                                                              mux(
                                                                sig(:__VdfgRegularize_h7a35cd6a_0_39, width: 1),
                                                                sig(:dst, width: 32)[31..18].concat(
                                                                  sig(:e_bit_value, width: 1).concat(
                                                                    sig(:dst, width: 32)[16..0]
                                                                  )
                                                                ),
                                                                mux(
                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_40, width: 1),
                                                                  sig(:dst, width: 32)[31..19].concat(
                                                                    sig(:e_bit_value, width: 1).concat(
                                                                      sig(:dst, width: 32)[17..0]
                                                                    )
                                                                  ),
                                                                  mux(
                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_41, width: 1),
                                                                    sig(:dst, width: 32)[31..20].concat(
                                                                      sig(:e_bit_value, width: 1).concat(
                                                                        sig(:dst, width: 32)[18..0]
                                                                      )
                                                                    ),
                                                                    mux(
                                                                      sig(:__VdfgRegularize_h7a35cd6a_0_42, width: 1),
                                                                      sig(:dst, width: 32)[31..21].concat(
                                                                        sig(:e_bit_value, width: 1).concat(
                                                                          sig(:dst, width: 32)[19..0]
                                                                        )
                                                                      ),
                                                                      mux(
                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_43, width: 1),
                                                                        sig(:dst, width: 32)[31..22].concat(
                                                                          sig(:e_bit_value, width: 1).concat(
                                                                            sig(:dst, width: 32)[20..0]
                                                                          )
                                                                        ),
                                                                        mux(
                                                                          sig(:__VdfgRegularize_h7a35cd6a_0_44, width: 1),
                                                                          sig(:dst, width: 32)[31..23].concat(
                                                                            sig(:e_bit_value, width: 1).concat(
                                                                              sig(:dst, width: 32)[21..0]
                                                                            )
                                                                          ),
                                                                          mux(
                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_45, width: 1),
                                                                            sig(:dst, width: 32)[31..24].concat(
                                                                              sig(:e_bit_value, width: 1).concat(
                                                                                sig(:dst, width: 32)[22..0]
                                                                              )
                                                                            ),
                                                                            mux(
                                                                              sig(:__VdfgRegularize_h7a35cd6a_0_46, width: 1),
                                                                              sig(:dst, width: 32)[31..25].concat(
                                                                                sig(:e_bit_value, width: 1).concat(
                                                                                  sig(:dst, width: 32)[23..0]
                                                                                )
                                                                              ),
                                                                              mux(
                                                                                sig(:__VdfgRegularize_h7a35cd6a_0_47, width: 1),
                                                                                sig(:dst, width: 32)[31..26].concat(
                                                                                  sig(:e_bit_value, width: 1).concat(
                                                                                    sig(:dst, width: 32)[24..0]
                                                                                  )
                                                                                ),
                                                                                mux(
                                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_48, width: 1),
                                                                                  sig(:dst, width: 32)[31..27].concat(
                                                                                    sig(:e_bit_value, width: 1).concat(
                                                                                      sig(:dst, width: 32)[25..0]
                                                                                    )
                                                                                  ),
                                                                                  mux(
                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_49, width: 1),
                                                                                    sig(:dst, width: 32)[31..28].concat(
                                                                                      sig(:e_bit_value, width: 1).concat(
                                                                                        sig(:dst, width: 32)[26..0]
                                                                                      )
                                                                                    ),
                                                                                    mux(
                                                                                      sig(:__VdfgRegularize_h7a35cd6a_0_50, width: 1),
                                                                                      sig(:dst, width: 32)[31..29].concat(
                                                                                        sig(:e_bit_value, width: 1).concat(
                                                                                          sig(:dst, width: 32)[27..0]
                                                                                        )
                                                                                      ),
                                                                                      mux(
                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_51, width: 1),
                                                                                        sig(:dst, width: 32)[31..30].concat(
                                                                                          sig(:e_bit_value, width: 1).concat(
                                                                                            sig(:dst, width: 32)[28..0]
                                                                                          )
                                                                                        ),
                                                                                        mux(
                                                                                          sig(:__VdfgRegularize_h7a35cd6a_0_52, width: 1),
                                                                                          sig(:dst, width: 32)[31].concat(
                                                                                            sig(:e_bit_value, width: 1).concat(
                                                                                              sig(:dst, width: 32)[29..0]
                                                                                            )
                                                                                          ),
                                                                                          sig(:e_bit_value, width: 1).concat(
                                                                                            sig(:dst, width: 32)[30..0]
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
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
                              sig(:cond_138, width: 1),
                              sig(:src, width: 32),
                              mux(
                                sig(:cond_140, width: 1),
                                sig(:exe_buffer, width: 32),
                                mux(
                                  sig(:cond_141, width: 1),
                                  mux(
                                    sig(:exe_is_8bit, width: 1),
                                    lit(0, width: 16, base: "d", signed: false).concat(
                                      sig(:div_result_remainder, width: 32)[7..0].concat(
                                        sig(:div_result_quotient, width: 32)[7..0]
                                      )
                                    ),
                                    mux(
                                      sig(:exe_operand_16bit, width: 1),
                                      sig(:div_result_remainder, width: 32)[15..0].concat(
                                        sig(:div_result_quotient, width: 32)[15..0]
                                      ),
                                      sig(:div_result_quotient, width: 32)
                                    )
                                  ),
                                  mux(
                                    sig(:cond_142, width: 1),
                                    sig(:e_shift_result, width: 32),
                                    mux(
                                      sig(:cond_143, width: 1),
                                      sig(:e_shift_result, width: 32),
                                      mux(
                                        sig(:cond_144, width: 1),
                                        sig(:exe_arith_sub, width: 33)[31..0],
                                        mux(
                                          (
                                              sig(:cond_146, width: 1) &
                                              sig(:cond_147, width: 1)
                                          ),
                                          sig(:e_cr0_reg, width: 32),
                                          mux(
                                            (
                                                sig(:cond_146, width: 1) &
                                                sig(:cond_148, width: 1)
                                            ),
                                            sig(:cr2, width: 32),
                                            mux(
                                              (
                                                  sig(:cond_146, width: 1) &
                                                  sig(:cond_149, width: 1)
                                              ),
                                              sig(:cr3, width: 32),
                                              mux(
                                                (
                                                    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[46] &
                                                    sig(:cond_9, width: 1)
                                                ),
                                                sig(:e_cr0_reg, width: 32),
                                                mux(
                                                  (
                                                      sig(:cond_158, width: 1) &
                                                      sig(:exe_condition, width: 1)
                                                  ),
                                                  lit(1, width: 32, base: "h", signed: false),
                                                  mux(
                                                    sig(:exe_cmpxchg_switch, width: 1),
                                                    mux(
                                                      sig(:e_cmpxchg_eq, width: 1),
                                                      sig(:src, width: 32),
                                                      sig(:e_cmpxchg_sub, width: 33)[31..0]
                                                    ),
                                                    mux(
                                                      sig(:cond_166, width: 1),
                                                      sig(:mult_result, width: 66)[31..0],
                                                      mux(
                                                        sig(:cond_168, width: 1),
                                                        sig(:e_shift_result, width: 32),
                                                        mux(
                                                          sig(:cond_172, width: 1),
                                                          case_select(
                                                            sig(:exe_cmd, width: 7)[2..0],
                                                            cases: {
                                                              0 => sig(:exe_arith_add, width: 33)[31..0],
                                                              1 => (sig(:dst, width: 32) | sig(:src, width: 32)),
                                                              2 => sig(:exe_arith_adc, width: 33)[31..0],
                                                              3 => sig(:exe_arith_sbb, width: 33)[31..0],
                                                              4 => sig(:exe_arith_and, width: 32),
                                                              6 => (sig(:dst, width: 32) ^ sig(:src, width: 32))
                                                            },
                                                            default: sig(:exe_arith_sub, width: 33)[31..0]
                                                          ),
                                                          mux(
                                                            sig(:cond_174, width: 1),
                                                            sig(:mult_result, width: 66)[31..0],
                                                            mux(
                                                              sig(:cond_178, width: 1),
                                                              sig(:exe_arith_and, width: 32),
                                                              mux(
                                                                sig(:cond_190, width: 1),
                                                                sig(:src, width: 32),
                                                                mux(
                                                                  sig(:cond_191, width: 1),
                                                                  sig(:src, width: 32),
                                                                  mux(
                                                                    (
                                                                        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[73] &
                                                                        sig(:cond_165, width: 1)
                                                                    ),
                                                                    sig(:exe_buffer, width: 32),
                                                                    mux(
                                                                      (
                                                                          lit(78, width: 7, base: "h", signed: false) ==
                                                                          sig(:exe_cmd, width: 7)
                                                                      ),
                                                                      (
                                                                        ~sig(:dst, width: 32)
                                                                      ),
                                                                      mux(
                                                                        (
                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_88, width: 1) &
                                                                            sig(:cond_165, width: 1)
                                                                        ),
                                                                        sig(:exe_extra, width: 32),
                                                                        mux(
                                                                          sig(:cond_239, width: 1),
                                                                          sig(:src, width: 32),
                                                                          mux(
                                                                            (
                                                                                lit(103, width: 7, base: "h", signed: false) ==
                                                                                sig(:exe_cmd, width: 7)
                                                                            ),
                                                                            sig(:exe_address_effective, width: 32),
                                                                            mux(
                                                                              (
                                                                                  sig(:cond_279, width: 1) &
                                                                                  sig(:cond_9, width: 1)
                                                                              ),
                                                                              lit(0, width: 16, base: "d", signed: false).concat(
                                                                                sig(:gdtr_limit, width: 16)
                                                                              ),
                                                                              mux(
                                                                                (
                                                                                    sig(:cond_279, width: 1) &
                                                                                    sig(:cond_67, width: 1)
                                                                                ),
                                                                                sig(:gdtr_base, width: 32),
                                                                                mux(
                                                                                  (
                                                                                      sig(:cond_282, width: 1) &
                                                                                      sig(:cond_9, width: 1)
                                                                                  ),
                                                                                  lit(0, width: 16, base: "d", signed: false).concat(
                                                                                    sig(:idtr_limit, width: 16)
                                                                                  ),
                                                                                  mux(
                                                                                    (
                                                                                        sig(:cond_282, width: 1) &
                                                                                        sig(:cond_67, width: 1)
                                                                                    ),
                                                                                    sig(:idtr_base, width: 32),
                                                                                    mux(
                                                                                      sig(:cond_284, width: 1),
                                                                                      mux(
                                                                                        (
                                                                                            sig(:__VdfgRegularize_h7a35cd6a_0_99, width: 1) &
                                                                                            sig(:exe_is_8bit, width: 1)
                                                                                        ),
                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_173, width: 32),
                                                                                        mux(
                                                                                          sig(:__VdfgRegularize_h7a35cd6a_0_99, width: 1),
                                                                                          sig(:__VdfgRegularize_h7a35cd6a_0_65, width: 32),
                                                                                          mux(
                                                                                            (
                                                                                                sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[107] &
                                                                                                sig(:exe_is_8bit, width: 1)
                                                                                            ),
                                                                                            lit(0, width: 24, base: "d", signed: false).concat(
                                                                                              sig(:src, width: 32)[7..0]
                                                                                            ),
                                                                                            lit(0, width: 16, base: "d", signed: false).concat(
                                                                                              sig(:src, width: 32)[15..0]
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                      ),
                                                                                      mux(
                                                                                        (
                                                                                            sig(:cond_286, width: 1) &
                                                                                            (
                                                                                                sig(:cond_9, width: 1) &
                                                                                                sig(:cond_147, width: 1)
                                                                                            )
                                                                                        ),
                                                                                        sig(:dr0, width: 32),
                                                                                        mux(
                                                                                          (
                                                                                              sig(:cond_286, width: 1) &
                                                                                              (
                                                                                                  sig(:cond_9, width: 1) &
                                                                                                  (
                                                                                                      lit(1, width: 3, base: "h", signed: false) ==
                                                                                                      sig(:exe_modregrm_reg, width: 3)
                                                                                                  )
                                                                                              )
                                                                                          ),
                                                                                          sig(:dr1, width: 32),
                                                                                          mux(
                                                                                            (
                                                                                                sig(:cond_286, width: 1) &
                                                                                                (
                                                                                                    sig(:cond_9, width: 1) &
                                                                                                    sig(:cond_148, width: 1)
                                                                                                )
                                                                                            ),
                                                                                            sig(:dr2, width: 32),
                                                                                            mux(
                                                                                              (
                                                                                                  sig(:cond_286, width: 1) &
                                                                                                  (
                                                                                                      sig(:cond_9, width: 1) &
                                                                                                      sig(:cond_149, width: 1)
                                                                                                  )
                                                                                              ),
                                                                                              sig(:dr3, width: 32),
                                                                                              mux(
                                                                                                (
                                                                                                    sig(:cond_286, width: 1) &
                                                                                                    (
                                                                                                        sig(:cond_9, width: 1) &
                                                                                                        (
                                                                                                            (
                                                                                                                lit(4, width: 3, base: "h", signed: false) ==
                                                                                                                sig(:exe_modregrm_reg, width: 3)
                                                                                                            ) |
                                                                                                            (
                                                                                                                lit(6, width: 3, base: "h", signed: false) ==
                                                                                                                sig(:exe_modregrm_reg, width: 3)
                                                                                                            )
                                                                                                        )
                                                                                                    )
                                                                                                ),
                                                                                                lit(65535, width: 16, base: "h", signed: false).concat(
                                                                                                  sig(:dr6_bt, width: 1).concat(
                                                                                                    sig(:dr6_bs, width: 1).concat(
                                                                                                      sig(:dr6_bd, width: 1).concat(
                                                                                                        sig(:dr6_b12, width: 1).concat(
                                                                                                          lit(255, width: 8, base: "h", signed: false).concat(
                                                                                                            sig(:dr6_breakpoints, width: 4)
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                  )
                                                                                                ),
                                                                                                mux(
                                                                                                  (
                                                                                                      sig(:cond_286, width: 1) &
                                                                                                      (
                                                                                                          sig(:cond_9, width: 1) &
                                                                                                          (
                                                                                                              (
                                                                                                                  lit(5, width: 3, base: "h", signed: false) ==
                                                                                                                  sig(:exe_modregrm_reg, width: 3)
                                                                                                              ) |
                                                                                                              (
                                                                                                                  lit(7, width: 3, base: "h", signed: false) ==
                                                                                                                  sig(:exe_modregrm_reg, width: 3)
                                                                                                              )
                                                                                                          )
                                                                                                      )
                                                                                                  ),
                                                                                                  sig(:dr7, width: 32),
                                                                                                  mux(
                                                                                                    sig(:cond_295, width: 1),
                                                                                                    sig(:src, width: 32),
                                                                                                    mux(
                                                                                                      sig(:__VdfgRegularize_h7a35cd6a_0_100, width: 1),
                                                                                                      lit(0, width: 16, base: "d", signed: false).concat(
                                                                                                        (
                                                                                                            (
                                                                                                                mux(
                                                                                                                  sig(:exe_bcd_condition_af, width: 1),
                                                                                                                  sig(:e_aaa_sum_ax, width: 16)[15..8].concat(
                                                                                                                    lit(0, width: 4, base: "d", signed: false).concat(
                                                                                                                      sig(:e_aaa_sum_ax, width: 16)[3..0]
                                                                                                                    )
                                                                                                                  ),
                                                                                                                  sig(:__VdfgRegularize_h7a35cd6a_0_66, width: 16)
                                                                                                                ) >>
                                                                                                                lit(0, width: nil, base: "d", signed: false)
                                                                                                            ) &
                                                                                                            (
                                                                                                                (
                                                                                                                    lit(1, width: 32, base: "d") <<
                                                                                                                    (
                                                                                                                          (
                                                                                                                            lit(15, width: nil, base: "d", signed: false)
                                                                                                                          ) -
                                                                                                                          (
                                                                                                                            lit(0, width: nil, base: "d", signed: false)
                                                                                                                          ) +
                                                                                                                        lit(1, width: 32, base: "d")
                                                                                                                    )
                                                                                                                ) -
                                                                                                                lit(1, width: 32, base: "d")
                                                                                                            )
                                                                                                        )
                                                                                                      ),
                                                                                                      mux(
                                                                                                        sig(:__VdfgRegularize_h7a35cd6a_0_101, width: 1),
                                                                                                        lit(0, width: 16, base: "d", signed: false).concat(
                                                                                                          (
                                                                                                              (
                                                                                                                  mux(
                                                                                                                    sig(:exe_bcd_condition_af, width: 1),
                                                                                                                    sig(:e_aas_sub_ax, width: 16)[15..8].concat(
                                                                                                                      lit(0, width: 4, base: "d", signed: false).concat(
                                                                                                                        sig(:e_aas_sub_ax, width: 16)[3..0]
                                                                                                                      )
                                                                                                                    ),
                                                                                                                    sig(:__VdfgRegularize_h7a35cd6a_0_66, width: 16)
                                                                                                                  ) >>
                                                                                                                  lit(0, width: nil, base: "d", signed: false)
                                                                                                              ) &
                                                                                                              (
                                                                                                                  (
                                                                                                                      lit(1, width: 32, base: "d") <<
                                                                                                                      (
                                                                                                                            (
                                                                                                                              lit(15, width: nil, base: "d", signed: false)
                                                                                                                            ) -
                                                                                                                            (
                                                                                                                              lit(0, width: nil, base: "d", signed: false)
                                                                                                                            ) +
                                                                                                                          lit(1, width: 32, base: "d")
                                                                                                                      )
                                                                                                                  ) -
                                                                                                                  lit(1, width: 32, base: "d")
                                                                                                              )
                                                                                                          )
                                                                                                        ),
                                                                                                        mux(
                                                                                                          sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[114],
                                                                                                          lit(0, width: 16, base: "d", signed: false).concat(
                                                                                                            sig(:dst, width: 32)[15..8]
                                                                                                          ).concat(
                                                                                                            mux(
                                                                                                              sig(:e_bcd_condition_cf, width: 1),
                                                                                                              (
                                                                                                                  lit(96, width: 8, base: "h", signed: false) +
                                                                                                                  sig(:e_daa_step1, width: 8)
                                                                                                              ),
                                                                                                              sig(:e_daa_step1, width: 8)
                                                                                                            )
                                                                                                          ),
                                                                                                          mux(
                                                                                                            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[115],
                                                                                                            lit(0, width: 16, base: "d", signed: false).concat(
                                                                                                              sig(:dst, width: 32)[15..8]
                                                                                                            ).concat(
                                                                                                              mux(
                                                                                                                sig(:e_bcd_condition_cf, width: 1),
                                                                                                                (
                                                                                                                    sig(:e_das_step1, width: 8) -
                                                                                                                    lit(96, width: 8, base: "h", signed: false)
                                                                                                                ),
                                                                                                                sig(:e_das_step1, width: 8)
                                                                                                              )
                                                                                                            ),
                                                                                                            mux(
                                                                                                              (
                                                                                                                  sig(:cond_297, width: 1) &
                                                                                                                  sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[116]
                                                                                                              ),
                                                                                                              lit(0, width: 27, base: "d", signed: false).concat(
                                                                                                                (
                                                                                                                    (
                                                                                                                        mux(
                                                                                                                          sig(:src, width: 32)[0],
                                                                                                                          lit(0, width: 5, base: "h", signed: false),
                                                                                                                          mux(
                                                                                                                            sig(:src, width: 32)[1],
                                                                                                                            lit(1, width: 5, base: "h", signed: false),
                                                                                                                            mux(
                                                                                                                              sig(:src, width: 32)[2],
                                                                                                                              lit(2, width: 5, base: "h", signed: false),
                                                                                                                              mux(
                                                                                                                                sig(:src, width: 32)[3],
                                                                                                                                lit(3, width: 5, base: "h", signed: false),
                                                                                                                                mux(
                                                                                                                                  sig(:src, width: 32)[4],
                                                                                                                                  lit(4, width: 5, base: "h", signed: false),
                                                                                                                                  mux(
                                                                                                                                    sig(:src, width: 32)[5],
                                                                                                                                    lit(5, width: 5, base: "h", signed: false),
                                                                                                                                    mux(
                                                                                                                                      sig(:src, width: 32)[6],
                                                                                                                                      lit(6, width: 5, base: "h", signed: false),
                                                                                                                                      mux(
                                                                                                                                        sig(:src, width: 32)[7],
                                                                                                                                        lit(7, width: 5, base: "h", signed: false),
                                                                                                                                        mux(
                                                                                                                                          sig(:src, width: 32)[8],
                                                                                                                                          lit(8, width: 5, base: "h", signed: false),
                                                                                                                                          mux(
                                                                                                                                            sig(:src, width: 32)[9],
                                                                                                                                            lit(9, width: 5, base: "h", signed: false),
                                                                                                                                            mux(
                                                                                                                                              sig(:src, width: 32)[10],
                                                                                                                                              lit(10, width: 5, base: "h", signed: false),
                                                                                                                                              mux(
                                                                                                                                                sig(:src, width: 32)[11],
                                                                                                                                                lit(11, width: 5, base: "h", signed: false),
                                                                                                                                                mux(
                                                                                                                                                  sig(:src, width: 32)[12],
                                                                                                                                                  lit(12, width: 5, base: "h", signed: false),
                                                                                                                                                  mux(
                                                                                                                                                    sig(:src, width: 32)[13],
                                                                                                                                                    lit(13, width: 5, base: "h", signed: false),
                                                                                                                                                    mux(
                                                                                                                                                      sig(:src, width: 32)[14],
                                                                                                                                                      lit(14, width: 5, base: "h", signed: false),
                                                                                                                                                      mux(
                                                                                                                                                        sig(:src, width: 32)[15],
                                                                                                                                                        lit(15, width: 5, base: "h", signed: false),
                                                                                                                                                        mux(
                                                                                                                                                          sig(:src, width: 32)[16],
                                                                                                                                                          lit(16, width: 5, base: "h", signed: false),
                                                                                                                                                          mux(
                                                                                                                                                            sig(:src, width: 32)[17],
                                                                                                                                                            lit(17, width: 5, base: "h", signed: false),
                                                                                                                                                            mux(
                                                                                                                                                              sig(:src, width: 32)[18],
                                                                                                                                                              lit(18, width: 5, base: "h", signed: false),
                                                                                                                                                              mux(
                                                                                                                                                                sig(:src, width: 32)[19],
                                                                                                                                                                lit(19, width: 5, base: "h", signed: false),
                                                                                                                                                                mux(
                                                                                                                                                                  sig(:src, width: 32)[20],
                                                                                                                                                                  lit(20, width: 5, base: "h", signed: false),
                                                                                                                                                                  mux(
                                                                                                                                                                    sig(:src, width: 32)[21],
                                                                                                                                                                    lit(21, width: 5, base: "h", signed: false),
                                                                                                                                                                    mux(
                                                                                                                                                                      sig(:src, width: 32)[22],
                                                                                                                                                                      lit(22, width: 5, base: "h", signed: false),
                                                                                                                                                                      mux(
                                                                                                                                                                        sig(:src, width: 32)[23],
                                                                                                                                                                        lit(23, width: 5, base: "h", signed: false),
                                                                                                                                                                        mux(
                                                                                                                                                                          sig(:src, width: 32)[24],
                                                                                                                                                                          lit(24, width: 5, base: "h", signed: false),
                                                                                                                                                                          mux(
                                                                                                                                                                            sig(:src, width: 32)[25],
                                                                                                                                                                            lit(25, width: 5, base: "h", signed: false),
                                                                                                                                                                            mux(
                                                                                                                                                                              sig(:src, width: 32)[26],
                                                                                                                                                                              lit(26, width: 5, base: "h", signed: false),
                                                                                                                                                                              mux(
                                                                                                                                                                                sig(:src, width: 32)[27],
                                                                                                                                                                                lit(27, width: 5, base: "h", signed: false),
                                                                                                                                                                                mux(
                                                                                                                                                                                  sig(:src, width: 32)[28],
                                                                                                                                                                                  lit(28, width: 5, base: "h", signed: false),
                                                                                                                                                                                  mux(
                                                                                                                                                                                    sig(:src, width: 32)[29],
                                                                                                                                                                                    lit(29, width: 5, base: "h", signed: false),
                                                                                                                                                                                    mux(
                                                                                                                                                                                      sig(:src, width: 32)[30],
                                                                                                                                                                                      lit(30, width: 5, base: "h", signed: false),
                                                                                                                                                                                      mux(
                                                                                                                                                                                        sig(:src, width: 32)[31],
                                                                                                                                                                                        lit(31, width: 5, base: "h", signed: false),
                                                                                                                                                                                        lit(0, width: 5, base: "h", signed: false)
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            )
                                                                                                                          )
                                                                                                                        ) >>
                                                                                                                        lit(0, width: nil, base: "d", signed: false)
                                                                                                                    ) &
                                                                                                                    (
                                                                                                                        (
                                                                                                                            lit(1, width: 32, base: "d") <<
                                                                                                                            (
                                                                                                                                  (
                                                                                                                                    lit(4, width: nil, base: "d", signed: false)
                                                                                                                                  ) -
                                                                                                                                  (
                                                                                                                                    lit(0, width: nil, base: "d", signed: false)
                                                                                                                                  ) +
                                                                                                                                lit(1, width: 32, base: "d")
                                                                                                                            )
                                                                                                                        ) -
                                                                                                                        lit(1, width: 32, base: "d")
                                                                                                                    )
                                                                                                                )
                                                                                                              ),
                                                                                                              mux(
                                                                                                                (
                                                                                                                    sig(:cond_297, width: 1) &
                                                                                                                    sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[117]
                                                                                                                ),
                                                                                                                lit(0, width: 27, base: "d", signed: false).concat(
                                                                                                                  (
                                                                                                                      (
                                                                                                                          mux(
                                                                                                                            sig(:e_src_ze, width: 32)[31],
                                                                                                                            lit(31, width: 5, base: "h", signed: false),
                                                                                                                            mux(
                                                                                                                              sig(:e_src_ze, width: 32)[30],
                                                                                                                              lit(30, width: 5, base: "h", signed: false),
                                                                                                                              mux(
                                                                                                                                sig(:e_src_ze, width: 32)[29],
                                                                                                                                lit(29, width: 5, base: "h", signed: false),
                                                                                                                                mux(
                                                                                                                                  sig(:e_src_ze, width: 32)[28],
                                                                                                                                  lit(28, width: 5, base: "h", signed: false),
                                                                                                                                  mux(
                                                                                                                                    sig(:e_src_ze, width: 32)[27],
                                                                                                                                    lit(27, width: 5, base: "h", signed: false),
                                                                                                                                    mux(
                                                                                                                                      sig(:e_src_ze, width: 32)[26],
                                                                                                                                      lit(26, width: 5, base: "h", signed: false),
                                                                                                                                      mux(
                                                                                                                                        sig(:e_src_ze, width: 32)[25],
                                                                                                                                        lit(25, width: 5, base: "h", signed: false),
                                                                                                                                        mux(
                                                                                                                                          sig(:e_src_ze, width: 32)[24],
                                                                                                                                          lit(24, width: 5, base: "h", signed: false),
                                                                                                                                          mux(
                                                                                                                                            sig(:e_src_ze, width: 32)[23],
                                                                                                                                            lit(23, width: 5, base: "h", signed: false),
                                                                                                                                            mux(
                                                                                                                                              sig(:e_src_ze, width: 32)[22],
                                                                                                                                              lit(22, width: 5, base: "h", signed: false),
                                                                                                                                              mux(
                                                                                                                                                sig(:e_src_ze, width: 32)[21],
                                                                                                                                                lit(21, width: 5, base: "h", signed: false),
                                                                                                                                                mux(
                                                                                                                                                  sig(:e_src_ze, width: 32)[20],
                                                                                                                                                  lit(20, width: 5, base: "h", signed: false),
                                                                                                                                                  mux(
                                                                                                                                                    sig(:e_src_ze, width: 32)[19],
                                                                                                                                                    lit(19, width: 5, base: "h", signed: false),
                                                                                                                                                    mux(
                                                                                                                                                      sig(:e_src_ze, width: 32)[18],
                                                                                                                                                      lit(18, width: 5, base: "h", signed: false),
                                                                                                                                                      mux(
                                                                                                                                                        sig(:e_src_ze, width: 32)[17],
                                                                                                                                                        lit(17, width: 5, base: "h", signed: false),
                                                                                                                                                        mux(
                                                                                                                                                          sig(:e_src_ze, width: 32)[16],
                                                                                                                                                          lit(16, width: 5, base: "h", signed: false),
                                                                                                                                                          mux(
                                                                                                                                                            sig(:e_src_ze, width: 32)[15],
                                                                                                                                                            lit(15, width: 5, base: "h", signed: false),
                                                                                                                                                            mux(
                                                                                                                                                              sig(:e_src_ze, width: 32)[14],
                                                                                                                                                              lit(14, width: 5, base: "h", signed: false),
                                                                                                                                                              mux(
                                                                                                                                                                sig(:e_src_ze, width: 32)[13],
                                                                                                                                                                lit(13, width: 5, base: "h", signed: false),
                                                                                                                                                                mux(
                                                                                                                                                                  sig(:e_src_ze, width: 32)[12],
                                                                                                                                                                  lit(12, width: 5, base: "h", signed: false),
                                                                                                                                                                  mux(
                                                                                                                                                                    sig(:e_src_ze, width: 32)[11],
                                                                                                                                                                    lit(11, width: 5, base: "h", signed: false),
                                                                                                                                                                    mux(
                                                                                                                                                                      sig(:e_src_ze, width: 32)[10],
                                                                                                                                                                      lit(10, width: 5, base: "h", signed: false),
                                                                                                                                                                      mux(
                                                                                                                                                                        sig(:e_src_ze, width: 32)[9],
                                                                                                                                                                        lit(9, width: 5, base: "h", signed: false),
                                                                                                                                                                        mux(
                                                                                                                                                                          sig(:e_src_ze, width: 32)[8],
                                                                                                                                                                          lit(8, width: 5, base: "h", signed: false),
                                                                                                                                                                          mux(
                                                                                                                                                                            sig(:e_src_ze, width: 32)[7],
                                                                                                                                                                            lit(7, width: 5, base: "h", signed: false),
                                                                                                                                                                            mux(
                                                                                                                                                                              sig(:e_src_ze, width: 32)[6],
                                                                                                                                                                              lit(6, width: 5, base: "h", signed: false),
                                                                                                                                                                              mux(
                                                                                                                                                                                sig(:e_src_ze, width: 32)[5],
                                                                                                                                                                                lit(5, width: 5, base: "h", signed: false),
                                                                                                                                                                                mux(
                                                                                                                                                                                  sig(:e_src_ze, width: 32)[4],
                                                                                                                                                                                  lit(4, width: 5, base: "h", signed: false),
                                                                                                                                                                                  mux(
                                                                                                                                                                                    sig(:e_src_ze, width: 32)[3],
                                                                                                                                                                                    lit(3, width: 5, base: "h", signed: false),
                                                                                                                                                                                    mux(
                                                                                                                                                                                      sig(:e_src_ze, width: 32)[2],
                                                                                                                                                                                      lit(2, width: 5, base: "h", signed: false),
                                                                                                                                                                                      mux(
                                                                                                                                                                                        sig(:e_src_ze, width: 32)[1],
                                                                                                                                                                                        lit(1, width: 5, base: "h", signed: false),
                                                                                                                                                                                        lit(0, width: 5, base: "h", signed: false)
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            )
                                                                                                                          ) >>
                                                                                                                          lit(0, width: nil, base: "d", signed: false)
                                                                                                                      ) &
                                                                                                                      (
                                                                                                                          (
                                                                                                                              lit(1, width: 32, base: "d") <<
                                                                                                                              (
                                                                                                                                    (
                                                                                                                                      lit(4, width: nil, base: "d", signed: false)
                                                                                                                                    ) -
                                                                                                                                    (
                                                                                                                                      lit(0, width: nil, base: "d", signed: false)
                                                                                                                                    ) +
                                                                                                                                  lit(1, width: 32, base: "d")
                                                                                                                              )
                                                                                                                          ) -
                                                                                                                          lit(1, width: 32, base: "d")
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
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_66,
    sig(:dst, width: 32)[15..8].concat(
      lit(0, width: 4, base: "d", signed: false).concat(
        sig(:dst, width: 32)[3..0]
      )
    )
  assign :exe_glob_param_3_set,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_189, width: 1) |
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_190, width: 1) |
            (
                sig(:__VdfgRegularize_h7a35cd6a_0_164, width: 1) |
                (
                    sig(:__VdfgRegularize_h7a35cd6a_0_231, width: 1) |
                    (
                        sig(:cond_121, width: 1) |
                        (
                            sig(:__VdfgRegularize_h7a35cd6a_0_230, width: 1) |
                            mux(
                              sig(:cond_185, width: 1),
                              sig(:exe_ready, width: 1),
                              (
                                  sig(:cond_204, width: 1) |
                                  sig(:cond_207, width: 1)
                              )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :exe_glob_descriptor_2_value,
    mux(
      sig(:cond_24, width: 1),
      sig(:glob_descriptor, width: 64),
      mux(
        sig(:__VdfgRegularize_h7a35cd6a_0_189, width: 1),
        sig(:glob_descriptor, width: 64),
        mux(
          sig(:__VdfgRegularize_h7a35cd6a_0_190, width: 1),
          sig(:glob_descriptor, width: 64),
          mux(
            sig(:__VdfgRegularize_h7a35cd6a_0_164, width: 1),
            sig(:glob_descriptor, width: 64),
            mux(
              sig(:__VdfgRegularize_h7a35cd6a_0_231, width: 1),
              sig(:glob_descriptor, width: 64),
              mux(
                sig(:cond_121, width: 1),
                sig(:glob_descriptor, width: 64),
                mux(
                  sig(:__VdfgRegularize_h7a35cd6a_0_230, width: 1),
                  sig(:glob_descriptor, width: 64),
                  mux(
                    sig(:cond_185, width: 1),
                    sig(:glob_descriptor, width: 64),
                    lit(0, width: 64, base: "h", signed: false)
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :offset_enter_last,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[53] &
        sig(:cond_67, width: 1)
    )
  assign :offset_new_stack,
    (
        sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[29] &
        sig(:__VdfgRegularize_h7a35cd6a_0_74, width: 1)
    )
  assign :offset_ret_imm,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_109, width: 1) &
        sig(:cond_186, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_7,
    (
      ~sig(:glob_descriptor, width: 64)[41]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_10,
    (
        (
            sig(:__VdfgRegularize_h7a35cd6a_0_6, width: 1) |
            sig(:__VdfgRegularize_h7a35cd6a_0_248, width: 1)
        ) &
        sig(:exe_privilege_not_accepted, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_20,
    (
        sig(:glob_descriptor, width: 64)[46..45] !=
        sig(:glob_param_1, width: 32)[1..0]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_67,
    (
        sig(:exe_branch_eip, width: 32) >
        sig(:cs_limit, width: 32)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_82,
    (
      ~sig(:cond_20, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_83,
    (
        sig(:glob_descriptor, width: 64)[46..45] <
        sig(:cpl, width: 2)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_85,
    (
        lit(0, width: 14, base: "h", signed: false) ==
        sig(:glob_param_1, width: 32)[15..2]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_89,
    (
        lit(1, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_90,
    (
        lit(9, width: 4, base: "h", signed: false) ==
        sig(:glob_descriptor, width: 64)[43..40]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_91,
    (
        sig(:glob_descriptor, width: 64)[46..45] !=
        sig(:cpl, width: 2)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_92,
    (
        sig(:glob_descriptor, width: 64)[46..45] >
        sig(:cpl, width: 2)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_93,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_2, width: 1) &
        sig(:__VdfgRegularize_h7a35cd6a_0_92, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_96,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:glob_param_2, width: 32)[1..0]
    )
  assign :__VdfgRegularize_h7a35cd6a_0_98,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_4, width: 1) |
        sig(:__VdfgRegularize_h7a35cd6a_0_6, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_241,
    (
        sig(:cond_267, width: 1) &
        (
            sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[102] &
            sig(:cond_188, width: 1)
        )
    )
  assign :__VdfgRegularize_h7a35cd6a_0_123,
    (
      ~sig(:cond_51, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_245,
    lit(0, width: 5, base: "d", signed: false).concat(
      sig(:exc_vector, width: 8)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_244,
    (
        sig(:__VdfgRegularize_h7a35cd6a_0_85, width: 1) |
        sig(:__VdfgRegularize_h7a35cd6a_0_98, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_165,
    (
      ~sig(:cond_44, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_167,
    (
      ~sig(:exe_operand_32bit, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_220,
    (
        sig(:cond_267, width: 1) &
        sig(:cond_270, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_219,
    (
        sig(:cond_267, width: 1) &
        sig(:cond_273, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_199,
    (
      ~sig(:cond_197, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_0_208,
    (
      ~sig(:cond_218, width: 1)
    )
  assign :__VdfgRegularize_h7a35cd6a_1_0,
    (
        sig(:cond_9, width: 1) &
        sig(:cond_54, width: 1)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_buffer_shift, width: 1)) do
        assign(
          :exe_buffer_shifted,
          sig(:exe_buffer_shifted, width: 464)[431..0].concat(
            sig(:exe_buffer, width: 32)
          ),
          kind: :nonblocking
        )
        elsif_block(sig(:exe_buffer_shift_word, width: 1)) do
          assign(
            :exe_buffer_shifted,
            sig(:exe_buffer_shifted, width: 464)[447..0].concat(
              sig(:exe_buffer, width: 32)[15..0]
            ),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :exe_buffer_shifted,
          lit(0, width: 464, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_1,
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

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :e_invd_code_done,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :e_invd_code_done,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:invdcode_done, width: 1)) do
          assign(
            :e_invd_code_done,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :e_invd_code_done,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :e_invd_data_done,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :e_invd_data_done,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:invddata_done, width: 1)) do
          assign(
            :e_invd_data_done,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :e_invd_data_done,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :e_wbinvd_code_done,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :e_wbinvd_code_done,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:invdcode_done, width: 1)) do
          assign(
            :e_wbinvd_code_done,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :e_wbinvd_code_done,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :e_wbinvd_data_done,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :e_wbinvd_data_done,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:wbinvddata_done, width: 1)) do
          assign(
            :e_wbinvd_data_done,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :e_wbinvd_data_done,
          lit(0, width: 1, base: "h", signed: false),
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
    assign(
      :exe_buffer,
      mux(
        sig(:rst_n, width: 1),
        sig(:exe_buffer_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :initial_block_7,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :__VdfgBinToOneHot_Pre_ha6c45459_0_0,
      lit(0, width: 7, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :combinational_logic_8,
    sensitivity: [
    ],
    clocked: false,
    initial: false do
    assign(
      sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[sig(:__VdfgBinToOneHot_Pre_ha6c45459_0_0, width: 7)],
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      sig(:__VdfgBinToOneHot_Tab_ha6c45459_0_0, width: 128)[sig(:exe_cmd, width: 7)],
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
    assign(
      :__VdfgBinToOneHot_Pre_ha6c45459_0_0,
      sig(:exe_cmd, width: 7),
      kind: :blocking
    )
  end

  # Instances

  instance :exe_condition_inst, "condition",
    ports: {
      index: sig(:exe_decoder, width: 40)[3..0],
      condition: :exe_condition
    }

end
