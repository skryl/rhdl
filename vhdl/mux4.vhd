library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mux4 is
  port(
    a : in std_logic;
    b : in std_logic;
    c : in std_logic;
    d : in std_logic;
    sel : in std_logic_vector(1 downto 0);
    y : out std_logic
  );
end mux4;

architecture rtl of mux4 is
  signal low_mux : std_logic;
  signal high_mux : std_logic;
begin
  low_mux <= (b when sel(0) = '1' else a);
  high_mux <= (d when sel(0) = '1' else c);
  y <= (high_mux when sel(1) = '1' else low_mux);
end rtl;