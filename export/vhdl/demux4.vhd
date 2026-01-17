library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity demux4 is
  port(
    a : in std_logic;
    sel : in std_logic_vector(1 downto 0);
    y0 : out std_logic;
    y1 : out std_logic;
    y2 : out std_logic;
    y3 : out std_logic
  );
end demux4;

architecture rtl of demux4 is
  signal sel_0 : std_logic;
  signal sel_1 : std_logic;
  signal sel_2 : std_logic;
  signal sel_3 : std_logic;
begin
  sel_0 <= (not sel(1) and not sel(0));
  sel_1 <= (not sel(1) and sel(0));
  sel_2 <= (sel(1) and not sel(0));
  sel_3 <= (sel(1) and sel(0));
  y0 <= (a when sel_0 = '1' else '0');
  y1 <= (a when sel_1 = '1' else '0');
  y2 <= (a when sel_2 = '1' else '0');
  y3 <= (a when sel_3 = '1' else '0');
end rtl;