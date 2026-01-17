library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity instruction_decoder is
  port(
    instruction : in std_logic_vector(7 downto 0);
    zero_flag : in std_logic;
    alu_op : out std_logic_vector(3 downto 0);
    alu_src : out std_logic;
    reg_write : out std_logic;
    mem_read : out std_logic;
    mem_write : out std_logic;
    branch : out std_logic;
    jump : out std_logic;
    pc_src : out std_logic_vector(1 downto 0);
    halt : out std_logic;
    call : out std_logic;
    ret : out std_logic;
    instr_length : out std_logic_vector(1 downto 0)
  );
end instruction_decoder;

architecture rtl of instruction_decoder is
begin
  alu_op <= ('0' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(3, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(4, 4)))) else (std_logic_vector(to_unsigned(2, 2)) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(5, 4)))) else (std_logic_vector(to_unsigned(3, 2)) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(6, 4)))) else (std_logic_vector(to_unsigned(4, 3)) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(7, 4)))) else (std_logic_vector(to_unsigned(12, 4)) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(14, 4)))) else ((std_logic_vector(to_unsigned(11, 4)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(241, 8)))) else (std_logic_vector(to_unsigned(5, 3)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(242, 8)))) else ('1' when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(243, 8)))) else '0'))) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(15, 4)))) else '0')))))));
  alu_src <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(10, 4)))) else '0');
  reg_write <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(1, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(3, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(4, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(5, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(6, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(7, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(10, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(14, 4)))) else (('1' when ((unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(241, 8)))) or (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(242, 8))))) = '1' else '0') when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(15, 4)))) else '0')))))))));
  mem_read <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(1, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(3, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(4, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(5, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(6, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(7, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(14, 4)))) else (('1' when ((unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(241, 8)))) or (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(243, 8))))) = '1' else '0') when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(15, 4)))) else '0'))))))));
  mem_write <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(resize(unsigned(std_logic_vector(to_unsigned(2, 2))), 4)))) else '0');
  branch <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(8, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(9, 4)))) else (('1' when ((unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(248, 8)))) or (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(250, 8))))) = '1' else '0') when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(15, 4)))) else '0')));
  jump <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(11, 4)))) else (('1' when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(249, 8)))) else '0') when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(15, 4)))) else '0'));
  pc_src <= (('1' when zero_flag = '1' else '0') when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(8, 4)))) else (('0' when zero_flag = '1' else '1') when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(9, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(11, 4)))) else ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(12, 4)))) else (((std_logic_vector(to_unsigned(2, 2)) when zero_flag = '1' else '0') when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(248, 8)))) else (std_logic_vector(to_unsigned(2, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(249, 8)))) else (('0' when zero_flag = '1' else std_logic_vector(to_unsigned(2, 2))) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(250, 8)))) else '0'))) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(15, 4)))) else '0')))));
  halt <= ('1' when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(240, 8)))) else '0');
  call <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(12, 4)))) else '0');
  ret <= ('1' when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(13, 4)))) else '0');
  instr_length <= ((std_logic_vector(to_unsigned(3, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(32, 8)))) else (std_logic_vector(to_unsigned(2, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(33, 8)))) else '1')) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(2, 4)))) else (std_logic_vector(to_unsigned(2, 2)) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(10, 4)))) else ((std_logic_vector(to_unsigned(2, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(241, 8)))) else (std_logic_vector(to_unsigned(2, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(243, 8)))) else (std_logic_vector(to_unsigned(3, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(248, 8)))) else (std_logic_vector(to_unsigned(3, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(249, 8)))) else (std_logic_vector(to_unsigned(3, 2)) when (unsigned(instruction) = unsigned(std_logic_vector(to_unsigned(250, 8)))) else '1'))))) when (unsigned(instruction()) = unsigned(std_logic_vector(to_unsigned(15, 4)))) else '1')));
end rtl;