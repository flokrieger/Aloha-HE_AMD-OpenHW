#ifndef SRC_CKKS_ACCELERATOR_H_
#define SRC_CKKS_ACCELERATOR_H_

#include <stdint.h>

void ckks_encrypt(uint64_t** ciphertext0, uint64_t** ciphertext1, uint64_t* plaintext, uint32_t poly_size, uint64_t error_polys_seed,
				  uint64_t* pk1_seeds, uint8_t num_moduli, uint32_t* ntt_modulus_rom_indices,
				  uint32_t* rns_modulus_rom_indices, uint64_t** pk0, int32_t log_scale, uint32_t* qm,
				  uint32_t* log_q);
void ckks_decrypt(uint64_t* c0, uint64_t* c1, uint64_t* sk, uint64_t* plaintext, uint32_t poly_size, uint32_t qm, uint8_t log_q,
		          uint8_t ntt_modulus_rom_index, int32_t log_scale);
void ckks_init(uint8_t current_n);

#endif /* SRC_CKKS_ACCELERATOR_H_ */
