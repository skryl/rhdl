library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ripple_carry_adder is
  port(
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    cin : in std_logic;
    sum : out std_logic_vector(7 downto 0);
    cout : out std_logic;
    overflow : out std_logic
  );
end ripple_carry_adder;

architecture rtl of ripple_carry_adder is
  signal result : std_logic_vector(8 downto 0);
  signal a_sign : std_logic;
  signal b_sign : std_logic;
  signal sum_sign : std_logic;
begin
  result <= std_logic_vector(resize(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(a) + unsigned(b))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => cin))), 9))))), 9));
  a_sign <= a(7);
  b_sign <= b(7);
  sum_sign <= result(7);
  sum <= result();
  cout <= result(8);
  overflow <= ((a_sign xor sum_sign) and not (a_sign xor b_sign));
end rtl;