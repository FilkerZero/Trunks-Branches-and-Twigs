#if !defined(__ATOM_PORT_H)
#define __ATOM_PORT_H

#include <stdint.h>
#include <stddef.h>

#include "xparameters.h"
#include "mb_interface.h"
#include "xparameters.h"
#include "xtmrctr.h"            /* AXI Timer driver */


/* Uncomment to enable stack-checking */
/* #define ATOM_STACK_CHECKING */

/* Uncomment to enable stack-checking */
/* #define ATOM_STACK_CHECKING */
/* Uncomment to enable critical section debugging */
//#define DEBUG_CRITICAL

/* Define PORT_USE_MICROBLAZE_TICKER to enable the
 * code that sets up the AXI Interrupt Controller and
 * AXI Timer connected to the MicroBlaze
 */
#define PORT_USE_MICROBLAZE_TICKER

/* Required number of system ticks per second (normally 100 for 10ms tick
 * or 1000 for 1ms tick)
 */
#define SYSTEM_TICKS_PER_SEC            1000   /* 1k Hz */
//#define SYSTEM_TICKS_PER_SEC        100u /* 100Hz */

/*
 * The following constants map to the XPAR parameters created in the
 * xparameters.h file. They are only defined here such that a user can easily
 * change all the needed parameters in one place.
 */
#define PORT_INTC_ID          XPAR_INTC_0_DEVICE_ID

#define PORT_TICK_TIMER_ID    XPAR_TMRCTR_0_DEVICE_ID
#define PORT_TICK_TIMER_INT   XPAR_INTC_0_TMRCTR_0_VEC_ID
#define PORT_TICK_COUNTER     0

#define MB_RESERVED_STACK_WORDS 4       /* keep MB happy */

/* Size of each stack entry / stack alignment size (32 bits on MIPS) */
#define STACK_ALIGN_SIZE                sizeof(uint32_t)

#define ALIGN(x, a)         ((x + (typeof(x))(a) - 1) & ~((typeof(x))(a) - 1))
#define PTR_ALIGN(p, a)     ((typeof(p))ALIGN((uint32_t)(p), (a)))
#define STACK_ALIGN(p, a)   (typeof(p))((typeof(a))(p) & ~((a) - 1))

#define POINTER             void *
#define UINT32              uint32_t

#define likely(x)           __builtin_expect(!!(x), 1)
#define unlikely(x)         __builtin_expect(!!(x), 0)
#define __maybe_unused      __attribute__((unused))

#if defined(TRUE)
#if !(TRUE)
#warning TRUE is not compatible with definition in "atom.h"
#endif /* !(TRUE) */
#undef TRUE     /* will get defined again in "atom.h" */
#endif /* defined(TRUE) */

#if defined(FALSE)
#if (FALSE)
#warning FALSE is not compatible with definition in "atom.h"
#endif /* !(TRUE) */
#undef FALSE     /* will get defined again in "atom.h" */
#endif /* defined(FALSE) */

#define assert_static(e)                        \
   do                                           \
   {                                            \
      enum { assert_static__ = 1/(e) };         \
   } while (0)


/**
 * Critical region protection: this should disable interrupts
 * to protect OS data structures during modification. It must
 * allow nested calls, which means that interrupts should only
 * be re-enabled when the outer CRITICAL_END() is reached.
 */
extern uint32_t at_preempt_count;

/* CRITICAL_STORE allocates any local storage required in the context
 * where a critical section is entered; it might be empty.
 * If it is empty, it becomes a NUL statement where it appears.
 */
#define CRITICAL_STORE  /* nothing for microblaze */

/* CRITICAL_START() is a function-style macro that is used to enter
 * a critical section.  This must disable interrupts and support
 * nested critical sections.  For this port, the nesting uses the
 * global variable, 'at_preempt_count'.
 * The macro invocation must be followed by a ';' where it is used.
 */
#define CRITICAL_START()             \
    microblaze_disable_interrupts(); \
    at_preempt_count++

/* CRITICAL_END() is a function-style macro that is used to exit
 * a critical section.  This must support nested critical sections
 * and only enable interrupts when the outer-most critical section
 * is exited. For this port, the nesting uses the global variable
 * 'at_preempt_count' to track nesting depth.
 * The macro invocation must be followed by a ';' where it is used.
 */
#define CRITICAL_END()                      \
    do {                                    \
        at_preempt_count--;                 \
        if (at_preempt_count <= 0) {        \
            at_preempt_count = 0;            \
            microblaze_enable_interrupts(); \
        }                                   \
    } while (0)


struct mb_port_priv
{
   uint32_t oneTimeFlag; /* used when doing thread switching */
#if defined(__NEWLIB__) && defined(__NEWLIB_REENT__)
   /**
    * When using newlib with reent, define port private field in atom_tcb
    * to be a struct _reent.
    */
   struct _reent reent; /* reentrant context for newlib */
#endif /* defined(__NEWLIB__) && defined(__NEWLIB_REENT__) */

#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)
   uint64_t ticks;     /* accumulated ticks */
#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */
};

#define THREAD_PORT_PRIV    struct mb_port_priv port_priv

#endif /* !defined(__ATOM_PORT_H) */

