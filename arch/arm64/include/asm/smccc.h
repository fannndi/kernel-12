/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __ASM_ARM_SMCCC_H
#define __ASM_ARM_SMCCC_H

#include <linux/types.h>

/* SMCCC version */
#define ARM_SMCCC_VERSION_1_0	0x10000
#define ARM_SMCCC_VERSION_1_1	0x10001

/* ARM SMCCC function IDs */
#define ARM_SMCCC_VERSION_FUNC_ID		0x80000000
#define ARM_SMCCC_ARCH_FEATURES_FUNC_ID		0x80000001
#define ARM_SMCCC_SMCCC_VERSION_FUNC_ID		0x80000000

/* Feature identifiers */
#define ARM_SMCCC_ARCH_WORKAROUND_1	0x80008000
#define ARM_SMCCC_ARCH_WORKAROUND_2	0x80008001

/* Conduit types */
#define SMCCC_CONDUIT_NONE	0
#define SMCCC_CONDUIT_SMC	1
#define SMCCC_CONDUIT_HVC	2

/* Result struct */
struct arm_smccc_res {
	unsigned long a0;
	unsigned long a1;
	unsigned long a2;
	unsigned long a3;
};

/* SMCCC call wrapper */
static inline void arm_smccc_1_1_smc(unsigned long a0, unsigned long a1,
				     unsigned long a2, unsigned long a3,
				     unsigned long a4, unsigned long a5,
				     unsigned long a6, unsigned long a7,
				     struct arm_smccc_res *res)
{
	register unsigned long x0 asm("x0") = a0;
	register unsigned long x1 asm("x1") = a1;
	register unsigned long x2 asm("x2") = a2;
	register unsigned long x3 asm("x3") = a3;
	register unsigned long x4 asm("x4") = a4;
	register unsigned long x5 asm("x5") = a5;
	register unsigned long x6 asm("x6") = a6;
	register unsigned long x7 asm("x7") = a7;

	asm volatile("smc #0"
		     : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3),
		       "+r"(x4), "+r"(x5), "+r"(x6), "+r"(x7)
		     :
		     : "memory");

	if (res) {
		res->a0 = x0;
		res->a1 = x1;
		res->a2 = x2;
		res->a3 = x3;
	}
}

/* Simple wrapper */
static inline long call_smccc_arch_features(unsigned long func_id)
{
	struct arm_smccc_res res;

	arm_smccc_1_1_smc(ARM_SMCCC_ARCH_FEATURES_FUNC_ID, func_id,
			  0, 0, 0, 0, 0, 0, &res);

	return res.a0;
}

#endif /* __ASM_ARM_SMCCC_H */