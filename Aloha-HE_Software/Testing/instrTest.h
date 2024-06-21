#ifndef SRC_INSTRTEST_H_
#define SRC_INSTRTEST_H_

#include <inttypes.h>

uint32_t fft_HW(uint64_t *result, uint64_t *input, uint32_t do_forw_transf, int skip, uint64_t seed, uint8_t current_n);
uint32_t rns_HW(uint64_t *result_message, uint64_t* result_v, uint64_t* result_e1, uint64_t *input, int skip_rns, uint32_t modulus_select, int32_t scale, uint32_t qm, uint32_t current_k, uint8_t current_n);
uint32_t ntt_HW(uint64_t *result, uint64_t *input, uint32_t qm, uint32_t current_k, uint32_t constants_select, uint32_t do_forw_transf, uint32_t bram_sel, int skip, uint64_t seed, uint8_t current_n);
uint32_t i2f_HW(uint64_t *result, uint64_t *input, uint32_t qm, uint32_t current_k, int32_t scale, uint8_t current_n);
uint32_t pwm_HW(uint64_t *result_c0_m, uint64_t *result_c1, uint64_t *v_sk_poly, uint64_t *pk0_c1_poly, uint64_t *pk1_poly, uint64_t *msg_c0_poly, uint64_t *e1_poly, uint32_t qm, uint32_t current_k, uint8_t current_n);
uint32_t prj_HW(uint64_t* result, uint64_t* input, uint8_t current_n);

void getMessageAfterRns(int poly_size, uint64_t* e0_poly, uint64_t** message_after_rns, uint64_t num_moduli, uint32_t* current_k, uint32_t* qm);
void recvErrorPolys_HW(uint64_t *v, uint64_t *e0, uint64_t* e1, uint8_t current_n);

#endif
