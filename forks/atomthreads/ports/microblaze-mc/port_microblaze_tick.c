#include "xparameters.h"
#include "xintc.h"              /* Interrupt controller */
#include "xtmrctr.h"            /* AXI Timer driver */
#include "xil_exception.h"      /* Exception stuff */

#include "atom.h"
#include "atomport.h"

#if defined(PORT_USE_MICROBLAZE_TICKER)
#include "port_microblaze_tick.h"

#define PORT_TICK_TIMER_FREQ  XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ
#define PORT_TICK_PERIOD_NS  \
    XTC_HZ_TO_NS(SYSTEM_TICKS_PER_SEC)
#define PORT_TICK_CLOCKS_PER_NS \
    (1000000000U / XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ)
#define PORT_TICK_CLOCKS \
    (PORT_TICK_PERIOD_NS / PORT_TICK_CLOCKS_PER_NS)

//  SysClkPeriod = XTC_HZ_TO_NS(InstancePtr->Config.SysClockFreqHz);

/* Driver context blobs for the AXI Interrupt Controller and AXI Timer
 * connected to the MicroBlaze
 */
XIntc portIntController;
XTmrCtr portTickTimer;

static int portDriversSetup = 0;    /* flag for port HW driver setup */
static int portTickStarted = 0;
static uint32_t portTickTimerReload = 0xFFFFFFFF - PORT_TICK_CLOCKS;

/**
 * \b portTickHandler
 *
 * Tick interrupt handler
 *
 */
static void portTickHandler(void *timerRef, uint8_t counter)
{
    if (portTickStarted)
    {
        // XTmrCtr *timer = &portTickTimer;
        atomIntEnter();     /* notify kernel of interrupt context */
        atomTimerTick();    /* pass the event on to the kernel */
        XTmrCtr_Reset(&portTickTimer, PORT_TICK_COUNTER);
        atomIntExit(TRUE);  /* On our way out */
    }
} /* end of portTickHandler() */

/**
 * \b portTickStart
 *
 * Start the tick timer running
 */
void portTickStart(void)
{
    if (!portTickStarted)
    {
        XTmrCtr* timer = &portTickTimer;

        XTmrCtr_SetHandler(timer, portTickHandler, timer);
        //XTmrCtr_SetResetValue(timer, PORT_TICK_COUNTER, PORT_TICK_CLOCKS - 1UL);
        XTmrCtr_SetResetValue(timer, PORT_TICK_COUNTER, portTickTimerReload);
        XTmrCtr_SetOptions(timer, PORT_TICK_COUNTER,
                           XTC_INT_MODE_OPTION | XTC_AUTO_RELOAD_OPTION);

        /*
         * Start the timer counter such that it's incrementing by default,
         * then wait for it to timeout a number of times
         */
        XTmrCtr_Start(timer, PORT_TICK_COUNTER);
        portTickStarted = 1;
    }
} /* end of portTickStart() */

/**
 * \b portSetupDrivers
 *
 * Micorblaze microcontroller specific hardware and runtime initialization
 *
 * This assumes the following are true about the hardware (FPGA) design, as
 * reflected in "xparameters.h":
 *   * There is an AXI Interrupt Controller connected to the MicroBlaze
 *     selected by PORT_INTC_ID (defined in "atomport.h")
 *   * There is at least one AXI Timer connected to the MicroBlaze with
 *     its interrupt routed to the AXI Interrupt Controller connected to
 *     the MicroBlaze, selected by PORT_TICK_TIMER_ID (defined in
 *     "atomport.h")
 *   * The AtomThreads executive has exclusive use of the counter within
 *     the timer selected by PORT_TICK_COUNTER (defined in "atomport.h")
 */
int portSetupDrivers(void)
{
    XIntc* intCtl = &portIntController;
    int status = XST_SUCCESS;

    if (portDriversSetup != 0)
    {
        return status;
    }

    portDriversSetup = 1;

    /*
     * Initialize the exception table.
     */
    Xil_ExceptionInit();

    /*
     * Register the interrupt controller handler with the exception table.
     */
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XIntc_InterruptHandler,
                                 intCtl);

    /*
     * Enable non-critical exceptions.
     */
    Xil_ExceptionEnable();

    /* If the interrupt controller driver has not been set up,
     * set it up
     */
    if (intCtl->IsReady == 0)
    {
        /* Initialize the interrupt controller driver */
        status = XIntc_Initialize(intCtl, PORT_INTC_ID);

        if (status == XST_SUCCESS)
        {
            /* Start the interrupt controller */
            status = XIntc_Start(intCtl, XIN_REAL_MODE);
        }
    }

    /* Did that go okay? */
    if (status == XST_SUCCESS)
    { /* seems to have */
        XTmrCtr* timer = &portTickTimer;

        /* Need to set up the tick timer driver at some point */
        if (timer->IsReady == 0)
        { /* it's not been set up yet */
            /* initialize the AXI Timer driver */
            status = XTmrCtr_Initialize(timer, PORT_TICK_TIMER_ID);
        }

        if (status == XST_SUCCESS)
        {
            /* Register the timer driver's handler for the timer
             * interrupt with the interrupt controller driver
             */
            status = XIntc_Connect(intCtl, PORT_TICK_TIMER_INT,
                                   (XInterruptHandler)XTmrCtr_InterruptHandler,
                                   (void*)timer);

        }

        if (status == XST_SUCCESS)
        {
            /* Enable the timer interrupt, but don't start the timer yet */
            XIntc_Enable(intCtl, PORT_TICK_TIMER_INT);
        }
    }

    return status;
} /* end of portSetupDrivers() */

#endif /* defined(PORT_USE_MICROBLAZE_TICKER) */

