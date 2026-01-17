library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity inc_dec is
  port(
    a : in std_logic_vector(7 downto 0);
    inc : in std_logic;
    result : out std_logic_vector(7 downto 0);
    cout : out std_logic
  );
end inc_dec;

architecture rtl of inc_dec is
  signal inc_result : std_logic_vector(7 downto 0);
  signal dec_result : std_logic_vector(7 downto 0);
  signal inc_cout : std_logic;
  signal dec_cout : std_logic;
begin
  inc_result <= std_logic_vector(resize(unsigned(std_logic_vector(unsigned(a) + unsigned(std_logic_vector(to_unsigned(1, 8))))), 8));
  dec_result <= std_logic_vector(unsigned(a) - unsigned(std_logic_vector(to_unsigned(1, 8))));
  inc_cout <= (unsigned(a) = unsigned(std_logic_vector(to_unsigned(255, 8))));
  dec_cout <= (unsigned(a) = unsigned(std_logic_vector(to_unsigned(0, 8))));
  result <= (inc_result when inc = '1' else dec_result);
  cout <= (inc_cout when inc = '1' else dec_cout);
end rtl;