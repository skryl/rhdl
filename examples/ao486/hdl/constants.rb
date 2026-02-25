# ao486 Constants
# Ported from: rtl/ao486/defines.v, rtl/ao486/startup_default.v, rtl/ao486/autogen/defines.v

module RHDL
  module Examples
    module AO486
      module Constants
        # Exception vectors
        EXCEPTION_DE = 0   # Divide by zero
        EXCEPTION_DB = 1   # Debug
        EXCEPTION_BP = 3   # Breakpoint
        EXCEPTION_OF = 4   # Overflow
        EXCEPTION_BR = 5   # Bounds
        EXCEPTION_UD = 6   # Undefined opcode
        EXCEPTION_NM = 7   # No math coprocessor
        EXCEPTION_DF = 8   # Double fault
        EXCEPTION_TS = 10  # Invalid TSS
        EXCEPTION_NP = 11  # Segment not present
        EXCEPTION_SS = 12  # Stack-segment fault
        EXCEPTION_GP = 13  # General protection
        EXCEPTION_PF = 14  # Page fault
        EXCEPTION_AC = 17  # Alignment check
        EXCEPTION_MC = 18  # Machine check

        # Prefetch fault codes
        PREFETCH_GP_FAULT  = 15
        PREFETCH_PF_FAULT  = 14
        PREFETCH_MIN_FAULT = 9

        # CPUID
        CPUID_MODEL_FAMILY_STEPPING = 0x0000_045B

        # Microcode parameter flags
        MC_PARAM_1_FLAG_NO_WRITE             = 1
        MC_PARAM_1_FLAG_NO_WRITE_BIT         = 19
        MC_PARAM_1_FLAG_CPL_FROM_PARAM_3     = 3
        MC_PARAM_1_FLAG_CPL_FROM_PARAM_3_BIT = 20
        MC_PARAM_1_FLAG_NP_NOT_SS            = 7
        MC_PARAM_1_FLAG_NP_NOT_SS_BIT        = 21

        # EFLAGS bit positions
        EFLAGS_BIT_VM = 17

        # Descriptor bit positions (within 64-bit descriptor)
        DESC_BIT_G         = 55
        DESC_BIT_D_B       = 54
        DESC_BIT_P         = 47
        DESC_BIT_SEG       = 44
        DESC_BITS_TYPE_HI  = 43
        DESC_BITS_TYPE_LO  = 40
        DESC_BITS_DPL_HI   = 46
        DESC_BITS_DPL_LO   = 45
        DESC_BIT_TYPE_BIT_0 = 40

        # Descriptor masks (64-bit)
        DESC_MASK_G         = 0x0080_0000_0000_0000
        DESC_MASK_D_B       = 0x0040_0000_0000_0000
        DESC_MASK_L         = 0x0020_0000_0000_0000
        DESC_MASK_AVL       = 0x0010_0000_0000_0000
        DESC_MASK_LIMIT     = 0x000F_0000_0000_FFFF
        DESC_MASK_P         = 0x0000_8000_0000_0000
        DESC_MASK_DPL       = 0x0000_6000_0000_0000
        DESC_MASK_SEG       = 0x0000_1000_0000_0000
        DESC_MASK_TYPE      = 0x0000_0F00_0000_0000
        DESC_MASK_DATA_RWA  = 0x0000_0300_0000_0000

        # Descriptor type helpers (operate on 64-bit descriptor value)
        def self.desc_is_code?(val)             (val >> 43) & 1 == 1; end
        def self.desc_is_data?(val)             (val >> 43) & 1 == 0; end
        def self.desc_is_data_ro?(val)          !desc_is_code?(val) && ((val >> 41) & 1 == 0); end
        def self.desc_is_data_rw?(val)          !desc_is_code?(val) && ((val >> 41) & 1 == 1); end
        def self.desc_is_code_eo?(val)          desc_is_code?(val) && ((val >> 41) & 1 == 0); end
        def self.desc_is_code_non_conforming?(val) desc_is_code?(val) && ((val >> 42) & 1 == 0); end
        def self.desc_is_not_accessed?(val)     (val >> 40) & 1 == 0; end
        def self.desc_is_accessed?(val)         (val >> 40) & 1 == 1; end
        def self.desc_is_code_conforming?(val)  desc_is_code?(val) && ((val >> 42) & 1 == 1); end

        # Selector field helpers
        def self.selector_rpl(val)   val & 0x3; end
        def self.selector_ti?(val)   (val >> 2) & 1 == 1; end
        def self.selector_for_code(val) val & 0xFFFC; end

        # Debug register bits
        DR7_BIT_GD = 13

        # Segment register indices
        SEGMENT_ES  = 0
        SEGMENT_CS  = 1
        SEGMENT_SS  = 2
        SEGMENT_DS  = 3
        SEGMENT_FS  = 4
        SEGMENT_GS  = 5
        SEGMENT_LDT = 6
        SEGMENT_TR  = 7

        # Descriptor types
        DESC_TSS_AVAIL_386      = 0x9
        DESC_TSS_BUSY_386       = 0xB
        DESC_TSS_AVAIL_286      = 0x1
        DESC_TSS_BUSY_286       = 0x3
        DESC_INTERRUPT_GATE_386 = 0xE
        DESC_INTERRUPT_GATE_286 = 0x6
        DESC_TRAP_GATE_386      = 0xF
        DESC_TRAP_GATE_286      = 0x7
        DESC_CALL_GATE_386      = 0xC
        DESC_CALL_GATE_286      = 0x4
        DESC_LDT                = 0x2
        DESC_TASK_GATE           = 0x5

        # Mutex bits
        MUTEX_EAX_BIT    = 0
        MUTEX_ECX_BIT    = 1
        MUTEX_EDX_BIT    = 2
        MUTEX_EBX_BIT    = 3
        MUTEX_ESP_BIT    = 4
        MUTEX_EBP_BIT    = 5
        MUTEX_ESI_BIT    = 6
        MUTEX_EDI_BIT    = 7
        MUTEX_EFLAGS_BIT = 8
        MUTEX_MEMORY_BIT = 9
        MUTEX_ACTIVE_BIT = 10
        MUTEX_IO_BIT     = 11

        # Arithmetic sub-operation codes
        ARITH_VALID = 8
        ARITH_ADD   = 0
        ARITH_OR    = 1
        ARITH_ADC   = 2
        ARITH_SBB   = 3
        ARITH_AND   = 4
        ARITH_SUB   = 5
        ARITH_XOR   = 6
        ARITH_CMP   = 7

        # Task switch sources
        TASK_SWITCH_FROM_IRET = 0
        TASK_SWITCH_FROM_INT  = 1
        TASK_SWITCH_FROM_CALL = 2
        TASK_SWITCH_FROM_JUMP = 3

        # -------------------------------------------------------------------
        # Command IDs (from autogen/defines.v)
        # -------------------------------------------------------------------
        CMD_NULL          = 0
        CMD_XADD          = 1
        CMD_JCXZ          = 2
        CMD_CALL          = 3
        CMD_CALL_2        = 4
        CMD_CALL_3        = 5
        CMD_PUSH_MOV_SEG  = 6
        CMD_NEG           = 7
        CMD_Jcc           = 8
        CMD_INVD          = 9
        CMD_INVLPG        = 10
        CMD_io_allow      = 11
        CMD_HLT           = 12
        CMD_SCAS          = 13
        CMD_INC_DEC       = 14
        CMD_RET_near      = 15
        CMD_ARPL          = 16
        CMD_BSWAP         = 17
        CMD_LxS           = 18
        CMD_MOV_to_seg    = 19
        CMD_LLDT          = 20
        CMD_LTR           = 21
        CMD_CLC           = 22
        CMD_CLD           = 23
        CMD_CMC           = 24
        CMD_STC           = 25
        CMD_STD           = 26
        CMD_SAHF          = 27
        CMD_int           = 28
        CMD_int_2         = 29
        CMD_int_3         = 30
        CMD_AAD           = 31
        CMD_AAM           = 32
        CMD_load_seg      = 33
        CMD_POP_seg       = 34
        CMD_IRET          = 35
        CMD_BT            = 36
        CMD_BTx           = 36
        CMD_BTS           = 37
        CMD_BTR           = 38
        CMD_BTC           = 39
        CMD_IRET_2        = 40
        CMD_POP           = 41
        CMD_DIV           = 42
        CMD_IDIV          = 43
        CMD_Shift         = 44
        CMD_CMPS          = 45
        CMD_control_reg   = 46
        CMD_LGDT          = 47
        CMD_LIDT          = 48
        CMD_PUSHA         = 49
        CMD_fpu           = 50
        CMD_SETcc         = 51
        CMD_CMPXCHG       = 52
        CMD_ENTER         = 53
        CMD_IMUL          = 54
        CMD_LEAVE         = 55
        CMD_SHxD          = 56
        CMD_SHLD          = 56
        CMD_SHRD          = 57
        CMD_WBINVD        = 58
        CMD_MUL           = 59
        CMD_LOOP          = 60
        CMD_TEST          = 61
        CMD_CLTS          = 62
        CMD_RET_far       = 63
        CMD_Arith         = 64
        CMD_ADD           = 64
        CMD_OR            = 65
        CMD_ADC           = 66
        CMD_SBB           = 67
        CMD_AND           = 68
        CMD_SUB           = 69
        CMD_XOR           = 70
        CMD_CMP           = 71
        CMD_LODS          = 72
        CMD_XCHG          = 73
        CMD_PUSH          = 74
        CMD_INT_INTO      = 75
        CMD_CPUID         = 76
        CMD_IN            = 77
        CMD_NOT           = 78
        CMD_LAR           = 79
        CMD_LSL           = 80
        CMD_VERR          = 81
        CMD_VERW          = 82
        CMD_STOS          = 83
        CMD_INS           = 84
        CMD_OUTS          = 85
        CMD_PUSHF         = 86
        CMD_JMP           = 87
        CMD_JMP_2         = 88
        CMD_OUT           = 89
        CMD_MOV           = 90
        CMD_LAHF          = 91
        CMD_CBW           = 92
        CMD_CWD           = 93
        CMD_POPF          = 94
        CMD_CLI           = 95
        CMD_STI           = 96
        CMD_BOUND         = 97
        CMD_SALC          = 98
        CMD_task_switch   = 99
        CMD_task_switch_2 = 100
        CMD_task_switch_3 = 101
        CMD_task_switch_4 = 102
        CMD_LEA           = 103
        CMD_SGDT          = 104
        CMD_SIDT          = 105
        CMD_MOVS          = 106
        CMD_MOVZX         = 107
        CMD_MOVSX         = 108
        CMD_POPA          = 109
        CMD_debug_reg     = 110
        CMD_XLAT          = 111
        CMD_AAA           = 112
        CMD_AAS           = 113
        CMD_DAA           = 114
        CMD_DAS           = 115
        CMD_BSF           = 116
        CMD_BSx           = 116
        CMD_BSR           = 117

        # -------------------------------------------------------------------
        # CMDEX_* execution phase constants (from autogen/defines.v)
        # -------------------------------------------------------------------
        CMDEX_NULL = 0

        CMDEX_Arith_immediate     = 0
        CMDEX_Arith_modregrm      = 1
        CMDEX_Arith_modregrm_imm  = 2

        CMDEX_MOV_immediate       = 0
        CMDEX_MOV_modregrm        = 1
        CMDEX_MOV_modregrm_imm    = 2
        CMDEX_MOV_memoffset       = 3

        CMDEX_TEST_immediate      = 0
        CMDEX_TEST_modregrm       = 1
        CMDEX_TEST_modregrm_imm   = 2

        CMDEX_Shift_implicit      = 0
        CMDEX_Shift_modregrm      = 1
        CMDEX_Shift_modregrm_imm  = 2

        CMDEX_SHxD_implicit       = 0
        CMDEX_SHxD_modregrm_imm   = 1

        CMDEX_INC_DEC_implicit           = 0
        CMDEX_INC_DEC_decrement_implicit = 1
        CMDEX_INC_DEC_modregrm           = 2
        CMDEX_INC_DEC_increment_modregrm = 2
        CMDEX_INC_DEC_decrement_modregrm = 3

        CMDEX_PUSH_implicit     = 0
        CMDEX_PUSH_immediate    = 2
        CMDEX_PUSH_immediate_se = 1
        CMDEX_PUSH_modregrm     = 3

        CMDEX_POP_implicit          = 0
        CMDEX_POP_modregrm_STEP_0   = 1
        CMDEX_POP_modregrm_STEP_1   = 2

        CMDEX_PUSH_MOV_SEG_implicit    = 0
        CMDEX_PUSH_MOV_SEG_implicit_ES = 0
        CMDEX_PUSH_MOV_SEG_implicit_CS = 1
        CMDEX_PUSH_MOV_SEG_implicit_SS = 2
        CMDEX_PUSH_MOV_SEG_implicit_DS = 3
        CMDEX_PUSH_MOV_SEG_implicit_FS = 4
        CMDEX_PUSH_MOV_SEG_implicit_GS = 5
        CMDEX_PUSH_MOV_SEG_implicit_LDT = 6
        CMDEX_PUSH_MOV_SEG_implicit_TR  = 7
        CMDEX_PUSH_MOV_SEG_modregrm    = 8
        CMDEX_PUSH_MOV_SEG_modregrm_ES = 8
        CMDEX_PUSH_MOV_SEG_modregrm_CS = 9
        CMDEX_PUSH_MOV_SEG_modregrm_SS = 10
        CMDEX_PUSH_MOV_SEG_modregrm_DS = 11
        CMDEX_PUSH_MOV_SEG_modregrm_FS = 12
        CMDEX_PUSH_MOV_SEG_modregrm_GS = 13
        CMDEX_PUSH_MOV_SEG_modregrm_LDT = 14
        CMDEX_PUSH_MOV_SEG_modregrm_TR  = 15

        CMDEX_BTx_modregrm_imm = 0
        CMDEX_BTx_modregrm     = 1

        CMDEX_XCHG_implicit       = 0
        CMDEX_XCHG_modregrm       = 1
        CMDEX_XCHG_modregrm_LAST  = 2

        CMDEX_XADD_FIRST = 0
        CMDEX_XADD_LAST  = 1

        CMDEX_IMUL_modregrm     = 0
        CMDEX_IMUL_modregrm_imm = 1

        CMDEX_RET_near      = 0
        CMDEX_RET_near_imm  = 1
        CMDEX_RET_near_LAST = 2

        CMDEX_JMP_Ev_STEP_0     = 0
        CMDEX_JMP_Jv_STEP_0     = 1
        CMDEX_JMP_Ep_STEP_0     = 2
        CMDEX_JMP_Ap_STEP_0     = 3
        CMDEX_JMP_Ev_Jv_STEP_1  = 4
        CMDEX_JMP_Ep_STEP_1     = 5
        CMDEX_JMP_Ap_STEP_1     = 6

        CMDEX_JMP_real_v8086_STEP_0     = 7
        CMDEX_JMP_real_v8086_STEP_1     = 8
        CMDEX_JMP_protected_STEP_0      = 9
        CMDEX_JMP_protected_STEP_1      = 10
        CMDEX_JMP_protected_seg_STEP_0  = 11
        CMDEX_JMP_protected_seg_STEP_1  = 12
        CMDEX_JMP_task_switch_STEP_0    = 13
        CMDEX_JMP_task_gate_STEP_0      = 14
        CMDEX_JMP_task_gate_STEP_1      = 15

        CMDEX_JMP_2_call_gate_STEP_0 = 0
        CMDEX_JMP_2_call_gate_STEP_1 = 1
        CMDEX_JMP_2_call_gate_STEP_2 = 2
        CMDEX_JMP_2_call_gate_STEP_3 = 3

        CMDEX_CALL_Ev_STEP_0     = 0
        CMDEX_CALL_Jv_STEP_0     = 1
        CMDEX_CALL_Ep_STEP_0     = 2
        CMDEX_CALL_Ap_STEP_0     = 3
        CMDEX_CALL_Ev_Jv_STEP_1  = 4
        CMDEX_CALL_Ep_STEP_1     = 5
        CMDEX_CALL_Ap_STEP_1     = 6

        CMDEX_CALL_real_v8086_STEP_0    = 7
        CMDEX_CALL_real_v8086_STEP_1    = 8
        CMDEX_CALL_real_v8086_STEP_2    = 9
        CMDEX_CALL_real_v8086_STEP_3    = 10
        CMDEX_CALL_protected_STEP_0     = 11
        CMDEX_CALL_protected_STEP_1     = 12
        CMDEX_CALL_protected_seg_STEP_0 = 13
        CMDEX_CALL_protected_seg_STEP_1 = 14
        CMDEX_CALL_protected_seg_STEP_2 = 15

        CMDEX_CALL_2_task_switch_STEP_0      = 2
        CMDEX_CALL_2_task_gate_STEP_0        = 3
        CMDEX_CALL_2_task_gate_STEP_1        = 4
        CMDEX_CALL_2_call_gate_STEP_0        = 5
        CMDEX_CALL_2_call_gate_STEP_1        = 6
        CMDEX_CALL_2_call_gate_STEP_2        = 7
        CMDEX_CALL_2_call_gate_same_STEP_0   = 8
        CMDEX_CALL_2_call_gate_same_STEP_1   = 9
        CMDEX_CALL_2_call_gate_same_STEP_2   = 10
        CMDEX_CALL_2_call_gate_same_STEP_3   = 11
        CMDEX_CALL_2_call_gate_more_STEP_0   = 12
        CMDEX_CALL_2_call_gate_more_STEP_1   = 13
        CMDEX_CALL_2_call_gate_more_STEP_2   = 14
        CMDEX_CALL_2_call_gate_more_STEP_3   = 15
        CMDEX_CALL_2_protected_seg_STEP_3    = 0
        CMDEX_CALL_2_protected_seg_STEP_4    = 1

        CMDEX_CALL_3_call_gate_more_STEP_4  = 0
        CMDEX_CALL_3_call_gate_more_STEP_5  = 1
        CMDEX_CALL_3_call_gate_more_STEP_6  = 2
        CMDEX_CALL_3_call_gate_more_STEP_7  = 3
        CMDEX_CALL_3_call_gate_more_STEP_8  = 4
        CMDEX_CALL_3_call_gate_more_STEP_9  = 5
        CMDEX_CALL_3_call_gate_more_STEP_10 = 6

        CMDEX_RET_far_STEP_1 = 1
        CMDEX_RET_far_STEP_2 = 2
        CMDEX_RET_far_real_STEP_3    = 3
        CMDEX_RET_far_same_STEP_3    = 4
        CMDEX_RET_far_same_STEP_4    = 5
        CMDEX_RET_far_outer_STEP_3   = 6
        CMDEX_RET_far_outer_STEP_4   = 7
        CMDEX_RET_far_outer_STEP_5   = 8
        CMDEX_RET_far_outer_STEP_6   = 9
        CMDEX_RET_far_outer_STEP_7   = 10

        CMDEX_IRET_real_v86_STEP_0         = 0
        CMDEX_IRET_real_v86_STEP_1         = 1
        CMDEX_IRET_real_v86_STEP_2         = 2
        CMDEX_IRET_real_v86_STEP_3         = 3
        CMDEX_IRET_protected_STEP_0        = 4
        CMDEX_IRET_task_switch_STEP_0      = 5
        CMDEX_IRET_task_switch_STEP_1      = 6
        CMDEX_IRET_protected_STEP_1        = 7
        CMDEX_IRET_protected_STEP_2        = 8
        CMDEX_IRET_protected_STEP_3        = 9
        CMDEX_IRET_protected_to_v86_STEP_0 = 10
        CMDEX_IRET_protected_to_v86_STEP_1 = 11
        CMDEX_IRET_protected_to_v86_STEP_2 = 12
        CMDEX_IRET_protected_to_v86_STEP_3 = 13
        CMDEX_IRET_protected_to_v86_STEP_4 = 14
        CMDEX_IRET_protected_to_v86_STEP_5 = 15

        CMDEX_IRET_2_idle                       = 0
        CMDEX_IRET_2_protected_same_STEP_0      = 1
        CMDEX_IRET_2_protected_same_STEP_1      = 2
        CMDEX_IRET_2_protected_outer_STEP_0     = 3
        CMDEX_IRET_2_protected_outer_STEP_1     = 4
        CMDEX_IRET_2_protected_outer_STEP_2     = 5
        CMDEX_IRET_2_protected_outer_STEP_3     = 6
        CMDEX_IRET_2_protected_outer_STEP_4     = 7
        CMDEX_IRET_2_protected_outer_STEP_5     = 8
        CMDEX_IRET_2_protected_outer_STEP_6     = 9
        CMDEX_IRET_2_protected_to_v86_STEP_6    = 10

        CMDEX_PUSHA_STEP_0 = 0
        CMDEX_PUSHA_STEP_1 = 1
        CMDEX_PUSHA_STEP_2 = 2
        CMDEX_PUSHA_STEP_3 = 3
        CMDEX_PUSHA_STEP_4 = 4
        CMDEX_PUSHA_STEP_5 = 5
        CMDEX_PUSHA_STEP_6 = 6
        CMDEX_PUSHA_STEP_7 = 7

        CMDEX_POPA_STEP_0 = 0
        CMDEX_POPA_STEP_1 = 1
        CMDEX_POPA_STEP_2 = 2
        CMDEX_POPA_STEP_3 = 3
        CMDEX_POPA_STEP_4 = 4
        CMDEX_POPA_STEP_5 = 5
        CMDEX_POPA_STEP_6 = 6
        CMDEX_POPA_STEP_7 = 7

        CMDEX_POPF_STEP_0 = 0
        CMDEX_POPF_STEP_1 = 1

        CMDEX_ENTER_FIRST = 0
        CMDEX_ENTER_LAST  = 1
        CMDEX_ENTER_PUSH  = 2
        CMDEX_ENTER_LOOP  = 3

        CMDEX_LOOP_NE = 0
        CMDEX_LOOP_E  = 1
        CMDEX_LOOP    = 2

        CMDEX_MOVS_STEP_0  = 0
        CMDEX_LODS_STEP_0  = 0
        CMDEX_STOS_STEP_0  = 0
        CMDEX_CMPS_FIRST   = 0
        CMDEX_CMPS_LAST    = 1
        CMDEX_SCAS_STEP_0  = 0

        CMDEX_INS_real_1      = 0
        CMDEX_INS_real_2      = 1
        CMDEX_INS_protected_1 = 2
        CMDEX_INS_protected_2 = 3
        CMDEX_OUTS_first      = 0
        CMDEX_OUTS_protected  = 1

        CMDEX_IN_imm       = 0
        CMDEX_IN_dx        = 1
        CMDEX_IN_protected = 2
        CMDEX_IN_idle      = 3
        CMDEX_OUT_imm       = 0
        CMDEX_OUT_dx        = 1
        CMDEX_OUT_protected = 2
        CMDEX_OUT_idle      = 3

        CMDEX_INT_INTO_INT_STEP_0   = 0
        CMDEX_INT_INTO_INT3_STEP_0  = 3
        CMDEX_INT_INTO_INT1_STEP_0  = 3
        CMDEX_INT_INTO_INTO_STEP_0  = 2

        CMDEX_int_STEP_0 = 0
        CMDEX_int_STEP_1 = 1
        CMDEX_int_real_STEP_0 = 2
        CMDEX_int_real_STEP_1 = 3
        CMDEX_int_real_STEP_2 = 4
        CMDEX_int_real_STEP_3 = 5
        CMDEX_int_real_STEP_4 = 6
        CMDEX_int_real_STEP_5 = 7
        CMDEX_int_protected_STEP_0 = 8
        CMDEX_int_protected_STEP_1 = 9
        CMDEX_int_protected_STEP_2 = 10
        CMDEX_int_task_gate_STEP_0 = 11
        CMDEX_int_task_gate_STEP_1 = 12
        CMDEX_int_int_trap_gate_STEP_0 = 13
        CMDEX_int_int_trap_gate_STEP_1 = 14
        CMDEX_int_int_trap_gate_STEP_2 = 15

        CMDEX_int_2_int_trap_gate_same_STEP_0 = 0
        CMDEX_int_2_int_trap_gate_same_STEP_1 = 1
        CMDEX_int_2_int_trap_gate_same_STEP_2 = 2
        CMDEX_int_2_int_trap_gate_same_STEP_3 = 3
        CMDEX_int_2_int_trap_gate_same_STEP_4 = 4
        CMDEX_int_2_int_trap_gate_same_STEP_5 = 5
        CMDEX_int_2_int_trap_gate_more_STEP_0 = 6
        CMDEX_int_2_int_trap_gate_more_STEP_1 = 7
        CMDEX_int_2_int_trap_gate_more_STEP_2 = 8
        CMDEX_int_2_int_trap_gate_more_STEP_3 = 9
        CMDEX_int_2_int_trap_gate_more_STEP_4 = 10
        CMDEX_int_2_int_trap_gate_more_STEP_5 = 11
        CMDEX_int_2_int_trap_gate_more_STEP_6 = 12
        CMDEX_int_2_int_trap_gate_more_STEP_7 = 13
        CMDEX_int_2_int_trap_gate_more_STEP_8 = 14
        CMDEX_int_2_int_trap_gate_more_STEP_9 = 15

        CMDEX_int_3_int_trap_gate_more_STEP_0 = 0
        CMDEX_int_3_int_trap_gate_more_STEP_1 = 1
        CMDEX_int_3_int_trap_gate_more_STEP_2 = 2
        CMDEX_int_3_int_trap_gate_more_STEP_3 = 3
        CMDEX_int_3_int_trap_gate_more_STEP_4 = 4
        CMDEX_int_3_int_trap_gate_more_STEP_5 = 5
        CMDEX_int_3_int_trap_gate_more_STEP_6 = 6

        CMDEX_task_switch_STEP_1  = 1
        CMDEX_task_switch_STEP_2  = 2
        CMDEX_task_switch_STEP_3  = 3
        CMDEX_task_switch_STEP_4  = 4
        CMDEX_task_switch_STEP_5  = 5
        CMDEX_task_switch_STEP_6  = 6
        CMDEX_task_switch_STEP_7  = 7
        CMDEX_task_switch_STEP_8  = 8
        CMDEX_task_switch_STEP_9  = 9
        CMDEX_task_switch_STEP_10 = 10
        CMDEX_task_switch_STEP_11 = 11
        CMDEX_task_switch_STEP_12 = 12
        CMDEX_task_switch_STEP_13 = 13
        CMDEX_task_switch_STEP_14 = 14

        CMDEX_task_switch_2_STEP_0  = 0
        CMDEX_task_switch_2_STEP_7  = 7
        CMDEX_task_switch_2_STEP_11 = 11
        CMDEX_task_switch_2_STEP_13 = 13

        CMDEX_task_switch_3_STEP_0  = 0
        CMDEX_task_switch_3_STEP_7  = 7
        CMDEX_task_switch_3_STEP_8  = 8
        CMDEX_task_switch_3_STEP_12 = 12
        CMDEX_task_switch_3_STEP_15 = 15

        CMDEX_task_switch_4_STEP_0  = 0
        CMDEX_task_switch_4_STEP_1  = 1
        CMDEX_task_switch_4_STEP_2  = 2
        CMDEX_task_switch_4_STEP_3  = 3
        CMDEX_task_switch_4_STEP_4  = 4
        CMDEX_task_switch_4_STEP_5  = 5
        CMDEX_task_switch_4_STEP_6  = 6
        CMDEX_task_switch_4_STEP_7  = 7
        CMDEX_task_switch_4_STEP_8  = 8
        CMDEX_task_switch_4_STEP_9  = 9
        CMDEX_task_switch_4_STEP_10 = 10

        CMDEX_load_seg_STEP_1 = 0
        CMDEX_load_seg_STEP_2 = 1
        CMDEX_MOV_to_seg_LLDT_LTR_STEP_1    = 0
        CMDEX_MOV_to_seg_LLDT_LTR_STEP_LAST = 1
        CMDEX_POP_seg_STEP_1    = 0
        CMDEX_POP_seg_STEP_LAST = 1

        CMDEX_LAR_LSL_VERR_VERW_STEP_1    = 0
        CMDEX_LAR_LSL_VERR_VERW_STEP_2    = 1
        CMDEX_LAR_LSL_VERR_VERW_STEP_LAST = 2

        CMDEX_BOUND_STEP_FIRST = 0
        CMDEX_BOUND_STEP_LAST  = 1

        CMDEX_LxS_STEP_1    = 0
        CMDEX_LxS_STEP_2    = 1
        CMDEX_LxS_STEP_3    = 2
        CMDEX_LxS_STEP_LAST = 3

        CMDEX_control_reg_SMSW_STEP_0     = 0
        CMDEX_control_reg_LMSW_STEP_0     = 1
        CMDEX_control_reg_LMSW_STEP_1     = 2
        CMDEX_control_reg_MOV_store_STEP_0 = 3
        CMDEX_control_reg_MOV_load_STEP_0  = 4
        CMDEX_control_reg_MOV_load_STEP_1  = 5

        CMDEX_debug_reg_MOV_store_STEP_0 = 0
        CMDEX_debug_reg_MOV_load_STEP_0  = 1
        CMDEX_debug_reg_MOV_load_STEP_1  = 2

        CMDEX_SGDT_SIDT_STEP_1 = 0
        CMDEX_SGDT_SIDT_STEP_2 = 1
        CMDEX_LGDT_LIDT_STEP_1    = 8
        CMDEX_LGDT_LIDT_STEP_2    = 9
        CMDEX_LGDT_LIDT_STEP_LAST = 10

        CMDEX_INVD_STEP_0 = 0
        CMDEX_INVD_STEP_1 = 1
        CMDEX_INVD_STEP_2 = 2
        CMDEX_WBINVD_STEP_0 = 0
        CMDEX_WBINVD_STEP_1 = 1
        CMDEX_WBINVD_STEP_2 = 2

        CMDEX_INVLPG_STEP_0 = 0
        CMDEX_INVLPG_STEP_1 = 1
        CMDEX_INVLPG_STEP_2 = 2

        CMDEX_CLTS_STEP_FIRST = 0
        CMDEX_CLTS_STEP_LAST  = 1

        CMDEX_io_allow_1 = 0
        CMDEX_io_allow_2 = 1

        CMDEX_CPUID_STEP_LAST = 0
        CMDEX_SALC_STEP_0     = 0
        CMDEX_HLT_STEP_0      = 0
        CMDEX_WAIT_STEP_0     = 0
        CMDEX_ESC_STEP_0      = 1

        TASK_SWITCH_SOURCE_BITS_HI = 17
        TASK_SWITCH_SOURCE_BITS_LO = 16

        # -------------------------------------------------------------------
        # Startup register values (from startup_default.v)
        # -------------------------------------------------------------------
        STARTUP_EAX = 0
        STARTUP_EBX = 0
        STARTUP_ECX = 0
        STARTUP_EDX = CPUID_MODEL_FAMILY_STEPPING
        STARTUP_EBP = 0
        STARTUP_ESP = 0
        STARTUP_ESI = 0
        STARTUP_EDI = 0

        STARTUP_EIP = 0x0000_FFF0

        STARTUP_CR0_PE = false
        STARTUP_CR0_MP = false
        STARTUP_CR0_EM = false
        STARTUP_CR0_TS = false
        STARTUP_CR0_NE = false
        STARTUP_CR0_WP = false
        STARTUP_CR0_AM = false
        STARTUP_CR0_NW = true
        STARTUP_CR0_CD = true
        STARTUP_CR0_PG = false

        STARTUP_CR2 = 0
        STARTUP_CR3 = 0

        STARTUP_CFLAG  = 0
        STARTUP_PFLAG  = 0
        STARTUP_AFLAG  = 0
        STARTUP_ZFLAG  = 0
        STARTUP_SFLAG  = 0
        STARTUP_OFLAG  = 0
        STARTUP_TFLAG  = 0
        STARTUP_IFLAG  = 0
        STARTUP_DFLAG  = 0
        STARTUP_IOPL   = 0
        STARTUP_NTFLAG = 0
        STARTUP_VMFLAG = 0
        STARTUP_ACFLAG = 0
        STARTUP_IDFLAG = 0
        STARTUP_RFLAG  = 0

        STARTUP_GDTR_BASE  = 0
        STARTUP_GDTR_LIMIT = 0xFFFF
        STARTUP_IDTR_BASE  = 0
        STARTUP_IDTR_LIMIT = 0xFFFF

        STARTUP_DR0 = 0
        STARTUP_DR1 = 0
        STARTUP_DR2 = 0
        STARTUP_DR3 = 0
        STARTUP_DR6_BREAKPOINTS = 0
        STARTUP_DR6_B12 = true
        STARTUP_DR6_BD  = false
        STARTUP_DR6_BS  = false
        STARTUP_DR6_BT  = false
        STARTUP_DR7     = 0x0000_0400

        STARTUP_ES   = 0
        STARTUP_DS   = 0
        STARTUP_SS   = 0
        STARTUP_FS   = 0
        STARTUP_GS   = 0
        STARTUP_CS   = 0xF000
        STARTUP_LDTR = 0
        STARTUP_TR   = 0

        STARTUP_ES_RPL   = 0
        STARTUP_DS_RPL   = 0
        STARTUP_SS_RPL   = 0
        STARTUP_FS_RPL   = 0
        STARTUP_GS_RPL   = 0
        STARTUP_CS_RPL   = 0
        STARTUP_LDTR_RPL = 0
        STARTUP_TR_RPL   = 0

        STARTUP_ES_VALID   = true
        STARTUP_DS_VALID   = true
        STARTUP_SS_VALID   = true
        STARTUP_FS_VALID   = true
        STARTUP_GS_VALID   = true
        STARTUP_CS_VALID   = true
        STARTUP_LDTR_VALID = true
        STARTUP_TR_VALID   = true

        STARTUP_PREFETCH_LIMIT  = 16
        STARTUP_PREFETCH_LINEAR = 0xFFFF0

        # Default segment descriptor caches (from write_register.v)
        # { base[31:24], flags_byte, access_byte, base[23:0], limit[15:0] } = 64 bits
        # DEFAULT_SEG_CACHE:  base=0, G=1, D/B=0, P=1, DPL=0, S=1, Type=0011 (data RW accessed), limit=0xFFFF
        DEFAULT_SEG_CACHE  = 0x0000_9300_0000_FFFF
        # DEFAULT_CS_CACHE:   base=0xFFFF0000, same flags but code segment
        DEFAULT_CS_CACHE   = 0xFF00_9300_FF00_FFFF
        # DEFAULT_LDTR_CACHE: base=0, P=1, type=LDT (0010)
        DEFAULT_LDTR_CACHE = 0x0000_8200_0000_FFFF
        # DEFAULT_TR_CACHE:   base=0, P=1, type=busy TSS 386 (1011)
        DEFAULT_TR_CACHE   = 0x0000_8B00_0000_FFFF
      end
    end
  end
end
