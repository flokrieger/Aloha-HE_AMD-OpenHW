/****************************************
 * Testing and Verification Code
 *
 * This file contains functionality
 * for testing the design.
 ***************************************/

#include "xparameters.h"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include "xil_cache.h"
#include "../communication.h"
#include "../instruction.h"
#include "../xtime_l.h"
#include "../ckksAccelerator.h"
#include "instrTest.h"
#include "polyCheck.h"



/* Test and benchmark end-to-end encode+encrypt and decrypt+decode. */
#define FAST_ALOHA 			// Runs end-to-end encode+encrypt and decrypt+decode without intermediate checks but with execution timing
#define TEST_ALOHA     	// Tests a full encode+encrypt and decrypt+decode procedure and validates all intermediate results
#define POLY_DEGREE 15  // select the polynomial degree to test (13, 14, or 15)

#if POLY_DEGREE == 13
#include "referenceEncryption13.h"
#include "referenceDecryption13.h"
#elif POLY_DEGREE == 14
#include "referenceEncryption14.h"
#include "referenceDecryption14.h"
#else
#include "referenceEncryption15.h"
#include "referenceDecryption15.h"
#endif
/***************************************************************************************************/


const uint64_t CPU_FREQ_MHZ = 150;    // clock frequency of host CPU
const uint64_t COPROC_FREQ_MHZ = 150; // clock frequency of co-processor

#define ALIGN __attribute__((aligned(1<<15)))

