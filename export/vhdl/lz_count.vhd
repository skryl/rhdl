library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lz_count is
  port(
    a : in std_logic_vector(7 downto 0);
    count : out std_logic_vector(3 downto 0);
    all_zero : out std_logic
  );
end lz_count;

architecture rtl of lz_count is
begin
  count <= std_logic_vector(resize(unsigned(std_logic_vector(to_unsigned(4, 3))), 4));
  all_zero <= '1';
end rtl;