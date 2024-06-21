#include <inttypes.h>
#include <math.h>
#include <stdio.h>

int compareDouble(double a, double b, double eps)
{
	if(a == 0.0 || a == -0.0)
		return b < eps;
	else if(b == 0.0 || b == -0.0)
		return a < eps;
	else
	{
		double tmp = b/a - 1.0;
		tmp = tmp < 0.0 ? -tmp : tmp;
		return tmp < eps;
	}
}

int checkPoly(uint64_t* res, uint64_t* ref, int size, const char* poly_name, int modulus_nr, int64_t delta_max)
{
	int error = 0;
	for(int i = 0; i < size; ++i)
	{
		int64_t delta = res[i] - ref[i];
		if(delta > delta_max || delta < -delta_max){
			if(error<10)
				printf("Error: modulus %d: %s[%d]: result: %llx, expected: %llx\n",modulus_nr,poly_name,i,res[i], ref[i]);
			error++;
		}
	}
	return error != 0;
}

int checkPolyFFT(uint64_t* res, uint64_t* ref, int size, int is_forward_fft, const char* poly_name, double eps, int32_t scale)
{
	int error = 0;
	if(is_forward_fft){
		for(int i = 0; i < size; ++i)
		{
			double a = *(double*)&(res[i*2]);
			a *= pow(2.0, 1.0*scale) / size;
			double b = *(double*)&(ref[i*2]);
			if(!compareDouble(a, b, eps)){
				if(error<10)
					printf("Error FFT: %s[%d]: result: %llx (%lf), expected: %llx (%lf)\n",poly_name,i,res[i*2],a, ref[i*2],b);
				error++;
			}
		}
	}
	else
	{
		for(int i = 0; i < size*2; ++i)
		{
			double a = *(double*)&(res[i]);
			double b = *(double*)&(ref[i]);
			if(!compareDouble(a, b, eps)){
				if(error<10)
					printf("Error FFT: %s[%d] %s : result: %llx (%lf), expected: %llx (%lf)\n",poly_name,i/2, i % 2 ? "im" : "re", res[i],a, ref[i],b);
				error++;
			}
		}
	}
	return error != 0;
}
