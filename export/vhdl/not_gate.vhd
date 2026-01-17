library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity not_gate is
  port(
    a : in std_logic;
    y : out std_logic
  );
end not_gate;

architecture rtl of not_gate is
begin
  y <= not a;
end rtl;