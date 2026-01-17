library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zero_extend is
  port(
    a : in std_logic_vector(7 downto 0);
    y : out std_logic_vector(15 downto 0)
  );
end zero_extend;

architecture rtl of zero_extend is
begin
  y <= std_logic_vector(resize(unsigned(a), 16));
end rtl;