`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module RNS #(

    parameter LOGN = 13,   // max bit-size of polynomial coeficient addressing 
    parameter LOGQ = 54,   // maximum bit-size of one modulus
    parameter LOGI = 4,    // 2*4 = 16 supported different moduli

    parameter W = 24,      // word-size of WL-Montgomery reduction in bits
    parameter L = 3,       // number of stages in WL-Montgomery reduction
    parameter M = 17      // number of non-zero bits in modulus
  )
  (
    input clk,
    input rst,
    input [LOGI-1:0] modulus_select,
    input [`EXPONENT_BITS:0] scale,
    input [1:0] current_n, // 0 -> 2^13, 1 -> 2^14, 2 -> 2^15

    input [3:0] current_k,
    input [M-1:0] qm,

    // fft bram:
    output [LOGN-1:0] bram_rd_addr,
    input [`OVERALL_BITS-1:0] bram_rd_data,

    // message write bram:
    output [LOGN-1:0] bram_wr_addr,
    output [LOGQ-1:0] bram_wr_data,
    output bram_wea,

    // error polynomials brams:
    output [LOGN-1:0] e0_bram_rd_addr,
    input [5:0] e0_bram_rd_data,
    output [LOGN-1:0] e1_bram_rd_addr,
    input [5:0] e1_bram_rd_data,
    output [LOGN-1:0] v_bram_rd_addr,
    input [1:0] v_bram_rd_data,

    output [LOGN-1:0] v_bram_wr_addr,
    output [LOGQ-1:0] v_bram_wr_data,
    output v_bram_wea,
    output [LOGN-1:0] e1_bram_wr_addr,
    output [LOGQ-1:0] e1_bram_wr_data,
    output e1_bram_wea,

    // auxiliary rom:
    output [LOGI+4-1:0] rom_addr,
    input [2*`OVERALL_BITS-1:0] rom_data,

    // connection to UnifiedTransformation to reuse reduction and multiplier
    output [107:0] significant,
    output [23:0] significant_low,
    output [LOGQ-1:0] mult_factor,
    input [LOGQ-1:0] mult_result,

    output done
  );

  localparam N = 1<<LOGN;      // polynomial degree
  localparam NUM_REGIONS = LOGN == 13 ? 4 : LOGN == 14 ? 10 : 22;

  localparam BRAM_RD_LAT = 2;
  localparam ModMul_LAT = 15;
  localparam MontRed_LAT = 11 + 2; // +2 bc of two additional registers in the UnifiedTwFctGen module
  localparam ModAdd_LAT = 2;

  localparam ENTRIES_PER_MODULUS = 32;
  logic [$clog2(ENTRIES_PER_MODULUS)-1:0] rom_offset;
  assign rom_addr = {modulus_select, rom_offset[$clog2(ENTRIES_PER_MODULUS)-1:1]};
  logic rom_offset_lsb_delayed;
  DelayRegister #(.CYCLE_COUNT(BRAM_RD_LAT), .BITWIDTH(1)) rom_addr_delay (.clk(clk), .in(rom_offset[0]), .out(rom_offset_lsb_delayed));

  logic [`EXPONENT_BITS:0] scale_power_DP;
  logic [LOGQ-1:0] q;
  logic [3:0] current_k_DP;
  logic [M-1:0] q_m_DP;
  always @(posedge clk) begin
    if(rst) begin
      scale_power_DP <= scale;
      q_m_DP <= qm;
      current_k_DP <= current_k;
    end
  end
  assign q = {(13'h1fff >> (8-current_k_DP)) , q_m_DP , {(W-1){1'd0}} , 1'd1};

  //////////// address generation //////////
  logic [LOGN-1:0] read_addr_DP;
  logic done_internal;
  always_ff @(posedge clk) begin
    if(rst)
      read_addr_DP <= 0;
    else if(~done_internal)
      read_addr_DP <= read_addr_DP + 1;
  end
  assign bram_rd_addr = read_addr_DP;
  assign done_internal = read_addr_DP == (current_n == 2'd0 ? 'h1fff : current_n == 2'd1 ? 'h3fff : 'h7fff);
  DelayRegisterReset #(.BITWIDTH(1), .CYCLE_COUNT(ModMul_LAT+MontRed_LAT+BRAM_RD_LAT+ModMul_LAT+3)) done_delay (.clk(clk), .rst(rst), .in(done_internal), .out(done));


  /////// Mantissa and Exponent split-up ////////
  logic [`SIGNIFICANT_BITS:0] significant_in;
  logic [`EXPONENT_BITS-1:0] exponent_in;
  logic sign_in;
  assign significant_in = {1'd1, bram_rd_data[`SIGNIFICANT_BITS-1:0]};
  assign exponent_in = bram_rd_data[`OVERALL_BITS-2:`SIGNIFICANT_BITS];
  assign sign_in = bram_rd_data[`OVERALL_BITS-1];

  logic [`EXPONENT_BITS:0] e_unbiased;
  assign e_unbiased = exponent_in + scale_power_DP;

  logic [5:0] left_shift_values [NUM_REGIONS-1:0];
  genvar i;
  generate
    for(i = 0; i < NUM_REGIONS; i = i + 1)
      assign left_shift_values[i] = e_unbiased-(i*40);
  endgenerate
  logic [`EXPONENT_BITS:0] right_shift_value;
  assign right_shift_value = -e_unbiased-1;

  logic [$clog2(NUM_REGIONS)-1:0] multiplier_sel;
  if(LOGN == 13) begin
    // 4 regions
    assign multiplier_sel = e_unbiased < 40 || e_unbiased[`EXPONENT_BITS] == 1 ? 2'd0 :
                            e_unbiased < 80 ? 2'd1 :
                            e_unbiased < 120 ? 2'd2 : 2'd3;
  end else if(LOGN == 14) begin
    // 10 regions
    assign multiplier_sel = e_unbiased < 40 || e_unbiased[`EXPONENT_BITS] == 1 ? 4'd0 :
                            e_unbiased < 80 ? 4'd1 :
                            e_unbiased < 120 ? 4'd2 : 
                            e_unbiased < 160 ? 4'd3 : 
                            e_unbiased < 200 ? 4'd4 : 
                            e_unbiased < 240 ? 4'd5 : 
                            e_unbiased < 280 ? 4'd6 : 
                            e_unbiased < 320 ? 4'd7 : 
                            e_unbiased < 360 ? 4'd8 : 4'd9;
  end else begin // LOGN == 15
    // 22 regions
    assign multiplier_sel = e_unbiased < 40 || e_unbiased[`EXPONENT_BITS] == 1 ? 5'd0 :
                        e_unbiased < 80  ? 5'd1 :
                        e_unbiased < 120 ? 5'd2 : 
                        e_unbiased < 160 ? 5'd3 : 
                        e_unbiased < 200 ? 5'd4 : 
                        e_unbiased < 240 ? 5'd5 : 
                        e_unbiased < 280 ? 5'd6 : 
                        e_unbiased < 320 ? 5'd7 : 
                        e_unbiased < 360 ? 5'd8 : 
                        e_unbiased < 400 ? 5'd9 : 
                        e_unbiased < 440 ? 5'd10 : 
                        e_unbiased < 480 ? 5'd11 : 
                        e_unbiased < 520 ? 5'd12 : 
                        e_unbiased < 560 ? 5'd13 : 
                        e_unbiased < 600 ? 5'd14 : 
                        e_unbiased < 640 ? 5'd15 : 
                        e_unbiased < 680 ? 5'd16 : 
                        e_unbiased < 720 ? 5'd17 : 
                        e_unbiased < 760 ? 5'd18 : 
                        e_unbiased < 800 ? 5'd19 : 
                        e_unbiased < 840 ? 5'd20 : 5'd21;
  end

  /////// Pipeline stage ///////
  logic [5:0] left_shift_value_1DP;
  logic [`SIGNIFICANT_BITS:0] significant_in_1DP;
  logic e_unbiased_is_negative_1DP;
  logic [$clog2(NUM_REGIONS)-1:0] multiplier_sel_1DP;
  logic right_shift_ovf_1DP;
  logic [`SIGNIFICANT_BITS:0] significant_right_shifted_1DP;
  always_ff @(posedge clk) begin
    left_shift_value_1DP <= left_shift_values[multiplier_sel];
    significant_in_1DP <= significant_in;
    e_unbiased_is_negative_1DP <= e_unbiased[`EXPONENT_BITS];
    multiplier_sel_1DP <= multiplier_sel;
    right_shift_ovf_1DP <= right_shift_value >= 53;
    significant_right_shifted_1DP <= significant_in >> right_shift_value[5:0];
  end

  logic [91:0] significant_shifted;
  logic bit_shifted_out;
  always_comb begin
    if(e_unbiased_is_negative_1DP) begin
      significant_shifted[`SIGNIFICANT_BITS-1:0] = right_shift_ovf_1DP ? 'd0 : (significant_right_shifted_1DP >> 1);
      significant_shifted[91:`SIGNIFICANT_BITS] = 'd0;
      bit_shifted_out = right_shift_ovf_1DP ? 'd0 : significant_right_shifted_1DP[0];
    end else begin
      significant_shifted = significant_in_1DP << left_shift_value_1DP;
      bit_shifted_out = 0;
    end
  end

  ////////// Pipeline stage /////////////
  logic [91:0] significant_shifted_1DP, significant_shifted_2DP;
  logic [$clog2(NUM_REGIONS)-1:0] multiplier_sel_nDP;
  logic ovf_1DP;
  always_ff @(posedge clk) begin
    {ovf_1DP, significant_shifted_1DP[W-1:0]} <= significant_shifted[W-1:0] + bit_shifted_out;
    significant_shifted_1DP[91:W] <= significant_shifted[91:W];
    significant_shifted_2DP[W-1:0] <= significant_shifted_1DP[W-1:0];
    significant_shifted_2DP[91:`SIGNIFICANT_BITS] <= significant_shifted_1DP[91:`SIGNIFICANT_BITS]; // this is not affected by addition
    significant_shifted_2DP[`SIGNIFICANT_BITS-1:W] <= significant_shifted_1DP[`SIGNIFICANT_BITS-1:W] + ovf_1DP;
  end

  DelayRegister #(.BITWIDTH($clog2(NUM_REGIONS)), .CYCLE_COUNT(MontRed_LAT-BRAM_RD_LAT+1)) multiplier_sel_delay (.clk(clk), .in(multiplier_sel_1DP), .out(multiplier_sel_nDP));
  assign rom_offset = multiplier_sel_nDP;

  logic [LOGQ-1:0] multiplier_ina;
  assign multiplier_ina = rom_offset_lsb_delayed ? rom_data[2*LOGQ-1:LOGQ] : rom_data[LOGQ-1:0];
  
  // connection to montgomery reduction units and modmult inside UnifiedTransform
  assign significant = {16'd0, significant_shifted_2DP};
  assign significant_low = significant_shifted_1DP[W-1:0];
  assign mult_factor = multiplier_ina;

  logic sign_delayed;
  DelayRegister #(.BITWIDTH(1), .CYCLE_COUNT(ModMul_LAT+MontRed_LAT+2)) sign_delay (.clk(clk), .in(sign_in), .out(sign_delayed));
  logic [LOGQ-1:0] m_reduced, m_reduced_DP, e0_value_DP;
  assign m_reduced = sign_delayed && mult_result != 'd0 ? q-mult_result : mult_result;

  ////////// Pipeline stage /////////////
  always_ff @(posedge clk) begin
    m_reduced_DP <= m_reduced;
    e0_value_DP <= e0_bram_rd_data[5] == 1'd0 ? {49'd0, e0_bram_rd_data[4:0]} : q - e0_bram_rd_data[4:0];
  end

  ModAdd #(.K(LOGQ)) e0_adder (
    .clk(clk),
    .ina(m_reduced_DP),
    .inb(e0_value_DP),
    .q(q),
    .out(bram_wr_data)
  );

  logic valid;
  DelayRegisterReset #(.BITWIDTH(1), .CYCLE_COUNT(ModMul_LAT+MontRed_LAT+BRAM_RD_LAT+ModAdd_LAT+3)) valid_delay (.clk(clk), .rst(rst), .in(~rst), .out(valid));
  assign bram_wea = valid;

  logic [LOGN-1:0] write_addr;
  DelayRegister #(.BITWIDTH(LOGN), .CYCLE_COUNT(ModMul_LAT+MontRed_LAT+2)) e0_rd_addr_delay (.clk(clk), .in(read_addr_DP), .out(e0_bram_rd_addr));
  DelayRegister #(.BITWIDTH(LOGN), .CYCLE_COUNT(ModMul_LAT+MontRed_LAT+BRAM_RD_LAT+ModAdd_LAT+3)) write_addr_delay (.clk(clk), .in(read_addr_DP), .out(write_addr));
  assign bram_wr_addr = write_addr;

  // modular reduction of the error polynomials v and e1:
  logic [LOGN-1:0] e1_v_wr_addr, e1_v_rd_addr;
  logic e1_v_wea;
  RNSErrorPolys #(
    .N(N),
    .LOGN(LOGN),
    .LOGQ(LOGQ)
  ) rns_error_polys (
    .clk(clk),
    .rst(rst),
    .q(q),
    .read_addr_DP(read_addr_DP),
    .done_internal(done_internal),

    .error_bram_rd_addr(e1_v_rd_addr),
    .v_bram_rd_data(v_bram_rd_data),
    .e1_bram_rd_data(e1_bram_rd_data),

    .error_bram_wr_addr(e1_v_wr_addr),
    .v_bram_wr_data(v_bram_wr_data),
    .e1_bram_wr_data(e1_bram_wr_data),
    .error_bram_wea(e1_v_wea)
  );
  assign v_bram_wea = e1_v_wea;
  assign e1_bram_wea = e1_v_wea;
  assign v_bram_wr_addr = e1_v_wr_addr;
  assign e1_bram_wr_addr = e1_v_wr_addr;
  assign v_bram_rd_addr = e1_v_rd_addr;
  assign e1_bram_rd_addr = e1_v_rd_addr;


endmodule
