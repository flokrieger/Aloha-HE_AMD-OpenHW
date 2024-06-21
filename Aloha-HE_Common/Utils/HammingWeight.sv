`timescale 1ns / 1ps
`include "CommonDefinitions.vh"


module HammingWeight(
    input  [20:0] in,
    output [4:0]  out
  );

  logic [4:0] result;
  integer j;
  always_comb begin
    result = 'd0;
    for(j = 0; j < 21; j = j+1) begin
      result = result + in[j];
    end
  end
  assign out = result;
endmodule