char testAloha()
{
  char error = 0;

  int poly_size = 1<<(13+current_n);
	uint64_t result_fft[2*poly_size] ALIGN;
	uint64_t result[poly_size];
	int64_t rns_delta_max = 1;
	const double eps_fft = pow(2,-25);

  printf("Preparing test vectors... ");
	getMessageAfterRns(poly_size, e0_poly, message_after_rns, num_moduli, current_k, qm);
  printf(" Done\n");

  /////////////// Start of Encoding ///////////////
  // send message to be encrypted:
	cdmaDDRtoBRAM(FFT_BRAM_ID, (size_t)input, poly_size*sizeof(uint64_t), current_n);
	cdmaWaitForIdle();

	// receive expanded message:
  receive64(result_fft, 2*poly_size, FFT_BRAM_ID);
  error |= checkPoly(result_fft, expanded_input,poly_size*2,"expand result",0, 0);

  // perform FFT and concurrent error sampling:
	fft_HW(result_fft, NULL, 1, 0, error_polys_seed, current_n);

  // check FFT result and error sampling result:
  uint64_t result1[poly_size];
  error |= checkPolyFFT(result_fft, fft_expected,poly_size,1,"fft result", eps_fft, scale);
  recvErrorPolys_HW(result, result_fft, result1, current_n);
  error |= checkPoly(result, v_poly,poly_size,"v result", 0, 0);
  error |= checkPoly(result_fft, e0_poly,poly_size,"e0 result", 0, 0);
  error |= checkPoly(result1, e1_poly,poly_size,"e1 result", 0, 0);

  /////////////// Start of Encryption ///////////////

	for(uint32_t modulus_index = 0; modulus_index < num_moduli; ++modulus_index)
	{
    // Send public key 0:
		cdmaDDRtoBRAM(NTT_KEY_BRAM_ID, (size_t)pk0[modulus_index], poly_size*sizeof(uint64_t), 0);
		cdmaWaitForIdle();

    // perform RNS step and check result:
		rns_HW(result, NULL, NULL, NULL, 0, modulus_select[modulus_index], scale, qm[modulus_index], current_k[modulus_index], current_n);
    error |= checkPoly(result, message_after_rns[modulus_index],poly_size,"encoded_message",modulus_index, rns_delta_max);
		int ntt_constants = constants_select[modulus_index];
		if(ntt_constants == 15)
			ntt_constants = 16;

    // perform NTT and check NTT results:
		ntt_HW(result, message_after_rns[modulus_index], qm[modulus_index], current_k[modulus_index], ntt_constants, 1, NTT_MSG_BRAM_ID, 0, pk1_seeds[modulus_index], current_n);
    ntt_HW(result, NULL, 0, 0, 0, 0, NTT_V_BRAM_ID, 1, 0, current_n); // this just receives the ntt transformed v poly
    error |= checkPoly(result, v_poly_ntt[modulus_index],poly_size,"v_poly_ntt",modulus_index, 0);
    ntt_HW(result, NULL, 0, 0, 0, 0, NTT_E1_BRAM_ID, 1, 0, current_n); // this just receives the ntt transformed e1 poly
    error |= checkPoly(result, e1_poly_ntt[modulus_index],poly_size,"e1_poly_ntt",modulus_index, 0);
		
		// check generated pk1:
    receive64(result, poly_size, FFT_IM_BRAM_ID);
    error |= checkPoly(result, pk1[modulus_index],poly_size,"sampled pk1",modulus_index, 0);

		// perform point-wise multiplication
    pwm_HW(NULL, NULL, NULL, NULL, NULL, NULL, NULL, qm[modulus_index], current_k[modulus_index], current_n);

    // receive ciphertexts for current prime
		cdmaBRAMtoDDR((size_t)result_c0[modulus_index], NTT_MSG_BRAM_ID, poly_size*sizeof(uint64_t));
		cdmaWaitForIdle();
		cdmaBRAMtoDDR((size_t)result_c1[modulus_index], NTT_KEY_BRAM_ID, poly_size*sizeof(uint64_t));
		cdmaWaitForIdle();
	}

  // validate correctness of ciphertexts:
	for(uint32_t modulus_index = 0; modulus_index < num_moduli; ++modulus_index)
	{
		error |= checkPoly(result_c1[modulus_index], expected_c1[modulus_index], poly_size, "C1", modulus_index, 0);
		error |= checkPoly(result_c0[modulus_index], expected_c0[modulus_index], poly_size, "C0", modulus_index, 0);
	}

  printf("Testing Encryption Done\n");

  /////////////// Start of Decryption ///////////////
  // Send ciphertext and secret key:
	cdmaDDRtoBRAM(NTT_MSG_BRAM_ID, (size_t)c0_to_decrypt, poly_size*sizeof(uint64_t), 0);
	cdmaWaitForIdle();
	cdmaDDRtoBRAM(NTT_KEY_BRAM_ID, (size_t)c1_to_decrypt, poly_size*sizeof(uint64_t), 0);
	cdmaWaitForIdle();
	cdmaDDRtoBRAM(NTT_V_BRAM_ID, (size_t)sk, poly_size*sizeof(uint64_t), 0);
	cdmaWaitForIdle();

  // check whether sending ciphertexts and secret key works:
  receive64(result,poly_size,NTT_MSG_BRAM_ID);
  error |= checkPoly(result, c0_to_decrypt, poly_size, "sent c0", 0, 0);
  receive64(result,poly_size,NTT_KEY_BRAM_ID);
  error |= checkPoly(result, c1_to_decrypt, poly_size, "sent c1", 0, 0);
  receive64(result,poly_size,NTT_V_BRAM_ID);
  error |= checkPoly(result, sk, poly_size, "sent sk", 0, 0);

  // perform point-wise multiplication and check result:
	pwm_HW(result, NULL, NULL, NULL, NULL, NULL, NULL, qm[0], current_k[0], current_n);
  error |= checkPoly(result, decrypted_m_ntt, poly_size, "decrypted msg", 0, 0);

  // perform inverse NTT and check result:
	ntt_HW(result, NULL, qm[0], current_k[0], constants_select[0] == 15 ? 17 : 15, 0, NTT_MSG_BRAM_ID, 0, 0, current_n);
  error |= checkPoly(result, intt_m_reference, poly_size, "intt result", 0, 0);

  // convert integers back to floating-point domain and check result:
	i2f_HW(result_fft, NULL, qm[0], current_k[0], -scale, current_n);
  error |= checkPolyFFT(result_fft, ifft_input, poly_size,0, "ifft input", eps_fft, scale);

  // perform inverse fft and check result:
	fft_HW(result_fft, NULL, 0, 0, 0, current_n);
  error |= checkPolyFFT(result_fft, ifft_reference, poly_size,0, "ifft output", eps_fft, scale);

  // perform the projection in hardware and receive decrypted and decoded message:
	prj_HW(NULL, NULL, current_n);

	cdmaBRAMtoDDR((size_t)result_fft, FFT_BRAM_ID, poly_size*sizeof(uint64_t));
	cdmaWaitForIdle();

	error |= checkPolyFFT(result_fft, projected_reference, poly_size/2,0, "projected output", eps_fft, scale);

  printf("Testing Decryption Done\n");

  return error;
}

