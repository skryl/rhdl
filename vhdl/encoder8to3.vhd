library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity encoder8to3 is
  port(
    a : in std_logic_vector(7 downto 0);
    y : out std_logic_vector(2 downto 0);
    valid : out std_logic
  );
end encoder8to3;

architecture rtl of encoder8to3 is
  signal is_7 : std_logic;
  signal is_6 : std_logic;
  signal is_5 : std_logic;
  signal is_4 : std_logic;
  signal is_3 : std_logic;
  signal is_2 : std_logic;
  signal is_1 : std_logic;
  signal is_0 : std_logic;
  signal y2 : std_logic;
  signal y1 : std_logic;
  signal y0 : std_logic;
begin
  is_7 <= a(7);
  is_6 <= (not a(7) and a(6));
  is_5 <= ((not a(7) and not a(6)) and a(5));
  is_4 <= (((not a(7) and not a(6)) and not a(5)) and a(4));
  is_3 <= ((((not a(7) and not a(6)) and not a(5)) and not a(4)) and a(3));
  is_2 <= (((((not a(7) and not a(6)) and not a(5)) and not a(4)) and not a(3)) and a(2));
  is_1 <= ((((((not a(7) and not a(6)) and not a(5)) and not a(4)) and not a(3)) and not a(2)) and a(1));
  is_0 <= (((((((not a(7) and not a(6)) and not a(5)) and not a(4)) and not a(3)) and not a(2)) and not a(1)) and a(0));
  y2 <= (((is_4 or is_5) or is_6) or is_7);
  y1 <= (((is_2 or is_3) or is_6) or is_7);
  y0 <= (((is_1 or is_3) or is_5) or is_7);
  y <= y2 & y1 & y0;
  valid <= (((((((a(7) or a(6)) or a(5)) or a(4)) or a(3)) or a(2)) or a(1)) or a(0));
end rtl;