/*
Copyright(c) 2017 Cedric Jimenez

This file is part of Nano-OS.

Nano-OS is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Nano-OS is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with Nano-OS.  If not, see <http://www.gnu.org/licenses/>.
*/

    .syntax unified
    .cpu cortex-m4
    .fpu vfpv4
    .thumb

    /** \brief Service call number for the first context switch */
	.equ SVC_FIRST_CONTEXT_SWITCH, 0x24
	/** \brief Service call number to switch to priviledged mode */
	.equ SVC_SWITCH_TO_PRIVILEDGED_MODE, 0xAA

	.global NANO_OS_PORT_GetTaskStackPointer

	.global NANO_OS_PORT_SaveInterruptStatus
	.global NANO_OS_PORT_RestoreInterruptStatus

	.global NANO_OS_PORT_FirstContextSwitch
	.global NANO_OS_PORT_ContextSwitch
	.global NANO_OS_PORT_ContextSwitchFromIsr

	.global NANO_OS_PORT_SwitchToPriviledgedMode
	.global NANO_OS_PORT_SwitchToUnpriviledgedMode

	.global NANO_OS_PORT_SvcHandler
	.global NANO_OS_PORT_PendSvHandler

    .extern g_nano_os




.thumb_func
.type NANO_OS_PORT_GetTaskStackPointer, %function
/* uint32_t NANO_OS_PORT_GetTaskStackPointer(void)
   Get the current value of the task stack pointer -> Register R0 */
NANO_OS_PORT_GetTaskStackPointer:

	mrs		r0, psp
	blx		lr



.thumb_func
.type NANO_OS_PORT_SaveInterruptStatus, %function
/* nano_os_int_status_reg_t NANO_OS_PORT_SaveInterruptStatus(void)
   Disable interrupts and return previous interrupt status register -> Register R0 */
NANO_OS_PORT_SaveInterruptStatus:

    mrs     r0, primask
    cpsid   i
    bx      lr


.thumb_func
.type NANO_OS_PORT_RestoreInterruptStatus, %function
/* void NANO_OS_PORT_RestoreInterruptStatus(const nano_os_int_status_reg_t int_status_reg)
   Restore the interrupt status register passed in parameter -> Register R0 */
NANO_OS_PORT_RestoreInterruptStatus:

    msr     primask, r0
    bx      lr




.thumb_func
.type NANO_OS_PORT_SwitchToPriviledgedMode, %function
/* void NANO_OS_PORT_SwitchToPriviledgedMode(void)
   Switch the CPU to priviledged mode */
NANO_OS_PORT_SwitchToPriviledgedMode:

	svc SVC_SWITCH_TO_PRIVILEDGED_MODE
	bx lr


.thumb_func
.type NANO_OS_PORT_SwitchToUnpriviledgedMode, %function
/* void NANO_OS_PORT_SwitchToUnpriviledgedMode(void)
   Switch the CPU to unpriviledged mode */
NANO_OS_PORT_SwitchToUnpriviledgedMode:

	mrs 	r0, control
	movs	r1, #0x01	/* nPRIV bit = 1 */
	orrs	r0, r0, r1
	msr		control, r0

	bx lr



.thumb_func
.type NANO_OS_PORT_FirstContextSwitch, %function
/* nano_os_error_t NANO_OS_PORT_FirstContextSwitch(void)
   Port specific first task context switch */
NANO_OS_PORT_FirstContextSwitch:

    /* Set SP=MSP to point to the reset MSP value to use initial C stack as exception stack. */
    ldr     r0, =0xE000ED08
    ldr     r0, [r0]
    ldr     r1, [r0]
    mov		sp, r1

    /* Enable interrupts */
    cpsie	i

	/* Start first context switch */
	svc		SVC_FIRST_CONTEXT_SWITCH

	/* Return to caller (should never happen)*/
    bx      lr



.thumb_func
.type NANO_OS_PORT_ContextSwitchFromIsr, %function
/* void NANO_OS_PORT_ContextSwitchFromIsr(void)
   Port specific interrupt level context switch */
NANO_OS_PORT_ContextSwitchFromIsr:

	/* Initialize a PendSv exception to perform the context switch */
    ldr     r0, =0x10000000 /* PendSv Mask */
    ldr     r1, =0xE000ED04 /* ICSR register */
    ldr     r2, [r1]
    orr     r2, r2, r0
    str     r2, [r1]

    /* Return to caller */
    bx      lr



.thumb_func
.type NANO_OS_PORT_ContextSwitch, %function
/* void NANO_OS_PORT_ContextSwitch(void)
   Port specific task level context switch : register saving + context switch */
