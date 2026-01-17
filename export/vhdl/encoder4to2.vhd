library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity encoder4to2 is
  port(
    a : in std_logic_vector(3 downto 0);
    y : out std_logic_vector(1 downto 0);
    valid : out std_logic
  );
end encoder4to2;

architecture rtl of encoder4to2 is
  signal is_3 : std_logic;
  signal is_2 : std_logic;
  signal is_1 : std_logic;
  signal is_0 : std_logic;
begin
  is_3 <= a(3);
  is_2 <= (not a(3) and a(2));
  is_1 <= ((not a(3) and not a(2)) and a(1));
  is_0 <= (((not a(3) and not a(2)) and not a(1)) and a(0));
  y <= (is_3 or is_2) & (is_3 or is_1);
  valid <= (((a(3) or a(2)) or a(1)) or a(0));
end rtl;