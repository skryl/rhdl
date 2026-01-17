library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nor_gate is
  port(
    a0 : in std_logic;
    a1 : in std_logic;
    y : out std_logic
  );
end nor_gate;

architecture rtl of nor_gate is
begin
  y <= not (a0 or a1);
end rtl;