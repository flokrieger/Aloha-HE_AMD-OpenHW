#include <stdio.h>
#include "instrTest.h"
#include "xil_cache.h"
#include "../communication.h"
#include "../instruction.h"


uint32_t fft_HW(uint64_t *result, uint64_t *input, uint32_t do_forw_transf, int skip, uint64_t seed, uint8_t current_n)
{
	uint32_t poly_degree = 1<<(13+current_n);
	uint32_t fpga_cycle_count = 0;
	uint64_t INS[INS_BUFFER_SIZE];

	uint32_t is_dif = do_forw_transf;

	uint64_t ins_word = getFFTTransformationInstructionWord(is_dif,current_n);
	initInsBuffer(INS, &ins_word, 1);

	if(input){
		send64Expand(input, do_forw_transf ? poly_degree : poly_degree*2, 0, do_forw_transf ? FFT_BRAM_EXPAND_ID : FFT_BRAM_ID, current_n);
	}

	if(!skip){
		send64(INS, INS_BUFFER_SIZE, 1, 0);
		fpga_cycle_count = exeInsWithParameter(seed);
	}

	if(result){
		receive64(result, 2*poly_degree, FFT_BRAM_ID);
	}
	return fpga_cycle_count;
}

uint32_t rns_HW(uint64_t *result_message, uint64_t* result_v, uint64_t* result_e1, uint64_t *input, int skip_rns, uint32_t modulus_select, int32_t scale, uint32_t qm, uint32_t current_k, uint8_t current_n)
{
	while(scale < -(1<<8) || scale >= (1<<8))
		printf("Scale out of bounds!\n");

	uint32_t poly_degree = 1<<(13+current_n);
	uint64_t INS[INS_BUFFER_SIZE];
	uint32_t fpga_cycle_count = 0;

	scale = scale - 52 - 1023 - (13+current_n); // -13 bc of scaling factor of 1/N
	if(scale < 0)
		scale += 4096; // 2^12

	uint64_t ins_word = getRNSInstructionWord(scale, current_k, modulus_select, qm, current_n);
	initInsBuffer(INS, &ins_word, 1);

	if(input != NULL){
		send64(input, 2*poly_degree, 0, FFT_BRAM_ID);
	}


	if(!skip_rns){
		send64(INS, INS_BUFFER_SIZE, 1, 0);
		fpga_cycle_count = exeIns();
	}

	if(result_message){
		receive64(result_message, poly_degree, NTT_MSG_BRAM_ID);
	}
	if(result_v){
		receive64(result_v, poly_degree, NTT_V_BRAM_ID);
	}
	if(result_e1){
		receive64(result_e1, poly_degree, NTT_E1_BRAM_ID);
	}

	return fpga_cycle_count;
}

uint32_t ntt_HW(uint64_t *result, uint64_t *input, uint32_t qm, uint32_t current_k, uint32_t constants_select, uint32_t do_forw_transf, uint32_t bram_sel, int skip, uint64_t seed, uint8_t current_n)
{
	uint32_t poly_degree = 1<<(13+current_n);
	uint32_t fpga_cycle_count = 0;
	uint64_t INS[INS_BUFFER_SIZE];

	uint32_t is_dif = do_forw_transf ? 0 : 1;

	uint64_t ins_word = getNTTTransformationInstructionWord(is_dif, current_k, constants_select, qm, current_n);
	initInsBuffer(INS, &ins_word, 1);

	if(input) {
		send64(input, poly_degree, 0, bram_sel);
	}

	if(!skip){
		send64(INS, INS_BUFFER_SIZE, 1, 0);
		fpga_cycle_count = exeInsWithParameter(seed);
	}

	if(result){
		receive64(result, poly_degree, bram_sel);
	}

	return fpga_cycle_count;
}

uint32_t i2f_HW(uint64_t *result, uint64_t *input, uint32_t qm, uint32_t current_k, int32_t scale, uint8_t current_n)
{
	while(scale < -(1<<8) || scale >= (1<<8))
		printf("Scale out of bounds!\n");

	uint32_t poly_degree = 1<<(13+current_n);
	uint32_t fpga_cycle_count = 0;
	uint64_t INS[INS_BUFFER_SIZE];

	uint64_t ins_word = getI2FInstructionWord(scale, current_k, qm, current_n);
	initInsBuffer(INS, &ins_word, 1);

	if(input){
		send64(input, poly_degree, 0, NTT_MSG_BRAM_ID);
	}


	send64(INS, INS_BUFFER_SIZE, 1, 0);
	fpga_cycle_count = exeIns();

	if(result){
		receive64(result, 2*poly_degree, FFT_BRAM_ID);
	}

	return fpga_cycle_count;
}

