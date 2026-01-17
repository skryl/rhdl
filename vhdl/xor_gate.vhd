library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xor_gate is
  port(
    a0 : in std_logic;
    a1 : in std_logic;
    y : out std_logic
  );
end xor_gate;

architecture rtl of xor_gate is
begin
  y <= (a0 xor a1);
end rtl;