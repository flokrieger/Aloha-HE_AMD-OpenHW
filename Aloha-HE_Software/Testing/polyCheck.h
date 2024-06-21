#ifndef SRC_POLYCHECK_H_
#define SRC_POLYCHECK_H_

#include <inttypes.h>

int compareDouble(double a, double b, double eps);
int checkPoly(uint64_t* res, uint64_t* ref, int size, const char* poly_name, int modulus_nr, int64_t delta_max);
int checkPolyFFT(uint64_t* res, uint64_t* ref, int size, int is_forward_fft, const char* poly_name, double eps, int32_t scale);

#endif
