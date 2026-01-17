module comparator(
  input [7:0] a,
  input [7:0] b,
  input signed_cmp,
  output eq,
  output gt,
  output lt,
  output gte,
  output lte
);

  wire unsigned_eq;
  wire unsigned_gt;
  wire unsigned_lt;
  wire a_sign;
  wire b_sign;
  wire signs_differ;
  wire signed_lt;
  wire signed_gt;
  wire signed_eq;
  wire eq_result;
  wire gt_result;
  wire lt_result;

  assign unsigned_eq = (a == b);
  assign unsigned_gt = (a > b);
  assign unsigned_lt = (a < b);
  assign a_sign = a[7];
  assign b_sign = b[7];
  assign signs_differ = (a_sign ^ b_sign);
  assign signed_lt = (signs_differ ? a_sign : unsigned_lt);
  assign signed_gt = (signs_differ ? b_sign : unsigned_gt);
  assign signed_eq = unsigned_eq;
  assign eq_result = (signed_cmp ? signed_eq : unsigned_eq);
  assign gt_result = (signed_cmp ? signed_gt : unsigned_gt);
  assign lt_result = (signed_cmp ? signed_lt : unsigned_lt);
  assign eq = (signed_cmp ? signed_eq : unsigned_eq);
  assign gt = (signed_cmp ? signed_gt : unsigned_gt);
  assign lt = (signed_cmp ? signed_lt : unsigned_lt);
  assign gte = (eq_result | gt_result);
  assign lte = (eq_result | lt_result);

endmodule