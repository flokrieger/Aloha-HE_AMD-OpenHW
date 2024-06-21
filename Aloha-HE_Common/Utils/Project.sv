`timescale 1ns / 1ps

module Project #(
    parameter LOGN         = 13,
    parameter FLP_WORDSIZE = 64,
    parameter BRAM_RD_LAT  = 2
  )
  (
    input clk,
    input rst,
    input[1:0] current_n,

    output [LOGN-2:0]           fft_rd_addr,
    output [LOGN-2:0]           fft_wr_addr,
    output                      fft_bank0_wea,
    output                      fft_bank1_wea,
    input  [2*FLP_WORDSIZE-1:0] fft_bank0_rd_data,
    input  [2*FLP_WORDSIZE-1:0] fft_bank1_rd_data,
    output [2*FLP_WORDSIZE-1:0] fft_wr_data,

    output done
  );

  localparam LOGM = LOGN+1;
  localparam M = 2**LOGM;

  logic done_internal_1DP, done_internal_2DP;
  logic [LOGM-1:0] pos_ctr_DP,pos_ctr_DN;
  logic [1:0] pos_ctr_mask;
  logic [LOGN-2:0] dest_addr_DP;
  logic [LOGN-1:0] n_minus_one;
  assign pos_ctr_DN = (pos_ctr_DP << 1) + pos_ctr_DP;
  always_ff @(posedge clk) begin
    if(rst) begin
      pos_ctr_DP <= 'd1;
      dest_addr_DP <= 14'h3ffe;
    end else if(~done_internal_2DP) begin 
      pos_ctr_DP[LOGM-3:0] <= pos_ctr_DN[LOGM-3:0];
      pos_ctr_DP[LOGM-1:LOGM-2] <= pos_ctr_DN[LOGM-1:LOGM-2] & pos_ctr_mask;
      dest_addr_DP <= dest_addr_DP + 'd1;
    end
    pos_ctr_mask <= current_n == 2'd0 ? 2'd0 : current_n == 2'd1 ? 2'd1 : 2'd3;
    n_minus_one <= current_n == 2'd0 ? (1<<13)-1 : current_n == 2'd1 ? (1<<14)-1 : (1<<15)-1;
  end

  always_ff @(posedge clk)begin
    if(rst) begin
      done_internal_1DP <= 'd0;
      done_internal_2DP <= 'd0;
    end else begin
      if(dest_addr_DP[LOGN-4:0] == 14'hffd && (current_n == 2'd0 || (dest_addr_DP[LOGN-3] && (current_n == 2'd1 || dest_addr_DP[LOGN-2]))))
        done_internal_1DP <= 'd1;
      done_internal_2DP <= done_internal_1DP; 
    end
  end

  logic [LOGN-1:0] rd_index,rd_index_unshifted;
  logic [LOGM-1:0] br_in;
  assign br_in = pos_ctr_DP-1'd1;
  BitReverse #(.BITWIDTH(LOGN)) index_reverse (.in(br_in[LOGM-1:1]), .out(rd_index_unshifted));
  assign rd_index = current_n == 2'd0 ? (rd_index_unshifted >> 2) : current_n == 2'd1 ? (rd_index_unshifted >> 1) : rd_index_unshifted; 

  logic [LOGN-2:0] rd_addr_tmp;
  logic rd_index_msb;
  assign rd_index_msb = rd_index[current_n == 2'd2 ? LOGN-1 : current_n == 2'd1 ? LOGN-2 : LOGN-3];
  assign rd_addr_tmp = rd_index_msb == 0 ? rd_index : n_minus_one - rd_index;
  assign fft_rd_addr = {1'd0, rd_addr_tmp[LOGN-2:1]};
  logic rd_bank_sel, conjugate;
  DelayRegister #(.CYCLE_COUNT(BRAM_RD_LAT), .BITWIDTH(2)) delay (.clk(clk), .in({rd_index_msb, rd_addr_tmp[0]}), .out({conjugate, rd_bank_sel}));

  logic [2*FLP_WORDSIZE-1:0] fft_wr_data_tmp;
  assign fft_wr_data_tmp = (rd_bank_sel ? fft_bank1_rd_data : fft_bank0_rd_data);
  assign fft_wr_data = fft_wr_data_tmp ^ (conjugate<<63);
  
  assign fft_wr_addr = {1'd1, dest_addr_DP[LOGN-2:1]};

  logic wea_internal;
  DelayRegisterReset #(.CYCLE_COUNT(BRAM_RD_LAT), .BITWIDTH(1)) delay1 (.clk(clk), .rst(rst | done_internal_2DP), .in(~done_internal_2DP), .out(wea_internal));
  assign done = done_internal_2DP;

  assign fft_bank0_wea = wea_internal && ~dest_addr_DP[0];
  assign fft_bank1_wea = wea_internal &&  dest_addr_DP[0];
endmodule
