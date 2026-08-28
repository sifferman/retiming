// r18 -- clock_gated_region  (HAND-RETIMED REFERENCE)
//
//   din --[ 2 rounds ]--> (s1_q,en) --[ 3 rounds ]--> (s2_q,en) --[ 3 rounds ]--> (s3_q,en)
//
// Eight rounds total, cut 2 / 3 / 3 instead of the original 6 / 1 / 1.
//
// All three registers keep the same shared enable, so the clock-gated domain is
// unchanged in extent; only the logic distribution between the gated registers
// changes.
//
// Correctness with an enable
// --------------------------
// Every register in both variants is gated by the same `en`, so on any cycle
// either all of them advance or none do.  The pipeline is therefore equivalent to
// the ungated one sampled on enabled cycles, and the retiming argument reduces to
// the ordinary feed-forward case: the same eight rounds are applied in the same
// order, just cut in different places.
//
// Reset: all stages reset to zero in the original.  Because the round functions
// are applied to zero-valued registers during reset in BOTH variants, and the
// original's stages 2 and 3 apply a round to their predecessor's reset value, the
// retimed reset values are the corresponding forward images -- derived below
// rather than assumed to be zero.

module r18_clock_gated_region_core (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,
    input  logic [15:0] din,
    output logic [15:0] dout
);

  function automatic logic [15:0] rnd (input logic [15:0] x,
                                       input logic [15:0] k,
                                       input logic [15:0] c);
    logic [15:0] t;
    t   = {x[14:0], x[15]} ^ k;
    rnd = t + c;
  endfunction
  function automatic logic [15:0] rnd_inv (input logic [15:0] y,
                                           input logic [15:0] k,
                                           input logic [15:0] c);
    logic [15:0] t;
    t       = (y - c) ^ k;
    rnd_inv = {t[0], t[15:1]};
  endfunction

  localparam logic [15:0] K1 = 16'h9E37, C1 = 16'h1234;
  localparam logic [15:0] K2 = 16'h7B15, C2 = 16'h5A5A;
  localparam logic [15:0] K3 = 16'hC2B2, C3 = 16'h0F1E;
  localparam logic [15:0] K4 = 16'h27D4, C4 = 16'hBEEF;
  localparam logic [15:0] K5 = 16'h1656, C5 = 16'h3C3C;
  localparam logic [15:0] K6 = 16'h6763, C6 = 16'h07E1;
  localparam logic [15:0] K7 = 16'hB7E1, C7 = 16'h51ED;
  localparam logic [15:0] K8 = 16'h2545, C8 = 16'hF491;

  // Stage functions after the cut: 2 rounds / 3 rounds / 3 rounds.
  function automatic logic [15:0] f1 (input logic [15:0] x);
    f1 = rnd(rnd(x, K1, C1), K2, C2);
  endfunction
  function automatic logic [15:0] f2 (input logic [15:0] x);
    f2 = rnd(rnd(rnd(x, K3, C3), K4, C4), K5, C5);
  endfunction
  function automatic logic [15:0] f3 (input logic [15:0] x);
    f3 = rnd(rnd(rnd(x, K6, C6), K7, C7), K8, C8);
  endfunction

  // Reset values -- derived, and NOT zero
  // ------------------------------------
  // Writing zero into the retimed registers is the obvious guess and it is wrong.
  // The original's downstream stages do not hold zero after reset: they hold a
  // ROUND OF zero, because stage 2 latches round7(s1_q) while s1_q is still zero,
  // and stage 3 latches round8(s2_q) likewise.
  //
  // Name the original's stage functions g1 = rounds 1-6, g2 = round 7,
  // g3 = round 8, and the retimed ones f1 = rounds 1-2, f2 = rounds 3-5,
  // f3 = rounds 6-8.  Note g3.g2.g1 == f3.f2.f1: same eight rounds, cut elsewhere.
  //
  // dout is s3_q in both variants, so s3_q must agree cycle for cycle.  Requiring
  // that gives the invariant
  //
  //     s2_ret[t] = f3^-1( g3( s2_orig[t] ) )
  //     s1_ret[t] = f2^-1( f3^-1( g3( g2( s1_orig[t] ) ) ) )
  //
  // which is self-consistent precisely because the two cuts compose to the same
  // eight rounds.  Substituting the original's reset state (s1_orig = s2_orig = 0)
  // gives the constants below.  Every register is gated by the same `en`, so the
  // invariant survives enable gaps: either all registers advance or none do.
  function automatic logic [15:0] f3_inv (input logic [15:0] y);
    f3_inv = rnd_inv(rnd_inv(rnd_inv(y, K8, C8), K7, C7), K6, C6);
  endfunction
  function automatic logic [15:0] f2_inv (input logic [15:0] y);
    f2_inv = rnd_inv(rnd_inv(rnd_inv(y, K5, C5), K4, C4), K3, C3);
  endfunction
  function automatic logic [15:0] g2 (input logic [15:0] x);
    g2 = rnd(x, K7, C7);
  endfunction
  function automatic logic [15:0] g3 (input logic [15:0] x);
    g3 = rnd(x, K8, C8);
  endfunction

  localparam logic [15:0] S3_RESET = 16'h0;
  localparam logic [15:0] S2_RESET = f3_inv(g3(16'h0));
  localparam logic [15:0] S1_RESET = f2_inv(f3_inv(g3(g2(16'h0))));

  logic [15:0] s1_q, s2_q, s3_q;

  always_ff @(posedge clk) begin
    if (!rst_n)  s1_q <= S1_RESET;
    else if (en) s1_q <= f1(din);
  end

  always_ff @(posedge clk) begin
    if (!rst_n)  s2_q <= S2_RESET;
    else if (en) s2_q <= f2(s1_q);
  end

  always_ff @(posedge clk) begin
    if (!rst_n)  s3_q <= S3_RESET;
    else if (en) s3_q <= f3(s2_q);
  end

  assign dout = s3_q;

endmodule

// RT_WRAPPER_BEGIN -- generated by scripts/add_io_registers.py
// ---------------------------------------------------------------------
// Every input is captured and every output is registered, so ALL logic in
// r18_clock_gated_region_core lies between flip-flops and reg2reg timing sees all of it.
// Applied identically to every variant, so the variants remain equivalent
// to one another; each simply gains the same 2 cycles of latency.
// ---------------------------------------------------------------------
module r18_clock_gated_region (
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic [15:0] din,
    output logic [15:0] dout
);
  (* dont_touch = "yes", RETIMING_FORWARD = 0, RETIMING_BACKWARD = 0 *)
  logic en_iq;
  (* dont_touch = "yes", RETIMING_FORWARD = 0, RETIMING_BACKWARD = 0 *)
  logic [15:0] din_iq;
  (* dont_touch = "yes", RETIMING_FORWARD = 0, RETIMING_BACKWARD = 0 *)
  logic [15:0] dout_c;

  // capture inputs
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      en_iq <= '0;
      din_iq <= '0;
    end else begin
      en_iq <= en;
      din_iq <= din;
    end
  end

  r18_clock_gated_region_core u_core (
    .clk(clk), .rst_n(rst_n),
    .en(en_iq),
    .din(din_iq),
    .dout(dout_c)
  );

  // register outputs
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      dout <= '0;
    end else begin
      dout <= dout_c;
    end
  end

endmodule
