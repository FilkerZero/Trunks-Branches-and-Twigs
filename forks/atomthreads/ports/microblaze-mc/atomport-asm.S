#include "xparameters.h"

#if !defined(__ASSEMBLY__)
#define __ASSEMBLY__
#endif /* !defined(__ASSEMBLY__) */

#include "atomport-asm-macros.h"

/* MicroBlaze v9 32 bit register set and conventions:
 *  R0 - constant 0, read-only
 *  R1 - stack pointer, stack grows down
 *  R2 - Anchor for Read-Only Small Data area
 *  R3 - Volatile, used for temporaries and return values
 *  R4 - Volatile, used for temporaries and return values
 *  R5 - Volatile, used for temporaries and passing parameters
 *  R6 - Volatile, used for temporaries and passing parameters
 *  R7 - Volatile, used for temporaries and passing parameters
 *  R8 - Volatile, used for temporaries and passing parameters
 *  R9 - Volatile, used for temporaries and passing parameters
 *  R10 - Volatile, used for temporaries and passing parameters
 *  R11 - Volatile, used for temporaries
 *  R12 - Volatile, used for temporaries
 *  R13 - anchor for Read/Write Small Data area
 *  R14 - Interrupt return address
 *  R15 - Subroutine return address
 *  R16 - Trap return address
 *  R17 - Exception return address
 *  R18 - "Reserved for Compiler and Assembler Temporaries"
 *  R19 - Non-volatile, callee must restore before returning
 *  R20 - GOT pointer for PIC, non-volatile for non-PIC
 *  R21 - Non-volatile
 *  R22 - Non-volatile
 *  R23 - Non-volatile
 *  R24 - Non-volatile
 *  R25 - Non-volatile
 *  R26 - Non-volatile
 *  R27 - Non-volatile
 *  R28 - Non-volatile
 *  R29 - Non-volatile
 *  R30 - Non-volatile
 *  R31 - Non-volatile
 */


/**
 * \b archContextSwitch
 *
 * Perform a 'voluntary' context switch from one thread to
 * another. This is called by the Atom kernel, and should never
 * be called from user application code.
 *
 * This is for task switches due to preemption, blocking operations
 * (timer, semaphore), and when the user task calls the kernel "yield()"
 * function. Because of this, it is assumed that any volatile registers
 * have already been saved off, and only the non-volatile registers need
 * be saved or restored from the saved context.
 *
 * This interface is declared in "atom.h" as:
 *   void archContextSwitch (ATOM_TCB *old_tcb_ptr, ATOM_TCB *new_tcb_ptr);
 *
 * On entry on a Microblaze:
 *   'old_tcb_ptr' is in register r5
 *   'new_tcb_ptr' is in register r6
 *
 * This is always called from within a critical section, so interrupts will
 * not be enabled on entry. The MSR state is saved for the old thread and
 * restored on return, and when interrupts are disabled, this means they will
 * remain disabled on return. Note that 'on return' is a return to the last
 * call location to this function in the new thread context.
 */
.section .text
   .globl archContextSwitch
   .align 4
        
