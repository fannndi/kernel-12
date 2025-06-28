// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2016 ARM Ltd.
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/errno.h>
#include <linux/smp.h>

#include <asm/processor.h>
#include <asm/smp_plat.h>
#include <asm/smccc.h>

static u32 smccc_conduit = SMCCC_CONDUIT_NONE;

static int __init detect_smccc_conduit(void)
{
    u64 features;

    features = call_smccc_arch_features(ARM_SMCCC_ARCH_FEATURES_FUNC_ID);
    if ((s32)features < 0)
        return -ENODEV;

    features = call_smccc_arch_features(ARM_SMCCC_SMCCC_VERSION_FUNC_ID);
    if ((s32)features < 0)
        return -ENODEV;

    smp_wmb();
    smccc_conduit = arm64_smccc_get_conduit();
    return 0;
}
early_initcall(detect_smccc_conduit);

u32 arm64_get_smccc_conduit(void)
{
    smp_rmb();
    return smccc_conduit;
}
EXPORT_SYMBOL(arm64_get_smccc_conduit);

void arm64_update_smccc_conduit(u32 conduit)
{
    smp_wmb();
    smccc_conduit = conduit;
}
EXPORT_SYMBOL_GPL(arm64_update_smccc_conduit);