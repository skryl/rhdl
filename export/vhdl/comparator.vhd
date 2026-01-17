library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity comparator is
  port(
    a : in std_logic_vector(7 downto 0);
    b : in std_logic_vector(7 downto 0);
    signed_cmp : in std_logic;
    eq : out std_logic;
    gt : out std_logic;
    lt : out std_logic;
    gte : out std_logic;
    lte : out std_logic
  );
end comparator;

architecture rtl of comparator is
  signal unsigned_eq : std_logic;
  signal unsigned_gt : std_logic;
  signal unsigned_lt : std_logic;
  signal a_sign : std_logic;
  signal b_sign : std_logic;
  signal signs_differ : std_logic;
  signal signed_lt : std_logic;
  signal signed_gt : std_logic;
  signal signed_eq : std_logic;
  signal eq_result : std_logic;
  signal gt_result : std_logic;
  signal lt_result : std_logic;
begin
  unsigned_eq <= (unsigned(a) = unsigned(b));
  unsigned_gt <= (unsigned(a) > unsigned(b));
  unsigned_lt <= (unsigned(a) < unsigned(b));
  a_sign <= a(7);
  b_sign <= b(7);
  signs_differ <= (a_sign xor b_sign);
  signed_lt <= (a_sign when signs_differ = '1' else unsigned_lt);
  signed_gt <= (b_sign when signs_differ = '1' else unsigned_gt);
  signed_eq <= unsigned_eq;
  eq_result <= (signed_eq when signed_cmp = '1' else unsigned_eq);
  gt_result <= (signed_gt when signed_cmp = '1' else unsigned_gt);
  lt_result <= (signed_lt when signed_cmp = '1' else unsigned_lt);
  eq <= (signed_eq when signed_cmp = '1' else unsigned_eq);
  gt <= (signed_gt when signed_cmp = '1' else unsigned_gt);
  lt <= (signed_lt when signed_cmp = '1' else unsigned_lt);
  gte <= (eq_result or gt_result);
  lte <= (eq_result or lt_result);
end rtl;