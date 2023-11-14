// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __DMA_H__
#define __DMA_H__

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

int dma(
    fpga_handle accel_handle, bool is_ase_sim,
    uint32_t chunk_size,
    uint32_t completion_freq,
    bool use_interrupts,
    uint32_t max_reqs_in_flight);

#endif // __DMA_H__
