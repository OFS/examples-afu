// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __DMA_H__
#define __DMA_H__

#define USE_ASE
#define CLOCK_RATE_MHZ                 400 //400MHz
#define MAX_TRPT_BYTES                 (CLOCK_RATE_MHZ * 64) //64 Bytes per AXI read/write.
#define DMA_CSR_IDX_DFH                0x0
#define DMA_CSR_IDX_GUID_L             0x1
#define DMA_CSR_IDX_GUID_H             0x2
#define DMA_CSR_IDX_RSVD_1             0x3
#define DMA_CSR_IDX_RSVD_2             0x4
#define DMA_CSR_IDX_SRC_ADDR           0x5
#define DMA_CSR_IDX_DEST_ADDR          0x6
#define DMA_CSR_IDX_LENGTH             0x7
#define DMA_CSR_IDX_DESCRIPTOR_CONTROL 0x8
#define DMA_CSR_IDX_STATUS             0x9
#define DMA_CSR_IDX_CONTROL            0xA
#define DMA_CSR_IDX_WR_RE_FILL_LEVEL   0xB
#define DMA_CSR_IDX_RESP_FILL_LEVEL    0xC
#define DMA_CSR_IDX_WR_RE_SEQ_NUM      0xD
#define DMA_CSR_IDX_CONFIG_1           0xE
#define DMA_CSR_IDX_CONFIG_2           0xF
#define DMA_CSR_IDX_TYPE_VERSION       0x10
#define DMA_CSR_IDX_RD_SRC_PERF_CNTR   0x11
#define DMA_CSR_IDX_WR_DEST_PERF_CNTR  0x12
#define MODE_SHIFT                     26


#define CONTROL_BUSY_BIT               1
#define GET_CONTROL_BUSY(reg) ((1u << CONTROL_BUSY_BIT)&reg)
#define DMA_HOST_MASK		0x2000000000000
// #define DMA_HOST_MASK		0x0000000000000

#define DMA_BURST_SIZE_BYTES 8*8
#define DMA_BURST_SIZE_WORDS 8

//#define ACL_DMA_INST_ADDRESS_SPAN_EXTENDER_0_CNTL_BASE 0x200

#define DMA_MEM_WINDOW_SPAN (4*1024)
#define DMA_MEM_WINDOW_SPAN_MASK ((uint64_t)(DMA_MEM_WINDOW_SPAN-1))


#define ACL_DMA_INST_ADDRESS_SPAN_EXTENDER_0_WINDOWED_SLAVE_BASE 0x1000
#define MEM_WINDOW_MEM(dfh) (ACL_DMA_INST_ADDRESS_SPAN_EXTENDER_0_WINDOWED_SLAVE_BASE+dfh)

#define DMA_FPGA_MEM_BANK_SIZE (4L * 1024 * 1024 * 1024) // 4GB
#define DMA_FPGA_MEM_BANK_ADDR_MASK 0xFFFFFFFF 
#define DMA_FPGA_NUM_MEM_BANKS 4
#define DMA_FPGA_NUM_ADDR_BITS 32
#define DMA_FPGA_MEM_BUS_WIDTH 512
#define DMA_FPGA_MEM_ALIGNMENT 0x1FF

#define DMA_LINE_SIZE 64

int run_basic_ddr_dma_test(fpga_handle afc_handle);

int dma(
    fpga_handle accel_handle, bool is_ase_sim,
    uint32_t transfer_size,
    bool verbose);

#endif // __DMA_H__


