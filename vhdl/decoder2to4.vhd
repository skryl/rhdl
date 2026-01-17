library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decoder2to4 is
  port(
    a : in std_logic_vector(1 downto 0);
    en : in std_logic;
    y0 : out std_logic;
    y1 : out std_logic;
    y2 : out std_logic;
    y3 : out std_logic
  );
end decoder2to4;

architecture rtl of decoder2to4 is
begin
  y0 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(0, 2)))));
  y1 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(1, 2)))));
  y2 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(2, 2)))));
  y3 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(3, 2)))));
end rtl;