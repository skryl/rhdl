library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bitwise_or is
  port(
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    y : out std_logic_vector(7 downto 0)
  );
end bitwise_or;

architecture rtl of bitwise_or is
begin
  y <= (a or b);
end rtl;