library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mux2 is
  port(
    a : in std_logic;
    b : in std_logic;
    sel : in std_logic;
    y : out std_logic
  );
end mux2;

architecture rtl of mux2 is
begin
  y <= (b when sel = '1' else a);
end rtl;