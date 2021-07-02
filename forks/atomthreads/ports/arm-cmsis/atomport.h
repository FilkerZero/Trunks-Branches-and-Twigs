/*
 * Copyright (c) 2015, Tido Klaassen. All rights reserved.
 * Portions (c) 2017, Daniel Glasser
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
#pragma once
#if !defined(__ATOM_PORT_H)
#define __ATOM_PORT_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>  /* ensure that things like "__NEWLIB__" are defined */
#include "atomport_config.h" /* port configuration defines */

/* Uncomment to enable stack-checking */
/* #define ATOM_STACK_CHECKING */
/* Uncomment to enable critical section debugging */
//#define DEBUG_CRITICAL

/* MCU specific includes, see "atomport_config.h" for settings */
#if defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS)
#if defined(STM32L476xx)
/* Tested with STM32L476G Nucleo-64 */
#include "stm32l4xx_hal.h"
#include "stm32l4xx.h"
#include "stm32l476xx.h"
#include "core_cm4.h"
#elif defined(STM32F765xx) || defined(STM32F767xx) || defined(STM32F769xx) || \
   defined(STM32F777xx) || defined(STM32F769xx)
/* Tested with STM32F767ZI Nucleo-144 */
#include "stm32f7xx_hal.h"
#include "stm32f7xx.h"
#include "core_cm7.h"
#else
#error Unsupported target
#endif /* defined(STM32L476xx) */
#endif /* defined(ATOMPORT_CONFIG_STM32_WITH_HAL_DRIVERS) */

#if defined(ATOMPORT_CONFIG_SF2_WITH_HAL_DRIVERS)
#include "m2sxxx.h"   /* SmartFusion2 */
#include "hal.h"
#include "core_cm3.h"
#endif /* defined(ATOMPORT_CONFIG_SF2_WITH_HAL_DRIVERS) */

/* Other CMSIS includes */
#include "core_cmInstr.h"
#include "core_cmFunc.h"


/* Required number of system ticks per second (normally 100 for 10ms tick) */
#define SYSTEM_TICKS_PER_SEC            1000

/* Size of each stack entry / stack alignment size 
 * (4 bytes on Cortex-M without FPU) 
 */
#define STACK_ALIGN_SIZE    sizeof(uint32_t)

#define ALIGN(x, a)         ((x + (typeof(x))(a) - 1) & ~((typeof(x))(a) - 1))
#define PTR_ALIGN(p, a)     ((typeof(p))ALIGN((uint32_t)(p), (a)))
#define STACK_ALIGN(p, a)   (typeof(p))((typeof(a))(p) & ~((a) - 1))

#define POINTER             void *
#define UINT32              uint32_t

#define likely(x)           __builtin_expect(!!(x), 1)
#define unlikely(x)         __builtin_expect(!!(x), 0)
#define __maybe_unused      __attribute__((unused))

#define assert_static(e)                        \
   do                                           \
   {                                            \
      enum { assert_static__ = 1/(e) };         \
   } while (0)

__attribute__((always_inline))
   static inline uint32_t cm_mask_interrupts(uint32_t mask)
{
   register uint32_t old;
   __asm__ __volatile__("MRS %0, PRIMASK"  : "=r" (old));
   __asm__ __volatile__(""  : : : "memory");
   __asm__ __volatile__("MSR PRIMASK, %0" : : "r" (mask));
   return old;
}

/**
 * Critical region protection: this should disable interrupts
 * to protect OS data structures during modification. It must
 * allow nested calls, which means that interrupts should only
 * be re-enabled when the outer CRITICAL_END() is reached.
 */
#define CRITICAL_STORE      uint32_t __irq_flags
#if !defined(DEBUG_CRITICAL)
#define CRITICAL_START()    __irq_flags = cm_mask_interrupts(1ul)
#define CRITICAL_END()      (void) cm_mask_interrupts(__irq_flags)
#else
void __break_for_debug(uint32_t arg);

#define CRITICAL_START()                                     \
   do                                                        \
   {                                                         \
      __irq_flags = cm_mask_interrupts(1ul);                 \
      if ((__irq_flags & ~1ul) != 0)                         \
      {                                                      \
         __break_for_debug(__irq_flags);                     \
      }                                                      \
   } while(0)

#define CRITICAL_END()                                          \
   do                                                           \
   {                                                            \
      if ((__irq_flags & ~1ul) != 0)                            \
      {                                                         \
         __break_for_debug(__irq_flags);                        \
      }                                                         \
      (void)cm_mask_interrupts(__irq_flags);                    \
   } while (0)
#endif /* !defined(DEBUG_CRITICAL) */

/**
 * When using newlib, define port private field in atom_tcb to be a
 * struct _reent.
 */
#if defined(__NEWLIB__)
struct cortex_port_priv
{
   struct _reent reent; /* reentrant context for newlib */
#if defined(ATOMPORT_CONFIG_THREAD_PROFILE)
   uint64_t cycles;     /* accumulated cycles */
#endif /* defined(ATOMPORT_CONFIG_THREAD_PROFILE) */
};

#define THREAD_PORT_PRIV    struct cortex_port_priv port_priv
#endif /* defined(__NEWLIB__) */

#endif /* defined(__ATOM_PORT_H) */
