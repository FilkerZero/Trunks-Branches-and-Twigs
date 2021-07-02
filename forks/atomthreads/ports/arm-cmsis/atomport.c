/*
 * Copyright (c) 2015, Tido Klaassen. All rights reserved.
 * Portions Copyright (c) 2017, Daniel Glasser. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. No personal names or organizations' names associated with the
 *    Atomthreads project may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE ATOMTHREADS PROJECT AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE PROJECT OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <string.h>

#include "atomport.h"
#include "atomport-private.h"
#include "asm_offsets.h"


#if defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS)
/* STM32 driver specific stuff here */
#endif /* defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS) */

#if defined(ATOMPORT_CONFIG_SF2_WITH_HAL_DRIVERS)
/* Microsemi SmartFusion2 specific stuff here */
#endif /* defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS) */

/* The task switch TCB pointers are defined with the alias "CTX_SW_NFO"
 * that is used within the port asm file "atomport-asm.S".
 */
struct task_switch_info ctx_switch_info asm("CTX_SW_NFO") =
{
   .running_tcb = NULL,
   .next_tcb    = NULL,
};

/* Forward function declaration */
static void thread_shell(void);
void SysTick_Handler(void); /* prototype to make code analyzer happy */

#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)
void portStartCycleCounter(void);
uint32_t portStopCycleCounter(void);
uint32_t portGetCycleCounter(void);
#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */

/* Declarations for functions in "atomport-asm.S" */
#if defined(ATOMPORT_CONFIG_SIMPLIFY_FIRST_THREAD)
extern void _archTransferToFirstThread(ATOM_TCB *, uint32_t, uint32_t);
#else
extern void _archFirstThreadRestore(ATOM_TCB *);
#endif /* defined(ATOMPORT_CONFIG_SIMPLIFY_FIRST_THREAD) */

/**
 * \b archFirstThreadRestore
 *
 * Transfer control to the thread with the provided thread control block
 * through stack and register manipulation.
 *
 * @param[in] new_tcb_ptr  The address of the TCB for the thread to be
 *                         run first
 *
 * Does not return
 */
void archFirstThreadRestore(ATOM_TCB *new_tcb_ptr)
{
#if defined(ATOMPORT_CONFIG_SIMPLIFY_FIRST_THREAD)
   /* Assumes 'new_tcb_ptr' is not NULL */
   uint32_t* sp;
   struct isr_stack* isr;
   struct task_stack* task;
#endif /* defined(ATOMPORT_CONFIG_SIMPLIFY_FIRST_THREAD) */

#if defined(__NEWLIB__)
   ctx_switch_info.reent = &(new_tcb_ptr->port_priv.reent);
   __DMB();
#endif /* defined(__NEWLIB__) */

#if defined(ATOMPORT_CONFIG_SIMPLIFY_FIRST_THREAD)
   /* The contents of the thread's stack are not particularly important
    * other than the return address and xPSR value that was populated in
    * the exception frame by the create thread procedure.  What needs to
    * be done is to rebuild the stack so that assembly code can simply
    * switch to the process stack, set the xPSR, then load the PC.
    * (This only applies to the first thread)
    *
    * Initial stack looks like this:
    * xPSR      sp + 64                 Contains 0x01000000
    * PC        sp + 60                 Contains thread_shell
    * lr        sp + 56                 Contains 0xEEEEEEEE
    * r12       sp + 52                 Contains 0xCCCCCCCC
    * r3        sp + 48                 Contains 0x33333333
    * r2        sp + 44                 Contains 0x22222222
    * r1        sp + 40                 Contains 0x11111111
    * r0        sp + 36 <-- isr_stack   Contains 0x00000000
    * exc_ret   sp + 32                 Contains 0xFFFFFFFD
    * r11       sp + 28                 Contains 0xBBBBBBBB
    * r10       sp + 24                 Contains 0xAAAAAAAA
    * r9        sp + 20                 Contains 0x99999999
    * r8        sp + 16                 Contains 0x88888888
    * r7        sp + 12                 Contains 0x77777777
    * r6        sp + 8                  Contains 0x66666666
    * r5        sp + 4                  Contains 0x55555555
    * r4        sp + 0 <-- task_stack   Contains 0x44444444 <-- PSP
    * .         sp - 4                  ....
    * .         sp - 8                  ....
    * .         sp - 12                 ....
    * .         sp - 16                 ....
    *
    * The thread stack currently contains an exception stack frame at
    * the top, followed by a thread save frame, with the process stack
    * pointer (psp) pointing to the stored 'r4' value, as shown above.
    */

   sp = new_tcb_ptr->sp_save_ptr;   /* current bottom of stack */
   /* sp should currently point to the beginning of the task context */
   task = (struct task_stack*)sp;

   /* isr follows task in the stack memory */
   isr = (struct isr_stack*)&task[1];

   /* Rather than loading all the registers with useless values from
    * the synthetic thread stack frame, as is done by the usual
    * '_archFirstThreadRestore()' routine, '_archTransferToFirstThread()'
    * is lazy and leaves whatever garbage is already in most of the
    * registers.  The saved stack pointer gets adjusted here, then the
    * assembly function short circuits the process by using the xPSR
    * and PC values passed to it; the "return" address is pushed on
    * the stack, the xPSR and control registers are configured, then
    * the return address (thread_shell | 1, in this case) is popped
    * from the stack into the PC, and the first thread is running.
    */

   /* Set the task stack pointer to one beyond the isr frame */
   new_tcb_ptr->sp_save_ptr = (void*)&isr[1];

#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)
   portStartCycleCounter();
#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */

      /* fix the registers up and get moving */
   _archTransferToFirstThread(new_tcb_ptr, isr->pc, isr->psr);
#else
   _archFirstThreadRestore(new_tcb_ptr);
#endif /* defined(ATOMPORT_CONFIG_SIMPLIFY_FIRST_THREAD) */
} /* end of archFirstThreadRestore() */

