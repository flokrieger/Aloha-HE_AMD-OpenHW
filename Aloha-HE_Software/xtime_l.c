/***************************************
 * Timer infrastructure to measure time
 ***************************************/

#include "xtime_l.h"
#include "xil_io.h"

#define TCSR0 0x0
#define TLR0  0x4
#define TCR0  0x8
#define TLR1  0x14
#define TCR1  0x18

void initTimer()
{
	uint32_t val;
	val = 0;
	Xil_Out32(XPAR_AXI_TIMER_0_BASEADDR + TLR0, val);
	Xil_Out32(XPAR_AXI_TIMER_0_BASEADDR + TLR1, val);

	val = 	(1<<11) | // enable cascade
			(1<<5)  | // load value
			(1<<4)  ; // reload value
	Xil_Out32(XPAR_AXI_TIMER_0_BASEADDR + TCSR0, val);

	val |= (1<<10); // enable timers
	val &= ~(1<<5); // prevents timer from running
	Xil_Out32(XPAR_AXI_TIMER_0_BASEADDR + TCSR0, val);
}

void XTime_GetTime(XTime* t)
{
	uint32_t low = Xil_In32(XPAR_AXI_TIMER_0_BASEADDR + TCR0);
	uint32_t high = Xil_In32(XPAR_AXI_TIMER_0_BASEADDR + TCR1);

	*t = ((uint64_t)high << 32) | low;
	*t >>= 1; // compensate for 2* as needed in ZYNQ
}