NANO_OS_PORT_ContextSwitch:

    /* Initialize a PendSv exception to perform the context switch */
    ldr     r0, =0x10000000 /* PendSv Mask */
    ldr     r1, =0xE000ED04 /* ICSR register */
    ldr     r2, [r1]
    orr     r2, r2, r0
    str     r2, [r1]

    /* Enable interrupt to perform context switch */
    cpsie   i

    /* Disable interrupt before returning to OS */
    cpsid   i

    /* Return to OS protected code */
    bx      lr


.thumb_func
.type NANO_OS_PORT_SvcHandler, %function
/* void NANO_OS_PORT_SvcHandler(void)
   Handler for the SVC exception. Performs switchs between priviledged modes */
NANO_OS_PORT_SvcHandler:

	/* Check which stack was used for SVC call */
	tst 	lr, #0x04
	ite 	eq
	mrseq 	r0, msp
	mrsne 	r0, psp

	/* Extract SVC number */
	ldr		r0, [r0, #24]
	ldrb	r0, [r0, #-2]

	/* Branch to corresponding handler */
	movs	r1, SVC_FIRST_CONTEXT_SWITCH
	cmp		r0, r1
	beq		NANO_OS_PORT_SvcHandler_FirstContextSwitch
	movs	r1, SVC_SWITCH_TO_PRIVILEDGED_MODE
	cmp		r0, r1
	beq		NANO_OS_PORT_SvcHandler_SwitchToPriviledgedMode

NANO_OS_PORT_SvcHandler_FirstContextSwitch:
	/* First context switch */

	/* Get the stack pointer of the next task */
    ldr     r0, =g_nano_os
    ldr     r1, [r0, #4]
    ldr     r2, [r1]

    /* g_nano_os.current_task = g_nano_os.next_running_task */
    str     r1, [r0]

    /* Reset MSP */
	adds	sp, sp, #0x20

	/* Check if the task uses FPU */
	ldrb	r0, [r1, #4]
	cmp		r0, #1
	itte	eq

	/* If it uses FPU, load additionnal FPU context */
	vldmiaeq	r2!, {s16-s31}
	ldreq		r0, =0xFFFFFFED
	ldrne		r0, =0xFFFFFFFD

	/* Restore the control register from the next task stack */
	ldmia	r2!, {r3}
	msr		control, r3

	/* Restore the additionnals registers from the next task stack */
    ldmia	r2!, {r4-r11}
    msr		psp, r2

	/* Exit exception and configure CPU to use PSP for task's stack pointers
	   with FPU enabled depending on the task to switch on */
    bx      r0

NANO_OS_PORT_SvcHandler_SwitchToPriviledgedMode:
	/* Switch the CPU to priviledged mode */
	mrs		r0, control
	bfc		r0, #0, #1    	/* nPRIV bit = 0 */
	msr		control, r0

	/* Exit exception */
    bx      lr


.thumb_func
.type NANO_OS_PORT_PendSvHandler, %function
/* void NANO_OS_PORT_PendSvHandler()
   Handler for the PendSv exception. Performs context switchs */
NANO_OS_PORT_PendSvHandler:

    /* Disable interrupts */
    cpsid   i

    /* Save the additionnals registers to the current task stack */
    mrs		r12, psp
    stmdb   r12!, {r4-r11}

    /* Save control register */
    mrs		r4, control
    stmdb   r12!, {r4}

    /* Get the stack pointer of the next task */
    ldr     r0, =g_nano_os
    ldr     r1, [r0, #4]
    ldr     r2, [r1]

    /* Check if the current task uses FPU */
	ldr 	r3, [r0]
	ldrb	r4, [r3, #4]
	cmp		r4, #1
	it		eq

	/* If it uses FPU, save additionnal FPU context */
	vstmdbeq	r12!, {s16-s31}

    /* Save the stack pointer for the current task */
    str     r12, [r3]

    /* Set the stack pointer to the next task */
    mov     r12, r2

    /* g_nano_os.current_task = g_nano_os.next_running_task */
    str     r1, [r0]

	/* Check if the next task uses FPU */
	ldrb	r0, [r1, #4]
	cmp		r0, #1
	itte	eq

	/* If it uses FPU, restore additionnal FPU context */
	vldmiaeq	r12!, {s16-s31}
	ldreq		lr, =0xFFFFFFED
	ldrne		lr, =0xFFFFFFFD

	/* Restore the control register from the next task stack */
	ldmia	r12!, {r4}
	msr		control, r4

    /* Restore the additionnals registers from the next task stack */
    ldmia	r12!, {r4-r11}
    msr		psp, r12

    /* Enable interrupts */
    cpsie   i

    /* Exit exception */
    bx      lr


    .end