archContextSwitch:
// lwi r3, r5, 0       //get current old thread stack addr
   addik r1, r1, -(CONTEXT_STORE_BYTES); // create stack frame (sort of)
   swi   r1, r5, 0     //save stack ptr in old TCB
   STORE_REG(r2,  r1)  //Small RO Data anchor
   STORE_REG(r13, r1)  //Small RW Data anchor
   STORE_REG(r14, r1)  //Interrupt return address
   // Will be adjusting sub return addr
   STORE_REG(r16, r1)  //Break/Trap return address
   STORE_REG(r17, r1)  //Exception return address
   STORE_REG(r18, r1)  //Kernel/assembler use...
   STORE_REG(r19, r1)  //Non-volatile
   STORE_REG(r20, r1)  //GOT pointer or non-volatile
   STORE_REG(r21, r1)  //Non-volatile
   STORE_REG(r22, r1)  //Non-volatile
   STORE_REG(r23, r1)  //Non-volatile
   STORE_REG(r24, r1)  //Non-volatile
   STORE_REG(r25, r1)  //Non-volatile
   STORE_REG(r26, r1)  //Non-volatile
   STORE_REG(r27, r1)  //Non-volatile
   STORE_REG(r28, r1)  //Non-volatile
   STORE_REG(r29, r1)  //Non-volatile
   STORE_REG(r30, r1)  //Non-volatile
   STORE_REG(r31, r1)  //Non-volatile
   STORE_REG(r15, r1)  //Function return address(?) - it's done on MIPS...
   mfs r4, rmsr        //grab the machine state register
   swi r4, r1, (msr_idx * 4); // store it in stack frame
   addik r15, r15, 8   //Advance return address past call and delay slot
   STORE_REG(r15, r1)  //Subroutine return address


   lwi r1, r6, 0         //get stack addr from new TCB
   RESTORE_REG(r2,  r1)  //Small RO Data anchor
   RESTORE_REG(r13, r1)  //Small RW Data anchor
   RESTORE_REG(r14, r1)  //Interrupt return addr
   RESTORE_REG(r15, r1)  //Subroutine return addr
   RESTORE_REG(r16, r1)  //Break/Trap return addr
   RESTORE_REG(r17, r1)  //Exception return addr
   RESTORE_REG(r19, r1)  //Non-volatile
   RESTORE_REG(r20, r1)  //GOT pointer or non-volatile
   RESTORE_REG(r21, r1)  //Non-volatile
   RESTORE_REG(r22, r1)  //Non-volatile
   RESTORE_REG(r23, r1)  //Non-volatile
   RESTORE_REG(r24, r1)  //Non-volatile
   RESTORE_REG(r25, r1)  //Non-volatile
   RESTORE_REG(r26, r1)  //Non-volatile
   RESTORE_REG(r27, r1)  //Non-volatile
   RESTORE_REG(r28, r1)  //Non-volatile
   RESTORE_REG(r29, r1)  //Non-volatile
   RESTORE_REG(r30, r1)  //Non-volatile
   RESTORE_REG(r31, r1)  //Non-volatile

   lwi r18, r1, (msr_idx * 4);  //Get the stored MSR
   mts rmsr, r18
   RESTORE_REG(r18, r1)  //Kernel/assembler use...

   /* we are now done with the saved regs on the stack */
   addik r1, r1, (CONTEXT_STORE_BYTES); //Get rid of reg save

   /* return with interrupts enabled */
#if (XPAR_MICROBLAZE_USE_MSR_INSTR == 1)
   rtsd r15, 0          //Normal return...
   msrset r0, 0x2       //Enable interrupts in the delay slot
#else
   rtid r15, 0          //Use interrupt return to enable interrupts
   or r0, r0, r0        //don't do anything in the delay slot
#endif /* (XPAR_MICROBLAZE_USE_MSR_INSTR == 1) */


/**
 * archFirstThreadRestore(ATOM_TCB *new_tcb)
 *
 * This function is responsible for restoring and starting the first
 * thread the OS runs. It expects to find the thread context exactly
 * as it would be if a context save had previously taken place on it.
 * The only real difference between this and the archContextSwitch()
 * routine is that there is no previous thread for which context must
 * be saved.
 *
 * The final action this function must do is to restore interrupts.
 *
 * Note that this is only called from 'atomkernel.c:osStart()' from
 * outside a critical section.
 */
.globl archFirstThreadRestore
archFirstThreadRestore:
   lwi r1, r5, 0         //get current new thread stack addr from TCB
   //RESTORE_INT_CONTEXT;  //pull saved context from stack and delete it
   RESTORE_REG(r2,  r1)  //Small RO Data anchor
   RESTORE_REG(r13, r1)  //Small RW Data anchor
   RESTORE_REG(r14, r1)  //Interrupt return addr
   RESTORE_REG(r15, r1)  //Subroutine return addr
   RESTORE_REG(r16, r1)  //Break/Trap return addr
   RESTORE_REG(r17, r1)  //Exception return addr
   RESTORE_REG(r19, r1)  //Non-volatile
   RESTORE_REG(r20, r1)  //GOT pointer or non-volatile
   RESTORE_REG(r21, r1)  //Non-volatile
   RESTORE_REG(r22, r1)  //Non-volatile
   RESTORE_REG(r23, r1)  //Non-volatile
   RESTORE_REG(r24, r1)  //Non-volatile
   RESTORE_REG(r25, r1)  //Non-volatile
   RESTORE_REG(r26, r1)  //Non-volatile
   RESTORE_REG(r27, r1)  //Non-volatile
   RESTORE_REG(r28, r1)  //Non-volatile
   RESTORE_REG(r29, r1)  //Non-volatile
   RESTORE_REG(r30, r1)  //Non-volatile
   RESTORE_REG(r31, r1)  //Non-volatile
   addik r1, r1, (CONTEXT_STORE_BYTES); //Get rid of reg save

#if (XPAR_MICROBLAZE_USE_MSR_INSTR == 1)
   rtsd r15, 0          //Normal return to address (no skip)
   msrset r0, 0x2       //Enable interrupts in the delay slot
#else
   rtid r15, 0          //Use interrupt return to enable interrupts
   or r0, r0, r0        //don't do anything in the delay slot
#endif /* (XPAR_MICROBLAZE_USE_MSR_INSTR == 1) */
