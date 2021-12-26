#if !defined(PORT_MICROBLAZE_TICK_H__INCL__)
#define PORT_MICROBLAZE_TICK_H__INCL__

#if defined(PORT_USE_MICROBLAZE_TICKER)

#include "xintc.h"
#include "xtmrctr.h"

extern XIntc portIntController;
extern XTmrCtr portTickTimer;

/* Function:    portTickStart
 *
 * Description: Start the tick timer running
 *
 * Parameters:
 *   None
 *
 * Returns:
 *   Nothing
 */
void portTickStart(void);

/**
 * Function:    portSetupDrivers
 *
 * Description: Micorblaze microcontroller specific hardware driver
 *              initialization
 *
 * Parameters:
 *   None
 *
 * Returns:
 *   XST_SUCCESS on success
 *   XST_FAILURE (or some other Xilinx driver error code) on failure
 *
 * Notes:
 *   This assumes the following are true about the hardware (FPGA) design, as
 *   reflected in "xparameters.h":
 *   * There is an AXI Interrupt Controller connected to the MicroBlaze
 *     selected by PORT_INTC_ID (defined in "atomport.h")
 *   * There is at least one AXI Timer connected to the MicroBlaze with
 *     its interrupt routed to the AXI Interrupt Controller connected to
 *     the MicroBlaze, selected by PORT_TICK_TIMER_ID (defined in
 *     "atomport.h")
 *   * The AtomThreads executive has exclusive use of the counter within
 *     the timer selected by PORT_TICK_COUNTER (defined in "atomport.h")
 */
int portSetupDrivers(void);

#endif /* defined(PORT_USE_MICROBLAZE_TICKER) */

#endif /* !defined(PORT_MICROBLAZE_TICK_H__INCL__) */
