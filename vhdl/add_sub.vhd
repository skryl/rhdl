library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity add_sub is
  port(
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    sub : in std_logic;
    result : out std_logic_vector(7 downto 0);
    cout : out std_logic;
    overflow : out std_logic;
    zero : out std_logic;
    negative : out std_logic
  );
end add_sub;

architecture rtl of add_sub is
  signal sum_result : std_logic_vector(7 downto 0);
  signal diff_result : std_logic_vector(7 downto 0);
  signal add_carry : std_logic;
  signal sub_borrow : std_logic;
  signal a_sign : std_logic;
  signal b_sign : std_logic;
  signal result_val : std_logic_vector(7 downto 0);
  signal r_sign : std_logic;
  signal add_overflow : std_logic;
  signal sub_overflow : std_logic;
begin
  sum_result <= std_logic_vector(resize(unsigned(std_logic_vector(unsigned(a) + unsigned(b))), 8));
  diff_result <= std_logic_vector(unsigned(a) - unsigned(b));
  add_carry <= std_logic_vector(unsigned(a) + unsigned(b))(8);
  sub_borrow <= (unsigned(a) < unsigned(b));
  a_sign <= a(7);
  b_sign <= b(7);
  result_val <= (diff_result when sub = '1' else sum_result);
  r_sign <= result_val(7);
  add_overflow <= ((a_sign = b_sign) and (r_sign xor a_sign));
  sub_overflow <= ((a_sign xor b_sign) and (r_sign xor a_sign));
  result <= (diff_result when sub = '1' else sum_result);
  cout <= (sub_borrow when sub = '1' else add_carry);
  overflow <= (sub_overflow when sub = '1' else add_overflow);
  zero <= (unsigned(result_val) = unsigned(std_logic_vector(to_unsigned(0, 8))));
  negative <= r_sign;
end rtl;