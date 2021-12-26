#include <string.h>
#include "xparameters.h"
#include "xintc.h"              /* Interrupt controller */
#include "xtmrctr.h"            /* AXI Timer driver */
#include "xil_exception.h"      /* Exception stuff */

#include "atom.h"

//#include "atomport-private.h"
#include "atomport.h"
#include "atomport-asm-macros.h"
#if defined(PORT_USE_MICROBLAZE_TICKER)
#include "port_microblaze_tick.h"
#endif /* defined(PORT_USE_MICROBLAZE_TICKER) */

#define SET_REG(base, reg, val) \
   *((uint32_t *)((base) + (reg ## _idx) * sizeof(uint32_t))) = (uint32_t)(val)

#define MB_MSR_IE 0x0002u       /* Interrupt enable bit */
#define MB_MSR_EE 0x0100u       /* Exception enable bit */

extern void *_SDA2_BASE_;       /* from the linker */
extern void *_SDA_BASE_;        /* from the linker */

#define PORT_TICK_TIMER_FREQ  XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ
#define PORT_TICK_CLOCKS      \
    XTC_HZ_TO_NS(XPAR_AXI_TIMER_0_CLOCK_FREQ_HZ / SYSTEM_TICKS_PER_SEC)
//  SysClkPeriod = XTC_HZ_TO_NS(InstancePtr->Config.SysClockFreqHz);

/* Used for managing nesting of atomport.h critical sections */
uint32_t at_preempt_count = 0;

/**
 * \b thread_shell
 *
 * Wrapper for thread main functions.
 *
 * This function is called when a new thread is scheduled in for the first
 * time. It extracts the thread entry point and parameter from the current
 * thread TCB and calls the threads entry point.
 *
 *
 */
static void thread_shell(void)
{
   ATOM_TCB *task_ptr;

   /**
    * We "return" to here after being scheduled in by the pend_sv_handler.
    * We get a pointer to our TCB from atomCurrentContext()
    */
   task_ptr = atomCurrentContext();

   /**
    * Our thread entry point and parameter are stored in the TCB.
    * Call it if it is valid
    */
   if (task_ptr && task_ptr->entry_point)
   {
#if defined(PORT_USE_MICROBLAZE_TICKER)
       /* Sneaky hardware driver setup */
       (void)portSetupDrivers();
       portTickStart();     /* Start the clock */
#endif /* defined(PORT_USE_MICROBLAZE_TICKER) */

      task_ptr->entry_point(task_ptr->entry_param);
#if defined(DEBUG_THREAD_EXIT_BREAK)
      // TODO: inline break instruction
      __asm volatile ("brki rD, C_BASE_VECTORS+0x8\t\n");
#endif /* defined(DEBUG_THREAD_EXIT_BREAK) */
   }

   /**
    * Thread returned or entry point was not valid.
    * Should never happen... Maybe we should switch MCU into debug mode here
    */
   for (;;)
   {
      /* doing nothing */
   }
} /* end of thread_shell() */

/**
 * This function initializes each thread's stack during creation, before the
 * thread is first run. New threads are scheduled in using the same
 * context-switch function used for threads which were previously scheduled
 * out, therefore this function should set up a stack context which looks
 * much like a thread which has been scheduled out and had its context saved.
 * We fill part of the stack with those registers which are involved in the
 * context switch, including appropriate stack or register contents to cause
 * the thread to branch to its entry point function when it is scheduled in.
 *
 * Interrupts should also be enabled whenever a thread is restored, hence
 * ports may wish to explicitly include the interrupt-enable register here
 * which will be restored when the thread is scheduled in. Other methods
 * can be used to enable interrupts, however, without explicitly storing
 * it in the thread's context.
 */
void archThreadContextInit(ATOM_TCB *tcb_ptr, 
                           void *stack_top,
                           void (*entry_point)(uint32_t),
                           uint32_t entry_param)
{

   /* Make space for context saving */
   uint32_t stack_start;
   uint32_t poison = 0x00000000;
   int i;

   stack_start = (uint32_t)stack_top;

   /* The MicroBlaze kind-of requires a bunch of stuff at the top of the
    * stack before the first stack frame; not sure why.
    */
   for (i = 0; i < MB_RESERVED_STACK_WORDS; ++i)
   {
      *(uint32_t*)stack_start = (uint32_t)thread_shell;
      stack_start -= sizeof(uint32_t);
   }

   /* Reserve the context frame below the 0s we put in at the start */
   stack_start -= (uint32_t)(sizeof(uint32_t) * NUM_CTX_REGS);

   tcb_ptr->entry_point = entry_point;  /* probably already there */
   tcb_ptr->entry_param = entry_param;

   /* populate some TCB fields */
   tcb_ptr->sp_save_ptr = (POINTER)stack_start;
   tcb_ptr->port_priv.oneTimeFlag = 0;
#if defined(__NEWLIB__) && defined(__NEWLIB_REENT__)
   /* TODO: Fill in reent pointer with appropraite TLS */
   tcb_ptr->port_priv.reent = NULL;
#endif /* defined(__NEWLIB__) && defined(__NEWLIB_REENT__) */

#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)
   tcb_ptr->port_priv.cycles = 0;
#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */

   /* Fill the initial context with register number patterns */
   for (i = 0; i < 32; i++)
   {
      ((uint32_t*)stack_start)[i] = poison;
      poison += 0x01010101;
   }

   /* Populate registers that are not default */
   SET_REG(stack_start, msr, mfmsr() | MB_MSR_IE); /* enable interrupts */
   SET_REG(stack_start, r1, stack_start);     /* r1 is sp */
   SET_REG(stack_start, r2, &_SDA2_BASE_);    /* Read-only Small Data Area */
   SET_REG(stack_start, r5, entry_param);     /* volatile, 1st param */
   /* skipping non-parameter volatiles for now */
   SET_REG(stack_start, r13, &_SDA_BASE_);    /* Read/Write Small Data */
   SET_REG(stack_start, r14, thread_shell);   /* interrupt return addr */
   SET_REG(stack_start, r15, thread_shell);   /* Subroutne return addr */
   SET_REG(stack_start, r16, thread_shell);   /* Trap return addr */
   SET_REG(stack_start, r17, thread_shell);   /* Exception return addr */
   SET_REG(stack_start, r20, NULL);           /* GOT for PIC */
} /* end of archThreadContextInit() */

