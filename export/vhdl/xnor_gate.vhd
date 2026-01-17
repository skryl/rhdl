library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xnor_gate is
  port(
    a0 : in std_logic;
    a1 : in std_logic;
    y : out std_logic
  );
end xnor_gate;

architecture rtl of xnor_gate is
begin
  y <= not (a0 xor a1);
end rtl;