uint32_t pwm_HW(uint64_t *result_c0_m, uint64_t *result_c1, uint64_t *v_sk_poly, uint64_t *pk0_c1_poly, uint64_t *pk1_poly, uint64_t *msg_c0_poly, uint64_t *e1_poly, uint32_t qm, uint32_t current_k, uint8_t current_n)
{
	uint32_t fpga_cycle_count = 0;
	uint32_t poly_degree = 1<<(13+current_n);
	uint64_t INS[INS_BUFFER_SIZE];

	uint64_t ins_word = getPWMInstructionWord(current_k, qm, current_n);
	initInsBuffer(INS, &ins_word, 1);

	if(v_sk_poly){
		send64(v_sk_poly, poly_degree, 0, NTT_V_BRAM_ID);
	}
	if(pk0_c1_poly){
		send64(pk0_c1_poly, poly_degree, 0, NTT_KEY_BRAM_ID);
	}
	if(pk1_poly){
		send64(pk1_poly, poly_degree, 0, FFT_IM_BRAM_ID);
	}
	if(msg_c0_poly){
		send64(msg_c0_poly, poly_degree, 0, NTT_MSG_BRAM_ID);
	}
	if(e1_poly){
		send64(e1_poly, poly_degree, 0, NTT_E1_BRAM_ID);
	}

	send64(INS, INS_BUFFER_SIZE, 1, 0);
	fpga_cycle_count = exeIns();

	if(result_c1){
		receive64(result_c1, poly_degree, NTT_KEY_BRAM_ID);
	}
	if(result_c0_m){
		receive64(result_c0_m, poly_degree, NTT_MSG_BRAM_ID);
	}

	return fpga_cycle_count;
}

uint32_t prj_HW(uint64_t* result, uint64_t* input, uint8_t current_n)
{
	uint32_t poly_degree = 1<<(13+current_n);

	uint64_t INS[INS_BUFFER_SIZE];
	uint64_t instr = getProjectInstructionWord(current_n);
	initInsBuffer(INS, &instr, 1);
	if(input)
		send64(input, 2*poly_degree, 0, FFT_BRAM_ID);

	send64(INS, INS_BUFFER_SIZE, 1, 0);
	uint32_t fpga_cycle_count = exeIns();

	if(result)
	{
		uint64_t tmp[2*(1<<15)];
		receive64(tmp, 2*(1<<15), FFT_BRAM_ID);
		for(uint32_t i = 0; i < poly_degree; ++i)
			result[i] = tmp[i+(1<<15)];
	}
	return fpga_cycle_count;
}

void getMessageAfterRns(int poly_size, uint64_t* e0_poly, uint64_t** message_after_rns, uint64_t num_moduli, uint32_t* current_k, uint32_t* qm)
{
	static char already_done = 0;
	if(already_done)
		return;

	uint64_t* e0 = e0_poly;
	for(uint32_t j = 0; j < num_moduli; ++j)
	{
		uint64_t q = (1ull << (46+current_k[j])) - (qm[j] << 24) + 1;
		int64_t* m = (int64_t*)message_after_rns[j];
		for(int i = 0; i < poly_size; i++)
		{
			if(e0[i] & (1<<5))
				m[i] = m[i] - (e0[i] & 0x1f);
			else
				m[i] = m[i] + (e0[i] & 0x1f);

			if(m[i] >= (int64_t)q)
				m[i] -= q;
			else if(m[i] < 0)
				m[i] += q;
		}
	}
	already_done = 1;
}

void recvErrorPolys_HW(uint64_t *v, uint64_t *e0, uint64_t* e1, uint8_t current_n)
{
	uint32_t poly_degree = 1<<(13+current_n);
	uint64_t combined[poly_degree];

	receive64(combined, poly_degree, ERROR_BRAM_ID);

	for (uint32_t i = 0; i < poly_degree; ++i)
	{
		v[i] = (combined[i] >> 12) & 0x3;
		e0[i] = (combined[i] >> 6) & 0x3f;
		e1[i] = (combined[i]) & 0x3f;
	}
}

