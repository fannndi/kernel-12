/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _MMC_CORE_BLOCK_H
#define _MMC_CORE_BLOCK_H

#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/list.h>

struct mmc_queue;
struct request;
struct mmc_blk_data;

void mmc_blk_issue_rq(struct mmc_queue *mq, struct request *req);

struct mmc_rpmb_data {
	struct device dev;
	struct mmc_blk_data *md;
	int id;
	u32 part_index;
	struct cdev chrdev;
	struct list_head node;
};

#endif