/**
 * \b archContextSwitch
 * Architecture specific context switch routine
 *
 * We do not perform the context switch directly. Instead we mark the new tcb
 * as should-be-running in ctx_switch_info and trigger a PendSv-interrupt.
 * The pend_sv_handler will be called when all other pending exceptions have
 * returned and perform the actual context switch.
 * This way we do not have to worry if we are being called from task or
 * interrupt context, which would mean messing with either main or thread
 * stack format.
 *
 * One difference to the other architectures is that execution flow will
 * actually continue in the old thread context until interrupts are enabled
 * again. From a thread context this should make no difference, as the context
 * switch will be performed as soon as the execution flow would return to the
 * calling thread. Unless, of course, the thread called atomSched() with
 * disabled interrupts, which it should not do anyways...
 */
void __attribute__((noinline))
archContextSwitch(ATOM_TCB *old_tcb_ptr __maybe_unused, ATOM_TCB *new_tcb_ptr)
{
   if (likely(ctx_switch_info.running_tcb != NULL))
   {
#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)
      ctx_switch_info.running_tcb->port_priv.cycles += portStopCycleCounter();
#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */

      ctx_switch_info.next_tcb = new_tcb_ptr;
#if defined(__NEWLIB__)
      ctx_switch_info.reent = &(new_tcb_ptr->port_priv.reent);
#endif /* defined(__NEWLIB__) */

#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)
      portStartCycleCounter();
#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */
      __DMB();        /* data memory barrier */

      SCB->ICSR = SCB_ICSR_PENDSVSET_Msk;
   }
} /* end of archContextSwitch() */

#if defined(ATOMPORT_CONFIG_SYSTICK_HANDLER)
/**
 * \b SysTick_Handler
 * System tick IRQ handler for ARM Cortex-M MCUs
 *
 */
void SysTick_Handler(void)
{
   /* Call the interrupt entry routine */
   atomIntEnter();      /* required on any handler that may schedule */

   /* Call the OS system tick handler */
   atomTimerTick();

#if defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS)
   /* Call the HAL systick handler for STM32 HAL device drivers */
   HAL_SYSTICK_IRQHandler();
#endif /* defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS) */

#if defined(ATOMPORT_CONFIG_SF2_WITH_HAL_DRIVERS)
   /* tell the MSS I2C driver that 10ms has passed */
   // MSS_I2C_system_tick(&g_mss_i2c1, 10);
#endif /* defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS) */

   /* Call the interrupt exit routine */
   atomIntExit(TRUE); /* required when 'atomIntEnter()' is called */
} /* end of SysTick_Handler() */
#endif /* defined(ATOMPORT_CONFIG_SYSTICK_HANDLER) */

#if defined(ATOMPORT_CONFIG_HARDFAULT_HANDLER)
/* Declare "HardFault_Handler()" with the attribute "naked" to prevent the
 * compiler from adding any sort of preamble that changes the contents of
 * registers before they can be saved off.  With the "naked" attribute,
 * the "__asm()" in the function body is compiled as the code within its
 * argument would be by the assembler (as a pure assembly function).
 */
void HardFault_Handler(void) __attribute__((naked));

void prvGetRegistersFromStack(uint32_t *pulFaultStackAddress);

