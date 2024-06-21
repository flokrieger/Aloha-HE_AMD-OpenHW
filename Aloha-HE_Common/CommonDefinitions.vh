
// IEEE 754 double precision:
`define SIGNIFICANT_BITS 52
`define EXPONENT_BITS 11
`define OVERALL_BITS 64
`define EXPONENT_BIAS 11'd1023

// Latencies:
`define DELAY_FLP_MULT 7
`define DELAY_FLP_ADDER 7
`define DELAY_COMPLEX_MULT (`DELAY_FLP_ADDER + `DELAY_FLP_MULT)