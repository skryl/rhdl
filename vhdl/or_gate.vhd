library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity or_gate is
  port(
    a0 : in std_logic;
    a1 : in std_logic;
    y : out std_logic
  );
end or_gate;

architecture rtl of or_gate is
begin
  y <= (a0 or a1);
end rtl;