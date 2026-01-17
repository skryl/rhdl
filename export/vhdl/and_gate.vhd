library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity and_gate is
  port(
    a0 : in std_logic;
    a1 : in std_logic;
    y : out std_logic
  );
end and_gate;

architecture rtl of and_gate is
begin
  y <= (a0 and a1);
end rtl;