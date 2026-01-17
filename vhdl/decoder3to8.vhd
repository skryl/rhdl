library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decoder3to8 is
  port(
    a : in std_logic_vector(2 downto 0);
    en : in std_logic;
    y0 : out std_logic;
    y1 : out std_logic;
    y2 : out std_logic;
    y3 : out std_logic;
    y4 : out std_logic;
    y5 : out std_logic;
    y6 : out std_logic;
    y7 : out std_logic
  );
end decoder3to8;

architecture rtl of decoder3to8 is
begin
  y0 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(0, 3)))));
  y1 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(1, 3)))));
  y2 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(2, 3)))));
  y3 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(3, 3)))));
  y4 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(4, 3)))));
  y5 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(5, 3)))));
  y6 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(6, 3)))));
  y7 <= (en and (unsigned(a) = unsigned(std_logic_vector(to_unsigned(7, 3)))));
end rtl;