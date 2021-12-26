#include "xil_printf.h"

#include "atom.h"
#include "atomtimer.h"
#include "atommutex.h"

#define IDLE_STACK_SIZE    512
#define THREAD1_STACK_SIZE 1024
#define THREAD2_STACK_SIZE (THREAD1_STACK_SIZE)
#define THREAD3_STACK_SIZE (THREAD1_STACK_SIZE)

/* Priority is inverse, where low is high (idle=255)*/
#define LOW_PRIORITY       20
#define NORMAL_PRIORITY    15
#define HIGH_PRIORITY      10

ATOM_MUTEX putsMutex;

ATOM_TCB thread1_tcb;
ATOM_TCB thread2_tcb;
ATOM_TCB thread3_tcb;
static uint32_t idle_thread_stack[IDLE_STACK_SIZE / sizeof(uint32_t)];
static uint32_t thread1_stack[THREAD1_STACK_SIZE / sizeof(uint32_t)];
static uint32_t thread2_stack[THREAD2_STACK_SIZE / sizeof(uint32_t)];
static uint32_t thread3_stack[THREAD3_STACK_SIZE / sizeof(uint32_t)];

static void exPuts(const char* str)
{
    uint8_t status;
    status = atomMutexGet(&putsMutex, 0);
    if (status == ATOM_OK)
    {
        print(str);
        (void)atomMutexPut(&putsMutex);
    }
} /* end of exPuts() */

static void thread1_main(uint32_t arg)
{
    uint32_t sleepyTime = arg * SYSTEM_TICKS_PER_SEC;

    exPuts("Thread 1 says \"Hello\"\r\n");
    for (;;)
    {
        (void)atomTimerDelay(sleepyTime);
        exPuts(" (1)");
    }
} /* end of thread1_main() */

static void thread2_main(uint32_t arg)
{
    uint32_t sleepyTime = arg * SYSTEM_TICKS_PER_SEC;

    exPuts("Thread 2 says \"Hello\"\r\n");
    for (;;)
    {
        (void)atomTimerDelay(sleepyTime);
        exPuts(" (2)");
    }
} /* end of thread2_main() */

static void thread3_main(uint32_t arg)
{
    uint32_t sleepyTime = arg * SYSTEM_TICKS_PER_SEC;

    exPuts("Thread 3 says \"Huh?\"\r\n");
    for (;;)
    {
        (void)atomTimerDelay(sleepyTime);
        exPuts(" (3)");
    }
} /* end of threadX_main() */

int main()
{
    uint8_t status;

    print("Hello World\n\r");
    status = atomOSInit((uint8_t*)idle_thread_stack, IDLE_STACK_SIZE, FALSE);
    if (status == ATOM_OK)
    {
        status = atomMutexCreate(&putsMutex);
    }

    if (status == ATOM_OK)
    {
        status = atomThreadCreate(&thread1_tcb,
                                  NORMAL_PRIORITY,
                                  thread1_main,
                                  1u,
                                  (uint8_t*)thread1_stack,
                                  THREAD1_STACK_SIZE,
                                  TRUE);
    }
    if (status == ATOM_OK)
    {
        status = atomThreadCreate(&thread2_tcb,
                                  LOW_PRIORITY,
                                  thread2_main,
                                  2u,
                                  (uint8_t*)thread2_stack,
                                  THREAD2_STACK_SIZE,
                                  TRUE);
    }
    if (status == ATOM_OK)
    {
        status = atomThreadCreate(&thread3_tcb,
                                  HIGH_PRIORITY,
                                  thread3_main,
                                  3u,
                                  (uint8_t*)thread3_stack,
                                  THREAD3_STACK_SIZE,
                                  TRUE);
    }

    if (status == ATOM_OK)
    {
        print("Starting kernel now\r\n");
        atomOSStart();
        print("Returned from kernel?\r\n");
    }
    print("By all rights, this should not appear on the console...\r\n");
    return 0;
}
