library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mux8 is
  port(
    in0 : in std_logic;
    in1 : in std_logic;
    in2 : in std_logic;
    in3 : in std_logic;
    in4 : in std_logic;
    in5 : in std_logic;
    in6 : in std_logic;
    in7 : in std_logic;
    sel : in std_logic_vector(2 downto 0);
    y : out std_logic
  );
end mux8;

architecture rtl of mux8 is
begin
  y <= (in0 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(0, 3)))) else (in1 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(1, 3)))) else (in2 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(2, 3)))) else (in3 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(3, 3)))) else (in4 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(4, 3)))) else (in5 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(5, 3)))) else (in6 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(6, 3)))) else (in7 when (unsigned(sel) = unsigned(std_logic_vector(to_unsigned(7, 3)))) else '0'))))))));
end rtl;