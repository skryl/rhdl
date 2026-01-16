library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity accumulator is
  port(
    clk : in std_logic;
    reset : in std_logic;
    load : in std_logic;
    increment : in std_logic;
    data_in : in std_logic_vector(7 downto 0);
    data_out : out std_logic_vector(7 downto 0);
    clk : in std_logic;
    reset : in std_logic;
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    op : in std_logic_vector(3 downto 0);
    result : out std_logic_vector(7 downto 0);
    zero_flag : out std_logic;
    clk : in std_logic;
    reset : in std_logic;
    address : in std_logic_vector(7 downto 0);
    data_in : in std_logic_vector(7 downto 0);
    write_enable : in std_logic;
    data_out : out std_logic_vector(7 downto 0);
    clk : in std_logic;
    reset : in std_logic;
    data_in : in std_logic_vector(7 downto 0);
    load : in std_logic;
    data_out : out std_logic_vector(7 downto 0)
  );
end accumulator;

architecture rtl of accumulator is
begin
end rtl;