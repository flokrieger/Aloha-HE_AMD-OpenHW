`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

module Expand #(
    parameter LOGN = 13
  )
  (
    input clk,
    input rst,

    input do_expand,
    input[1:0] current_n,

    // software interface:
    input [LOGN-1:0]            addr_from_sw,
    input [2*`OVERALL_BITS-1:0] data_from_sw,
    input                       wea_from_sw, // this wont stay high for more than 1cc (re and im part are sent separately)

    // FFT BRAM banks:
    output [LOGN-2:0]            wr_addr_bank0,
    output [2*`OVERALL_BITS-1:0] wr_data_bank0,
    output                       wea_bank0,
    output [LOGN-2:0]            wr_addr_bank1,
    output [2*`OVERALL_BITS-1:0] wr_data_bank1,
    output                       wea_bank1
  );

  localparam LOGM = LOGN+1;

  logic [LOGM-1:0] m_minus_1;
  logic [1:0] pos_ctr_mask;
  always @(posedge clk) begin
    m_minus_1    <= current_n == 2'd0 ? 'h3fff : current_n == 2'd1 ? 'hffff : 'hffff;
    pos_ctr_mask <= current_n == 2'd0 ? 2'd0 : current_n == 2'd1 ? 2'd1 : 2'd3;
  end

  logic wea_from_sw_1DP, update_counter, wea_internal;
  logic [LOGM-1:0] pos_ctr_DP,pos_ctr_DN;
  assign pos_ctr_DN = (pos_ctr_DP << 1) + pos_ctr_DP;
  always_ff @(posedge clk) begin
    wea_from_sw_1DP <= wea_from_sw;
    update_counter <= wea_internal;

    if(rst)
      pos_ctr_DP <= 'd1;
    else if(update_counter) begin
      pos_ctr_DP[LOGM-3:0] <= pos_ctr_DN[LOGM-3:0];
      pos_ctr_DP[LOGM-1:LOGM-2] <= pos_ctr_DN[LOGM-1:LOGM-2] & pos_ctr_mask;
    end
  end

  assign wea_internal = wea_from_sw_1DP == 'd0 && wea_from_sw == 'd1;
  assign wea_bank0 = do_expand ? wea_internal : wea_from_sw && addr_from_sw[0] == 0;
  assign wea_bank1 = do_expand ? wea_internal : wea_from_sw && addr_from_sw[0] == 1;

  logic [LOGN-1:0] index0, index1, index0_unshifted, index1_unshifted;
  logic [LOGM-1:0] br_in0, br_in1;
  assign br_in0 = pos_ctr_DP-1'd1;
  assign br_in1 = m_minus_1-pos_ctr_DP;
  BitReverse #(.BITWIDTH(LOGN)) index0_reverse (.in(br_in0[LOGM-1:1]), .out(index0_unshifted));
  BitReverse #(.BITWIDTH(LOGN)) index1_reverse (.in(br_in1[LOGM-1:1]), .out(index1_unshifted));
  assign index0 = current_n == 2'd0 ? (index0_unshifted >> 2) : current_n == 2'd1 ? (index0_unshifted >> 1) : index0_unshifted; 
  assign index1 = current_n == 2'd0 ? (index1_unshifted >> 2) : current_n == 2'd1 ? (index1_unshifted >> 1) : index1_unshifted; 
  //always_ff @(posedge clk) assert(index0[0] != index1[0] || rst);
  
  logic switch_brams;
  assign switch_brams = index0[0];
  assign wr_addr_bank0 = do_expand ? (switch_brams ? index1[LOGN-1:1] : index0[LOGN-1:1]) : addr_from_sw[LOGN-1:1];
  assign wr_addr_bank1 = do_expand ? (switch_brams ? index0[LOGN-1:1] : index1[LOGN-1:1]) : addr_from_sw[LOGN-1:1];

  assign wr_data_bank0 = {data_from_sw[2*`OVERALL_BITS-1:`OVERALL_BITS], do_expand ? (data_from_sw[`OVERALL_BITS-1] ^  switch_brams) : data_from_sw[`OVERALL_BITS-1], data_from_sw[`OVERALL_BITS-2:0]};
  assign wr_data_bank1 = {data_from_sw[2*`OVERALL_BITS-1:`OVERALL_BITS], do_expand ? (data_from_sw[`OVERALL_BITS-1] ^ ~switch_brams) : data_from_sw[`OVERALL_BITS-1], data_from_sw[`OVERALL_BITS-2:0]};

endmodule
