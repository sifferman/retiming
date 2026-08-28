// r30 -- fsm_decode_fanout  (REFERENCE = decode retimed ACROSS the state register)
//
// Reduced from a REAL design and a real failure: sifferman/ternip commit 55bf227,
// rtl/fus/ternip_tmatmul.sv. Vivado could not retime it, so commit 7b658c7 did the
// transform by hand. Every other benchmark in this suite is synthetic; this one is
// not, and it is the case the project exists to explain.
//
// The original shape, preserved here: a 3-state FSM plus a 4-value operation enum,
// decoded into five mutually exclusive conditions, each gating a wide datapath
// cloud (BRAM control, gearbox FIFOs, RowParallelism accumulators).
//
//   state_q ---+--> [decode cone] --> do_* --> ~1000 loads spread across the die
//              |
//              +--> next-state logic (must keep an UNRETIMED copy)
//
// Two things make this hard for a retimer, and both are in CLAUDE.md:
//   * state_q is in a FEEDBACK LOOP (it computes state_d), so classical retiming
//     cannot move it -- the loop's register count is invariant.
//   * the decode cone's output is what has the high fanout, and relieving it needs
//     DUPLICATION, which is outside the retiming formulation.
// THE FIX, as done by hand in ternip commit 7b658c7: compute each decode from the
// NEXT state (state_d/op_d) and register it. At the following edge the registered
// decode carries exactly the value the combinational decode of state_q would have
// had, so this is LATENCY PRESERVING -- it is forward retiming of the decode cone
// across the state register, not an extra pipeline stage.
//
// What that buys:
//   * the high-fanout net is now a REGISTER OUTPUT, not the apex of a decode cone,
//     so the tool is free to duplicate the register per lane group and place the
//     copies near their loads;
//   * the decode logic moves off the critical path into the previous cycle;
//   * state_q survives untouched for the next-state loop, which is what makes this
//     legal at all.
//
// The catch, and the reason a tool has to reason about it: each new register needs
// the RESET VALUE the decode would have produced in the reset state. state_q resets
// to WAITING_FOR_IN, so do_wait_in_q must reset to 1 and the rest to 0. Get that
// wrong and the design differs only in the cycles right after reset -- which is why
// scripts/gen_tb.py pulses reset mid-run.

