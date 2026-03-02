# frozen_string_literal: true

class Condition < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: condition

  def self._import_decl_kinds
    {
      __VdfgRegularize_h583ff439_0_0: :logic,
      __VdfgRegularize_h583ff439_0_1: :logic,
      __VdfgRegularize_h583ff439_0_2: :logic
    }
  end

  # Ports

  input :oflag
  input :cflag
  input :sflag
  input :zflag
  input :pflag
  input :index, width: 4
  output :condition

  # Signals

  signal :__VdfgRegularize_h583ff439_0_0
  signal :__VdfgRegularize_h583ff439_0_1
  signal :__VdfgRegularize_h583ff439_0_2

  # Assignments

  assign :condition,
    case_select(
      sig(:index, width: 4),
      cases: {
        0 => sig(:oflag, width: 1),
        1 => (~sig(:oflag, width: 1)),
        2 => sig(:cflag, width: 1),
        3 => (~sig(:cflag, width: 1)),
        4 => sig(:zflag, width: 1),
        5 => (~sig(:zflag, width: 1)),
        6 => sig(:__VdfgRegularize_h583ff439_0_0, width: 1),
        7 => (~sig(:__VdfgRegularize_h583ff439_0_0, width: 1)),
        8 => sig(:sflag, width: 1),
        9 => (~sig(:sflag, width: 1)),
        10 => sig(:pflag, width: 1),
        11 => (~sig(:pflag, width: 1)),
        12 => sig(:__VdfgRegularize_h583ff439_0_2, width: 1),
        13 => (~sig(:__VdfgRegularize_h583ff439_0_2, width: 1)),
        14 => sig(:__VdfgRegularize_h583ff439_0_1, width: 1)
      },
      default: (~sig(:__VdfgRegularize_h583ff439_0_1, width: 1))
    )
  assign :__VdfgRegularize_h583ff439_0_0,
    (
        sig(:cflag, width: 1) |
        sig(:zflag, width: 1)
    )
  assign :__VdfgRegularize_h583ff439_0_2,
    (
        sig(:oflag, width: 1) ^
        sig(:sflag, width: 1)
    )
  assign :__VdfgRegularize_h583ff439_0_1,
    (
        sig(:__VdfgRegularize_h583ff439_0_2, width: 1) |
        sig(:zflag, width: 1)
    )

end
