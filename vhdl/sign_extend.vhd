library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sign_extend is
  port(
    a : in std_logic_vector(7 downto 0);
    y : out std_logic_vector(15 downto 0)
  );
end sign_extend;

architecture rtl of sign_extend is
  signal sign : std_logic;
  signal extension : std_logic_vector(7 downto 0);
begin
  sign <= a(7);
  extension <= (std_logic_vector(to_unsigned(255, 8)) when sign = '1' else std_logic_vector(to_unsigned(0, 8)));
  y <= extension & a;
end rtl;