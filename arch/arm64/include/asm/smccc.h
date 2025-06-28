/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __ASM_SMCCC_H
#define __ASM_SMCCC_H

#include <linux/linkage.h>

#define ARM_SMCCC_STD_CALL		0
#define ARM_SMCCC_FAST_CALL		1
#define ARM_SMCCC_TYPE_SHIFT		31
#define ARM_SMCCC_TYPE_MASK		0x1

#define ARM_SMCCC_SMC_32		0
#define ARM_SMCCC_SMC_64		1
#define ARM_SMCCC_CALL_CONV_SHIFT	30
#define ARM_SMCCC_CALL_CONV_MASK	0x1

#define ARM_SMCCC_OWNER_SHIFT		24
#define ARM_SMCCC_OWNER_MASK		0x3f

#define ARM_SMCCC_FUNC_MASK		0xffff

#define ARM_SMCCC_CALL_VAL(type, call_conv, owner, func_num) \
	((((type) & ARM_SMCCC_TYPE_MASK) << ARM_SMCCC_TYPE_SHIFT) | \
	 (((call_conv) & ARM_SMCCC_CALL_CONV_MASK) << ARM_SMCCC_CALL_CONV_SHIFT) | \
	 (((owner) & ARM_SMCCC_OWNER_MASK) << ARM_SMCCC_OWNER_SHIFT) | \
	 ((func_num) & ARM_SMCCC_FUNC_MASK))

#endif /* __ASM_SMCCC_H */