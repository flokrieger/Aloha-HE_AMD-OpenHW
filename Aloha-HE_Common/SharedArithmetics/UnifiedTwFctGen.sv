`timescale 1ns / 1ps
`include "CommonDefinitions.vh"

// generates twiddle factors for FFT and NTT
module UnifiedTwFctGen #(
    parameter COMPLEX_MULT_LAT = 14,
    parameter ADDR_WIDTH_ROM = 10,
    parameter LOGQ_MAX = 54,
    parameter M = 17,
    parameter NUM_MODULI = 18
  )
  (
    input clk,
    input rst,
    input is_DIF, // DIF: fFFT & iNTT; DIT: iFFT & fNTT
    input is_FFT,
    input [3:0] current_k,
    input [M-1:0] qm,
    input [$clog2(NUM_MODULI)-1:0] constants_sel,
    input [1:0] current_n,

    output [`OVERALL_BITS-1:0] tw_real,
    output [`OVERALL_BITS-1:0] tw_imag,

    output [LOGQ_MAX-1:0] tw_ntt,

    // Twiddle factor ROM:
    output [ADDR_WIDTH_ROM-1:0] rom_addr,
    input [2*`OVERALL_BITS-1:0] rom_data,

    // integer multiplier interface
    output [53:0] mult_a,
    output [53:0] mult_b,
    input [107:0] int_mult_result,
    input [23:0] int_mult_result_low
  );

  localparam N = (1<<15);

  localparam FFT_TW_BASE = 10'd896;
  localparam NTT_TW_BASE = 10'd256;
  localparam ENTRIES_PER_MODULUS = 71;

  logic [$clog2(ENTRIES_PER_MODULUS)-1:0] addr_w_32;
  assign addr_w_32 = 7'd63;
  logic [14:0] nr_bf_per_stage;
  logic [1:0] bf_ctr_mask;
  always_ff @(posedge clk) begin
    nr_bf_per_stage <= current_n == 2'd0 ? (1<<12) : current_n == 2'd1 ? (1<<13) : (1<<14);
    bf_ctr_mask <= current_n == 2'd0 ? 2'd0 : current_n == 2'd1 ? 2'd1 : 2'd3;
  end

  // counters to keep track of the transformation progress:
  logic [$clog2($clog2(N))-1:0] stage_counter;
  logic [$clog2(N)-2:0] butterfly_counter;
  logic stall;
  always_ff @(posedge clk)begin
    if(rst) begin
      butterfly_counter <= 0;
      stage_counter <= is_DIF ? 0 : current_n + 13 - 1;
    end else if(~stall) begin
      if (butterfly_counter == nr_bf_per_stage-1)
        stage_counter <= is_DIF ? stage_counter + 1 : stage_counter - 1;
      butterfly_counter <= (butterfly_counter + 1'd1) & {bf_ctr_mask,12'hfff};
    end
  end

  logic [$clog2(COMPLEX_MULT_LAT)-1:0] stall_counter;
  assign stall = is_DIF ? (stall_counter < COMPLEX_MULT_LAT)   && (stage_counter == 1) && (butterfly_counter == 0) : 
                          (stall_counter < COMPLEX_MULT_LAT+1) && (butterfly_counter == 14'd0 && stage_counter == 0);
  always_ff @(posedge clk) begin
    if (rst || ~stall)
      stall_counter = 0;
    else
      stall_counter = stall_counter + 1;
  end

  // ROM address generation:
  logic [$clog2(ENTRIES_PER_MODULUS)-1:0] rom_addr_DP, rom_addr_ifft_DN, rom_addr_next_w_c_DP;
  logic [`OVERALL_BITS-1:0] rom_data_real, rom_data_imag, rom_data_real_tmp, rom_data_imag_tmp;
  logic [LOGQ_MAX-1:0] rom_data_modring;
  assign rom_data_modring = constants_sel[0] ? rom_data[2*LOGQ_MAX-1:LOGQ_MAX] : rom_data[LOGQ_MAX-1:0];
  assign {rom_data_real_tmp, rom_data_imag_tmp} = rom_data;
  
  logic [$clog2(ENTRIES_PER_MODULUS)-1:0] rom_offset, rom_offset_compensated;
  logic [ADDR_WIDTH_ROM-1:0] rom_base_DP;
  assign rom_offset = rst ? addr_w_32 : butterfly_counter == nr_bf_per_stage - 4 ? rom_addr_next_w_c_DP : rom_addr_DP;
  always_comb begin
    rom_offset_compensated = rom_offset;
    if(current_n == 2'd1)begin
      if(rom_offset > 55)
        rom_offset_compensated = rom_offset_compensated + 8;
      if(rom_offset > 59)
        rom_offset_compensated = rom_offset_compensated + 4;
      if(rom_offset > 61)
        rom_offset_compensated = rom_offset_compensated + 2;
      if(rom_offset > 62)
        rom_offset_compensated = rom_offset_compensated + 1;
      rom_offset_compensated = rom_offset_compensated - 16;
    end else if(current_n == 2'd2)begin
      if(rom_offset > 55)
        rom_offset_compensated = rom_offset_compensated + 8;
      if(rom_offset > 59)
        rom_offset_compensated = rom_offset_compensated + 12;
      if(rom_offset > 61)
        rom_offset_compensated = rom_offset_compensated + 6;
      if(rom_offset > 62)
        rom_offset_compensated = rom_offset_compensated + 3;
      if(rom_offset > 63)
        rom_offset_compensated = rom_offset_compensated + 1;
      rom_offset_compensated = rom_offset_compensated - 32;
    end
  end
  always_ff @(posedge clk) begin
    rom_base_DP <= is_FFT ? FFT_TW_BASE : constants_sel[$clog2(NUM_MODULI)-1:1] == 0 ? NTT_TW_BASE + 0*ENTRIES_PER_MODULUS :
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 1 ? NTT_TW_BASE + 1*ENTRIES_PER_MODULUS :
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 2 ? NTT_TW_BASE + 2*ENTRIES_PER_MODULUS :
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 3 ? NTT_TW_BASE + 3*ENTRIES_PER_MODULUS :
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 4 ? NTT_TW_BASE + 4*ENTRIES_PER_MODULUS :
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 5 ? NTT_TW_BASE + 5*ENTRIES_PER_MODULUS :
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 6 ? NTT_TW_BASE + 6*ENTRIES_PER_MODULUS : 
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 7 ? NTT_TW_BASE + 7*ENTRIES_PER_MODULUS : 
                                          constants_sel[$clog2(NUM_MODULI)-1:1] == 8 ? NTT_TW_BASE + 8*ENTRIES_PER_MODULUS : 10'hXXX; 
  end
  assign rom_addr = rom_base_DP + rom_offset_compensated;

  assign rom_data_real = rom_data_real_tmp;
  assign rom_data_imag = {is_DIF ? rom_data_imag_tmp[`OVERALL_BITS-1] : ~rom_data_imag_tmp[`OVERALL_BITS-1], rom_data_imag_tmp[`OVERALL_BITS-2:0]}; // conjugate complex if iFFT

  logic advance_rom_addr;
  always_ff @(posedge clk) begin
    if(rst)
      rom_addr_DP <= is_DIF ? 7'd32 : current_n == 2'd0 ? 7'd70 : current_n == 2'd1 ? 7'd71 : 7'd72;
    else if(advance_rom_addr)
      rom_addr_DP <= is_DIF ? rom_addr_DP + 1'd1 : rom_addr_ifft_DN;

    rom_addr_next_w_c_DP <= is_DIF ? rom_addr_DP + 2'd2 : rom_addr_DP;
  end

  always_comb begin
    if (rom_addr_DP > 7'd62)
      rom_addr_ifft_DN = rom_addr_DP - 1'd1;
    else begin
      case(rom_addr_DP)
        7'd62: rom_addr_ifft_DN = 7'd60;
        7'd61: rom_addr_ifft_DN = 7'd56;
        7'd59: rom_addr_ifft_DN = 7'd48;
        7'd55: rom_addr_ifft_DN = 7'd32;
        default: rom_addr_ifft_DN = rom_addr_DP + 1'd1;
      endcase
    end
  end

  always_comb begin
    advance_rom_addr = 1'd0;
    case(stage_counter)
      4'd0: if (butterfly_counter < 4'd15 && !stall) advance_rom_addr = 1'd1;
      4'd1: if (butterfly_counter < 4'd15 && butterfly_counter[0] == 1'd1) advance_rom_addr = 1'd1;
      4'd2: if (butterfly_counter < 4'd15 && butterfly_counter[1:0] == 2'd3) advance_rom_addr = 1'd1;
      4'd3: if (butterfly_counter < 4'd15 && butterfly_counter[2:0] == 3'd7) advance_rom_addr = 1'd1;
    endcase
    if (butterfly_counter == nr_bf_per_stage - 2) 
      advance_rom_addr = 1'd1;
  end
  
  // logic when to update w_c
  logic update_w_c;
  assign update_w_c = butterfly_counter == nr_bf_per_stage - 2 && ((is_DIF && stage_counter > 4'd3) || (~is_DIF && stage_counter > 4'd4));
  logic [`OVERALL_BITS-1:0] w_c_real_DP, w_c_imag_DP;
  logic [LOGQ_MAX-1:0] w_c_modring_DP;
  always_ff @(posedge clk) begin
    if (rst || update_w_c) begin
      w_c_real_DP <= rom_data_real;
      w_c_imag_DP <= rom_data_imag;
      w_c_modring_DP <= rom_data_modring;
    end
  end

  // halting logic:
  logic halt, halt_delayed;
  always_comb begin
    halt = 1'd1;
    case(stage_counter)
      4'd0: halt = 1'd0;
      4'd1: halt = 1'd0;
      4'd2: halt = 1'd0;
      4'd3: halt = 1'd0;
      4'd4: halt = 1'd0;
      4'd5:  if(butterfly_counter[4:0] == 5'h1f) halt = 1'd0;
      4'd6:  if(butterfly_counter[5:0] == 6'h3f) halt = 1'd0;
      4'd7:  if(butterfly_counter[6:0] == 7'h7f) halt = 1'd0;
      4'd8:  if(butterfly_counter[7:0] == 8'hff) halt = 1'd0;
      4'd9:  if(butterfly_counter[8:0] == 9'h1ff) halt = 1'd0;
      4'd10: if(butterfly_counter[9:0] == 10'h3ff) halt = 1'd0;
      4'd11: if(butterfly_counter[10:0] == 11'h7ff) halt = 1'd0;
      4'd12: if(butterfly_counter[11:0] == 12'hfff || (butterfly_counter[11:0] == 12'h0 && ~is_DIF && current_n == 2'd0)) halt = 1'd0;
      4'd13: if(butterfly_counter[12:0] == 13'h1fff || (butterfly_counter[12:0] == 13'h0 && ~is_DIF && current_n == 2'd1)) halt = 1'd0;
      4'd14: if(butterfly_counter[13:0] == 14'h3fff || (butterfly_counter[13:0] == 14'h0 && ~is_DIF && current_n == 2'd2)) halt = 1'd0;
    endcase
  end
  DelayRegister #(.CYCLE_COUNT(2), .BITWIDTH(1)) halt_delay(.clk(clk), .in(halt), .out(halt_delayed));

  // combination of all things above:
  logic [`OVERALL_BITS-1:0] mult_out_real, mult_out_imag, mult_out_real_1DP, mult_out_imag_1DP;
  logic [`OVERALL_BITS-1:0] out_real, out_imag;
  logic [LOGQ_MAX-1:0] mult_out_modring, mult_out_modring_1DP;
  logic [LOGQ_MAX-1:0] out_modring;
  
  logic take_from_rom, take_from_rom_delayed;
  assign take_from_rom = butterfly_counter < 5'd16;
  DelayRegister #(.CYCLE_COUNT(2), .BITWIDTH(1)) take_from_rom_delay(.clk(clk), .in(take_from_rom), .out(take_from_rom_delayed));
  assign out_real = take_from_rom_delayed ? rom_data_real : mult_out_real_1DP;
  assign out_imag = take_from_rom_delayed ? rom_data_imag : mult_out_imag_1DP;
  assign out_modring = ~rst && take_from_rom_delayed ? rom_data_modring : mult_out_modring_1DP;

  logic [`OVERALL_BITS-1:0] out_real_DP, out_imag_DP;
  logic [LOGQ_MAX-1:0] out_modring_DP;

  always_ff @(posedge clk) begin
    out_real_DP <= out_real;
    out_imag_DP <= out_imag;
    out_modring_DP <= out_modring;

    if(!halt_delayed || rst) begin
      mult_out_real_1DP    <= butterfly_counter == 14'd1 || (butterfly_counter == 14'd2 && ~is_DIF) ? rom_data_real : mult_out_real;
      mult_out_imag_1DP    <= butterfly_counter == 14'd1 || (butterfly_counter == 14'd2 && ~is_DIF) ? rom_data_imag : mult_out_imag;
      mult_out_modring_1DP <= butterfly_counter == 14'd1 || (butterfly_counter == 14'd2 && ~is_DIF) ? rom_data_modring : mult_out_modring;
    end
  end
  

  logic [53:0] int_mult_a_gen [0:3];
  logic [53:0] int_mult_b_gen [0:3];
  logic [107:0] int_mult_result_gen [0:3];
  ComplexMultiplier complex_multiplier(
    .clk(clk),
    .a_real(w_c_real_DP),
    .a_imag(w_c_imag_DP),
    .b_real(out_real_DP),
    .b_imag(out_imag_DP),
    .a_x_b_real(mult_out_real),
    .a_x_b_imag(mult_out_imag),
    // unused:
    .start(), 
    .done(),

    // integer multiplier interface:
    .mult_a(int_mult_a_gen),
    .mult_b(int_mult_b_gen),
    .int_mult_result(int_mult_result_gen)
  );

  IntMultPool int_mult(
    .clk(clk),
    .grant_to_fft(1'd1),
    .a_fft(int_mult_a_gen),
    .b_fft(int_mult_b_gen),
    .result(int_mult_result_gen),
    // unused:
    .a_ntt(),
    .b_ntt(),
    .result_low()
  );

  ModMul modular_multiplier(    
    .clk(clk),
    .ina(w_c_modring_DP),
    .inb(out_modring), // modular multiplier has 1cc more latency than complex mult
    .q_m(qm),
    .current_k(current_k),
    .out(mult_out_modring),

    .mult_a(mult_a),
    .mult_b(mult_b),
    .int_mult_result(int_mult_result),
    .int_mult_result_low(int_mult_result_low)
  );

  assign tw_real = out_real_DP;
  assign tw_imag = out_imag_DP;
  assign tw_ntt = out_modring_DP;



endmodule