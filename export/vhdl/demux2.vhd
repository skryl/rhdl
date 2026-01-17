library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity demux2 is
  port(
    a : in std_logic;
    sel : in std_logic;
    y0 : out std_logic;
    y1 : out std_logic
  );
end demux2;

architecture rtl of demux2 is
begin
  y0 <= ('0' when sel = '1' else a);
  y1 <= (a when sel = '1' else '0');
end rtl;