void fastAloha()
{
  XTime tStart = 0, tEnd = 0;
	int poly_size = 1<<(13+current_n);
	uint64_t result_fft[2*poly_size] ALIGN;

	// initialize the accelerator:
  ckks_init(current_n);

  // perform encoding and encryption without intermediate tests & measure execution time
	XTime_GetTime(&tStart);
	ckks_encrypt(result_c0, result_c1, input, poly_size, error_polys_seed, pk1_seeds, num_moduli, constants_select, modulus_select, pk0, scale, qm, current_k);
	XTime_GetTime(&tEnd);
	printf("Encode+encrypt in hardware took %llu CPU cc -> %.0lf us\n",2*(tEnd-tStart), 2.0*(tEnd-tStart)/CPU_FREQ_MHZ);

  // perform decryption and decoding without intermediate tests & measure execution time
	XTime_GetTime(&tStart);
	ckks_decrypt(c0_to_decrypt, c1_to_decrypt, sk, result_fft, poly_size, qm[0], current_k[0], constants_select[0], -scale);
	XTime_GetTime(&tEnd);
  printf("Decode+decrypt in hardware took %llu CPU cc -> %.0lf us\n",2*(tEnd-tStart), 2.0*(tEnd-tStart)/CPU_FREQ_MHZ);
}

void test_hardware(){
	XTime tStart = 0, tEnd = 0;
	char error = 0;

	XTime_GetTime(&tStart);

#if defined(TEST_ALOHA)
  error |= testAloha();
#endif

#if defined(FAST_ALOHA)
  fastAloha();  
#endif

	XTime_GetTime(&tEnd);

	printf("Overall test in hardware took %llu CPU cc -> %.0lf us\n",2*(tEnd-tStart), 2.0*(tEnd-tStart)/CPU_FREQ_MHZ);
	if(error){
		printf("#################################\n");
		printf("# ERRORS OCCURED DURING TESTING #\n");
		printf("#################################\n");
	}
	else{
		printf("#################################\n");
		printf("#              OK!              #\n");
		printf("#################################\n");
	}
}

void demo()
{
  int poly_size = 1<<(13+current_n);
  ckks_init(current_n);

  XTime tStart = 0, tEnd = 0;
  XTime_GetTime(&tStart);
  for(int k = 0; k < 1000; k++)
	{
		ckks_encrypt(result_c0, result_c1, input, poly_size, error_polys_seed, pk1_seeds, num_moduli, constants_select, modulus_select, pk0, scale, qm, current_k);
		if (k % 25 == 0 && k != 0)
    {
      XTime_GetTime(&tEnd);
      printf("Done %u Encode+Encrypt in %.0lf seconds\n",k,2.0*(tEnd-tStart)/CPU_FREQ_MHZ/1000000);
    }
	}	
}

// Simple test to verify correct timer configuration.
void test_timing()
{
	printf("\n\nStart timing test\n\n");
	XTime start, end;
	XTime_GetTime(&start);
	for(uint32_t i = 0; i < (1<<27); ++i)
		;
	XTime_GetTime(&end);
	printf("Time consumed: %llu cpu cc, %.0f us\n",2*(end-start), 2.0*(end-start)/CPU_FREQ_MHZ);
}
