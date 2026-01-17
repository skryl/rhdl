library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tristate_buffer is
  port(
    a : in std_logic;
    en : in std_logic;
    y : out std_logic
  );
end tristate_buffer;

architecture rtl of tristate_buffer is
begin
  y <= (a when en = '1' else '0');
end rtl;