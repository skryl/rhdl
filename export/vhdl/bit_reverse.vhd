library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bit_reverse is
  port(
    a : in std_logic_vector(7 downto 0);
    y : out std_logic_vector(7 downto 0)
  );
end bit_reverse;

architecture rtl of bit_reverse is
begin
  y <= a(0) & a(1) & a(2) & a(3) & a(4) & a(5) & a(6) & a(7);
end rtl;