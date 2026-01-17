library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity subtractor is
  port(
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    bin : in std_logic;
    diff : out std_logic_vector(7 downto 0);
    bout : out std_logic;
    overflow : out std_logic
  );
end subtractor;

architecture rtl of subtractor is
  signal diff_result : std_logic_vector(7 downto 0);
  signal b_plus_bin : std_logic_vector(8 downto 0);
  signal a_sign : std_logic;
  signal b_sign : std_logic;
  signal diff_sign : std_logic;
begin
  diff_result <= std_logic_vector(unsigned(std_logic_vector(unsigned(a) - unsigned(b))) - unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => bin))), 8))));
  b_plus_bin <= std_logic_vector(unsigned(b) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => bin))), 8))));
  a_sign <= a(7);
  b_sign <= b(7);
  diff_sign <= diff_result(7);
  diff <= diff_result;
  bout <= (unsigned(a) < unsigned(std_logic_vector(resize(unsigned(b_plus_bin), 8))));
  overflow <= ((a_sign xor b_sign) and (diff_sign xor a_sign));
end rtl;