// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __DMA_UTIL_H__
#define __DMA_UTIL__H__

typedef enum dma_mode {
   stand_by    = 0x0,
   host_to_ddr = 0x1,
   ddr_to_host = 0x2,
   ddr_to_ddr  = 0x3
} e_dma_mode;

typedef struct __attribute__((__packed__))  {
   uint32_t src_address;
   uint32_t dest_address;
   uint32_t len;
   uint32_t control;
} dma_descriptor_t;

void mmio_read64( fpga_handle accel_handle, 
                  uint64_t addr, 
                  uint64_t *data, 
                  const char *reg_name);

void mmio_read64_silent(fpga_handle accel_handle, 
                        uint64_t addr,
                        uint64_t *data);

void send_descriptor( fpga_handle accel_handle, 
                      uint64_t mmio_dst, 
                      dma_descriptor_t desc);

void dma_transfer(fpga_handle accel_handle, 
                  e_dma_mode mode,
                  uint64_t src, 
                  uint64_t dest, 
                  int len,
                  bool verbose);

volatile void* alloc_io_shared_buffer(fpga_handle accel_handle,
                                   ssize_t size,
                                   uint64_t *wsid,
                                   uint64_t *io_addr);

fpga_result alloc_fpga_mem_buffer(size_t size, 
                                  uint64_t *addr);


#endif // __DMA_UTIL__H__
