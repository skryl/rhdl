library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
  port(
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    op : in std_logic_vector(3 downto 0);
    cin : in std_logic;
    result : out std_logic_vector(7 downto 0);
    cout : out std_logic;
    zero : out std_logic;
    negative : out std_logic;
    overflow : out std_logic
  );
end alu;

architecture rtl of alu is
begin
  result <= std_logic_vector(resize(unsigned((std_logic_vector(unsigned(std_logic_vector(unsigned(a) + unsigned(b))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => (cin and '1')))), 9)))) and std_logic_vector(resize(unsigned(std_logic_vector(to_unsigned(255, 8))), 10)))), 8));
  cout <= std_logic_vector(resize(unsigned((std_logic_vector(shift_right(unsigned(std_logic_vector(unsigned(std_logic_vector(unsigned(a) + unsigned(b))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => (cin and '1')))), 9))))), to_integer(unsigned(std_logic_vector(resize(unsigned(std_logic_vector(to_unsigned(8, 4))), 10)))))) and std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => '1'))), 10)))), 1));
  zero <= '1';
  negative <= std_logic_vector(resize(unsigned((std_logic_vector(shift_right(unsigned((std_logic_vector(unsigned(std_logic_vector(unsigned(a) + unsigned(b))) + unsigned(std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => (cin and '1')))), 9)))) and std_logic_vector(resize(unsigned(std_logic_vector(to_unsigned(255, 8))), 10)))), to_integer(unsigned(std_logic_vector(resize(unsigned(std_logic_vector(to_unsigned(7, 3))), 10)))))) and std_logic_vector(resize(unsigned(std_logic_vector'((0 downto 0 => '1'))), 10)))), 1));
  overflow <= '1';
end rtl;