void prvGetRegistersFromStack(uint32_t *pulFaultStackAddress)
{
   /* These variables are volatile to try and prevent the compiler/linker
    * optimising them away as the variable values don't get referenced
    * after they are set.
    *
    * If you don't see the register values you expect in the variables in
    * the debugger, you can make them global by moving their declaration
    * outside of this function.
    */
   struct regSave_s
   {
      volatile uint32_t r0; /* saved by exception */
      volatile uint32_t r1; /* saved by exception */
      volatile uint32_t r2; /* saved by exception */
      volatile uint32_t r3; /* saved by exception */
      volatile uint32_t r12; /* saved by exception */
      volatile uint32_t lr; /* Link register. */
      volatile uint32_t pc; /* Program counter. */
      volatile uint32_t psr;/* Program status register. */
      volatile uint32_t count; /* dummy counter */
   } exceptionRegs;

   exceptionRegs.r0  = pulFaultStackAddress[0];
   exceptionRegs.r1  = pulFaultStackAddress[1];
   exceptionRegs.r2  = pulFaultStackAddress[2];
   exceptionRegs.r3  = pulFaultStackAddress[3];

   exceptionRegs.r12 = pulFaultStackAddress[4];
   exceptionRegs.lr  = pulFaultStackAddress[5];
   exceptionRegs.pc  = pulFaultStackAddress[6];
   exceptionRegs.psr = pulFaultStackAddress[7];

   /* set this up for the debugger */
   exceptionRegs.count = 0;

   /* When the following block is hit, the local variables contain copies
    * of the register values at the time of the exception
    */
   for (;;)
   {
      __asm volatile ("BKPT\n\t");  // Halt (well, really a breakpoint)
      if (exceptionRegs.count)
      {
         break;
      }
   }
} /* prvGetRegistersFromStack */

/* Function:    HardFault_Handler
 *
 * Description: Handler for the Cortex-M3 "Hard Fault" exception, called on a
 *              bus error or a number of other errors when the more specific
 *              exceptions are disabled.  The name of this function must be
 *              "HardFault_Handler" or it will not override the default
 *              handler for the fault (an infinite loop) in the assembly
 *              start-up source file for your MCU/Toolchain combination.
 *
 *              This function has a function prototype that specifies the
 *              attribute "naked", which tells the compiler to preserve the
 *              contents of the registers on entry so they can be accessed
 *              in-place by the handler code.
 *
 *              The "__asm()" statement in the body of this function sets up
 *              a few things, saves the contents of some registers on the
 *              stack and then branches to the C language function
 *              "prvGetRegistersFromStack()".
 */
void HardFault_Handler(void)
{
   __asm volatile("tst lr, #4                                             \n"
                  "ite eq                                                 \n"
                  "mrseq r0, msp                                          \n"
                  "mrsne r0, psp                                          \n"
                  "ldr r1, [r0, #24]                                      \n"
                  "ldr r2, handler2_address_const                         \n"
                  "bx r2                                                  \n"
                  "handler2_address_const: .word prvGetRegistersFromStack \n");
} /* end of HardFault_Handler() */
#endif /* defined(ATOMPORT_CONFIG_HARDFAULT_HANDLER) */


/**
 * \b thread_shell
 *
 * Wrapper for thread main functions.
 *
 * This function is called when a new thread is scheduled in for the first
 * time. It extracts the thread entry point and parameter from the current
 * thread TCB and calls the threads entry point.
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
      task_ptr->entry_point(task_ptr->entry_param);
#if defined(DEBUG_THREAD_EXIT_BREAK)
      __asm volatile ("BKPT\n\t");  /* Halt (well, really a breakpoint) */
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
}

/**
 * Initialise a threads stack so it can be scheduled in by
 * archFirstThreadRestore or the pend_sv_handler.
 */
