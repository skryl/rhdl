library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pop_count is
  port(
    a : in std_logic_vector(7 downto 0);
    count : out std_logic_vector(3 downto 0)
  );
end pop_count;

architecture rtl of pop_count is
begin
  count <= std_logic_vector(resize(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(a(0)) + unsigned(a(1)))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => a(2)))), 2))))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => a(3)))), 3))))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => a(4)))), 4))))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => a(5)))), 5))))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => a(6)))), 6))))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => a(7)))), 7))))), 4));
end rtl;