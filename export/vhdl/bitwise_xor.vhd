library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bitwise_xor is
  port(
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    y : out std_logic_vector(7 downto 0)
  );
end bitwise_xor;

architecture rtl of bitwise_xor is
begin
  y <= (a xor b);
end rtl;