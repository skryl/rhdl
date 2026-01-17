library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity buffer_rhdl is
  port(
    a : in std_logic;
    y : out std_logic
  );
end buffer_rhdl;

architecture rtl of buffer_rhdl is
begin
  y <= a;
end rtl;