module r30_fsm_decode_fanout_core #(
    parameter int LANES = 32,          // RowParallelism in the original
    parameter int WIDTH = 32           // fixed_point_t width
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     instr_valid,
    input  logic [1:0]               instr_op,
    input  logic [31:0]              din,       // WIDTH-1:0, written literal:
                                                  // scripts/gen_tb.py cannot evaluate
                                                  // a parameter expression in a port
    output logic [1023:0]            dout       // LANES*WIDTH-1:0
);
  typedef enum logic [1:0] {WAITING_FOR_IN, WAITING_FOR_DDR, WORKING} state_e;
  typedef enum logic [1:0] {OP_GO, OP_IMPORT, OP_EXPORT, OP_NOP} op_e;

  state_e state_q, state_d;
  op_e    op_q, op_d;

  // ---- next-state logic: reads state_q, so state_q cannot be retimed away -----
  always_comb begin
    state_d = state_q;
    op_d    = op_q;
    unique case (state_q)
      WAITING_FOR_IN:  if (instr_valid) begin
                         state_d = WAITING_FOR_DDR;
                         op_d    = op_e'(instr_op);
                       end
      WAITING_FOR_DDR: if (op_q == OP_GO)  state_d = WORKING;
                       else                state_d = WORKING;
      WORKING:         if (din[0])         state_d = WAITING_FOR_IN;
      default:         state_d = WAITING_FOR_IN;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_q <= WAITING_FOR_IN;
      op_q    <= OP_NOP;
    end else begin
      state_q <= state_d;
      op_q    <= op_d;
    end
  end

  // ---- the decode, retimed across the state register -------------------------
  // Named as in the real commit: in_state_waiting_for_in_q, in_state_working_go_q,
  // in_state_working_import_q, in_state_working_export_q,
  // in_state_waiting_for_ddr_go_q.
  logic do_wait_in, do_wait_ddr, do_import, do_go, do_export;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      // the decode of the RESET STATE (WAITING_FOR_IN, OP_NOP), not zero
      do_wait_in  <= 1'b1;
      do_wait_ddr <= 1'b0;
      do_import   <= 1'b0;
      do_go       <= 1'b0;
      do_export   <= 1'b0;
    end else begin
      // decoded from state_d/op_d, so it lands in step with state_q
      do_wait_in  <=  (state_d == WAITING_FOR_IN);
      do_wait_ddr <= ((state_d == WAITING_FOR_DDR) && (op_d == OP_GO));
      do_import   <= ((state_d == WORKING)         && (op_d == OP_IMPORT));
      do_go       <= ((state_d == WORKING)         && (op_d == OP_GO));
      do_export   <= ((state_d == WORKING)         && (op_d == OP_EXPORT));
    end
  end

  // ---- the gated datapath: LANES lanes, each a WIDTH-bit accumulator ----------
  logic [WIDTH-1:0] acc_q [LANES];
  logic [WIDTH-1:0] seed_q;

  always_ff @(posedge clk) begin
    if (!rst_n) seed_q <= '0;
    else        seed_q <= din;
  end

  for (genvar i = 0; i < LANES; i++) begin : g_lane
    // Every lane reads all five decodes: this is where the fanout goes.
    always_ff @(posedge clk) begin
      if (!rst_n) acc_q[i] <= '0;
      else if (do_import) acc_q[i] <= acc_q[i] ^ (seed_q + WIDTH'(i));
      else if (do_go)     acc_q[i] <= acc_q[i] + (seed_q ^ {acc_q[i][WIDTH-2:0], acc_q[i][WIDTH-1]});
      else if (do_export) acc_q[i] <= {acc_q[i][WIDTH-2:0], acc_q[i][WIDTH-1]} ^ seed_q;
      else if (do_wait_ddr) acc_q[i] <= acc_q[i] + WIDTH'(1);
      else if (do_wait_in)  acc_q[i] <= acc_q[i];
    end
    assign dout[i*WIDTH +: WIDTH] = acc_q[i];
  end

endmodule

// RT_WRAPPER_BEGIN -- generated by scripts/add_io_registers.py
// ---------------------------------------------------------------------
// Every input is captured and every output is registered, so ALL logic in
// r30_fsm_decode_fanout_core lies between flip-flops and reg2reg timing sees all of it.
// Applied identically to every variant, so the variants remain equivalent
// to one another; each simply gains the same 2 cycles of latency.
// ---------------------------------------------------------------------
module r30_fsm_decode_fanout (
    input  logic clk,
    input  logic rst_n,
    input  logic instr_valid,
    input  logic [1:0] instr_op,
    input  logic [31:0] din,
    output logic [7:0] dout
);
  (* dont_touch = "yes", RETIMING_FORWARD = 0, RETIMING_BACKWARD = 0 *)
  logic instr_valid_iq;
  (* dont_touch = "yes", RETIMING_FORWARD = 0, RETIMING_BACKWARD = 0 *)
  logic [1:0] instr_op_iq;
  (* dont_touch = "yes", RETIMING_FORWARD = 0, RETIMING_BACKWARD = 0 *)
  logic [31:0] din_iq;
  (* dont_touch = "yes", RETIMING_FORWARD = 0, RETIMING_BACKWARD = 0 *)
  logic [1023:0] dout_c;
  logic [1023:0] dout_sr;
  logic [6:0] dout_cnt;
  always_ff @(posedge clk) begin
    if (!rst_n) begin dout_sr <= '0; dout_cnt <= '0; end
    else begin
      dout_cnt <= (dout_cnt == 127) ? '0 : dout_cnt + 1'b1;
      dout_sr  <= (dout_cnt == 0) ? dout_c : {dout_sr[1015:0], 8'h0};
    end
  end

  // capture inputs
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      instr_valid_iq <= '0;
      instr_op_iq <= '0;
      din_iq <= '0;
    end else begin
      instr_valid_iq <= instr_valid;
      instr_op_iq <= instr_op;
      din_iq <= din;
    end
  end

  r30_fsm_decode_fanout_core u_core (
    .clk(clk), .rst_n(rst_n),
    .instr_valid(instr_valid_iq),
    .instr_op(instr_op_iq),
    .din(din_iq),
    .dout(dout_c)
  );

  // register outputs
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      dout <= '0;
    end else begin
      dout <= dout_sr[1023:1016];
    end
  end

endmodule
