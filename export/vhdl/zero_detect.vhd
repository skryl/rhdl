library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zero_detect is
  port(
    a : in std_logic_vector(7 downto 0);
    zero : out std_logic
  );
end zero_detect;

architecture rtl of zero_detect is
begin
  zero <= (unsigned(a) = unsigned(std_logic_vector(to_unsigned(0, 8))));
end rtl;