void archThreadContextInit(ATOM_TCB *tcb_ptr,
                           void *stack_top,
                           void (*entry_point)(uint32_t),
                           uint32_t entry_param)
{
   struct isr_stack *isr_ctx;
   struct task_stack *tsk_ctx;

   /**
    * Do compile time verification for offsets used in _archFirstThreadRestore
    * and pend_sv_handler. If compilation aborts here, you will have to adjust
    * the offsets for struct task_switch_info's members in asm-offsets.h
    */
   assert_static(offsetof(struct task_switch_info, running_tcb) == CTX_RUN_OFF);
   assert_static(offsetof(struct task_switch_info, next_tcb) == CTX_NEXT_OFF);
#if defined(__NEWLIB__)
   assert_static(offsetof(struct task_switch_info, reent) == CTX_REENT_OFF);
#endif /* defined(__NEWLIB__) */

   /**
    * Enforce initial stack alignment
    */
   stack_top = STACK_ALIGN(stack_top, STACK_ALIGN_SIZE);

   /**
    * New threads will be scheduled from an exception handler, so we have to
    * set up an exception stack frame as well as task stack frame
    */
   isr_ctx = stack_top - sizeof *isr_ctx;
   tsk_ctx = (stack_top - sizeof *isr_ctx) - sizeof *tsk_ctx;

#if defined(DEBUG_THREAD_CREATION)
   printf("[%s] tcb_ptr: %p stack_top: %p isr_ctx: %p tsk_ctx: %p "
          "entry_point: %p, entry_param: 0x%x\n",
          __func__, tcb_ptr, stack_top, isr_ctx, tsk_ctx, 
          entry_point, entry_param);
   printf("[%s] isr_ctx->r0: %p isr_ctx->psr: %p tsk_ctx->r4: %p "
          "tsk_ctx->lr: %p\n",
          __func__, &isr_ctx->r0, &isr_ctx->psr, &tsk_ctx->r4,
          &tsk_ctx->lr);
#endif /* defined(DEBUG_THREAD_CREATION) */

   /**
    * We use the exception return mechanism to jump to our thread_shell()
    * function and initialise the PSR to the default value (thumb state
    * flag set and nothing else)
    */
   isr_ctx->psr = 0x01000000;
   isr_ctx->pc  = (uint32_t) thread_shell;

#if !defined(ATOMPORT_CONFIG_MINIMIZE_CODE_SIZE)
   /* initialise 'saved' registers to values that help with debugging
    * task start-up
    */
   isr_ctx->lr  = 0xEEEEEEEE;
   isr_ctx->r12 = 0xCCCCCCCC;
   isr_ctx->r3  = 0x33333333;
   isr_ctx->r2  = 0x22222222;
   isr_ctx->r1  = 0x11111111;
   isr_ctx->r0  = 0x00000000;
#endif /* !defined(ATOMPORT_CONFIG_MINIMIZE_CODE_SIZE) */

   /**
    * We use this special EXC_RETURN code to switch from main stack to our
    * thread stack on exception return
    */
   tsk_ctx->exc_ret = 0xFFFFFFFD;

#if !defined(ATOMPORT_CONFIG_MINIMIZE_CODE_SIZE)
   /* initialise 'saved' registers to values that help with debugging
    * task start-up
    */
   tsk_ctx->r11 = 0xBBBBBBBB;
   tsk_ctx->r10 = 0xAAAAAAAA;
   tsk_ctx->r9  = 0x99999999;
   tsk_ctx->r8  = 0x88888888;
   tsk_ctx->r7  = 0x77777777;
   tsk_ctx->r6  = 0x66666666;
   tsk_ctx->r5  = 0x55555555;
   tsk_ctx->r4  = 0x44444444;
#endif /* !defined(ATOMPORT_CONFIG_MINIMIZE_CODE_SIZE) */

   /**
    * Stack frames have been initialized, save it to the TCB. Also set
    * the thread's real entry point and param, so the thread shell knows
    * what function to call.
    */
   tcb_ptr->sp_save_ptr = tsk_ctx;
   tcb_ptr->entry_point = entry_point;
   tcb_ptr->entry_param = entry_param;

#if defined(__NEWLIB__)
   /**
    * Initialize thread's reentry context for newlib
    */
   _REENT_INIT_PTR(&(tcb_ptr->port_priv.reent));
   /* initialize the file descriptors for the standard streams */
   tcb_ptr->port_priv.reent.__sf[0]._file = 0; /* stdin */
   tcb_ptr->port_priv.reent.__sf[1]._file = 1; /* stdout */
   tcb_ptr->port_priv.reent.__sf[2]._file = 2; /* stderr */
#endif /* defined(__NEWLIB__) */
} /* end of archThreadContextInit */

#if defined(DEBUG_CRITICAL)
void __break_for_debug(uint32_t arg)
{
   static uint32_t previous_arg = 0xFA5A5A5Aul;

   if (previous_arg != arg)
   {
      previous_arg = arg;
   }
} /* end of __break_for_debug() */
#endif /* defined(DEBUG_CRITICAL) */

#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)

void portStartCycleCounter(void)
{
   CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk; /* enable trace */
   DWT->LAR = 0xC5ACCE55;   /* unlock writes to the DWT regs */
   __DMB();
   if ((DWT->CTRL & DWT_CTRL_CYCCNTENA_Msk) != 0)
   {
      DWT->CTRL &= ~DWT_CTRL_CYCCNTENA_Msk;
      __DMB();
   }
   DWT->CYCCNT = 0;
   DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
} /* end of portStartCycleCounter() */

uint32_t portStopCycleCounter(void)
{
   if ((DWT->CTRL & DWT_CTRL_CYCCNTENA_Msk) != 0)
   {
      DWT->CTRL &= ~DWT_CTRL_CYCCNTENA_Msk;
   }
   return (DWT->CYCCNT >> 8);
} /* end of portStopCycleCounter() */

uint32_t portGetCycleCounter(void)
{
   return (DWT->CYCCNT >> 8);
} /* end of portGetCycleCounter() */

#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */
