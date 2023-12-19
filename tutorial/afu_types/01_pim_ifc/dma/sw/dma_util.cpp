// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <assert.h>
#include <getopt.h>
#include <uuid/uuid.h>

#include <opae/fpga.h>
#include "dma.h"
#include "dma_util.h"

void mmio_read64(fpga_handle accel_handle, uint64_t addr, uint64_t *data, const char *reg_name){
   fpgaReadMMIO64(accel_handle, 0, addr, data);
   printf("Reading %s (Byte Offset=%08lx) = %08lx\n", reg_name, addr, *data);
}

void mmio_read64_silent(fpga_handle accel_handle, uint64_t addr, uint64_t *data) {
   fpgaReadMMIO64(accel_handle, 0, addr, data);
}

void send_descriptor(fpga_handle accel_handle, uint64_t mmio_dst, /*uint64_t *host_src,*/ dma_descriptor_t desc) {
   //mmio requires 8 byte alignment
   //assert(len % 8 == 0);
   assert(mmio_dst % 8 == 0);
   
   uint32_t dev_addr = mmio_dst;
   //uint64_t *host_addr = host_src;

    fpgaWriteMMIO64(accel_handle, 0, dev_addr, desc.src_address);
    printf("Writing %08X to address %08X\n", desc.src_address,dev_addr);
    dev_addr += 8;
    fpgaWriteMMIO64(accel_handle, 0, dev_addr, desc.dest_address);
    printf("Writing %08X to address %08X\n", desc.dest_address,dev_addr);
    dev_addr += 8;
    fpgaWriteMMIO64(accel_handle, 0, dev_addr, desc.len);
    printf("Writing %08X to address %08X\n", desc.len,dev_addr);
    dev_addr += 8;
    fpgaWriteMMIO64(accel_handle, 0, dev_addr, desc.control);
    printf("Writing %08X to address %08X\n", desc.control,dev_addr);
   
}

//
// Allocate a buffer in I/O memory, shared with the FPGA.
//
volatile void* alloc_io_shared_buffer(fpga_handle accel_handle,
                                              size_t size,
                                              uint64_t *wsid,
                                              uint64_t *io_addr) {
    fpga_result r;
    volatile void* buf;

    r = fpgaPrepareBuffer(accel_handle, size, (void**)&buf, wsid, 0);
    if (FPGA_OK != r) return NULL;

    // Get the physical address of the buffer in the accelerator
    r = fpgaGetIOAddress(accel_handle, *wsid, io_addr);
    assert(FPGA_OK == r);

    return buf;
}

//
// Allocate a buffer in FPGA memory, local to FPGA.
// 
//
static int64_t free_base_addr = 0;
fpga_result alloc_fpga_mem_buffer(size_t size, uint64_t *addr) {
  if (size == 0) {
    return FPGA_NO_MEMORY;
  }
  // align base addr with mem bus width
  *addr = (free_base_addr + DMA_FPGA_MEM_ALIGNMENT - 1) & ~(DMA_FPGA_MEM_ALIGNMENT - 1);
  
  // 4GB boundary alignment // TODO: This is a limitation in RTL right now
  uint64_t next_boundary = (*addr / DMA_FPGA_MEM_BANK_SIZE + 1) * DMA_FPGA_MEM_BANK_SIZE;
  if (*addr / DMA_FPGA_MEM_BANK_SIZE != (*addr + size - 1) / DMA_FPGA_MEM_BANK_SIZE) {
    *addr = DMA_FPGA_MEM_BANK_SIZE;
  }

  if (*addr + size > DMA_FPGA_MEM_BANK_SIZE * DMA_FPGA_NUM_MEM_BANKS || *addr < free_base_addr) {
    return FPGA_NO_MEMORY;
  }

  free_base_addr = *addr + size;
  return FPGA_OK;
}

void dma_transfer(fpga_handle accel_handle, e_dma_mode mode, uint64_t src, uint64_t dest, int len) {
   fpga_result     res = FPGA_OK;
   
   //dma requires 64 byte alignment
   //assert(len % 64 == 0);
   assert(src % 64 == 0);
   assert(dest % 64 == 0);
   
   //only 32bit for now //TODO: remove mask when >32 addr space accepted. Assume address being passed in is in boundary range
   const uint64_t MASK_FOR_32BIT_ADDR = 0xFFFFFFFF;
   
   dma_descriptor_t desc;
   desc.src_address = src & MASK_FOR_32BIT_ADDR;
   desc.dest_address = dest & MASK_FOR_32BIT_ADDR;  
   desc.len = len;
   desc.control = 0x80000000 | (mode << MODE_SHIFT);
      
   const uint64_t DMA_DESC_BASE = 8*DMA_CSR_IDX_SRC_ADDR;
   const uint64_t DMA_STATUS_BASE = 8*DMA_CSR_IDX_STATUS;
   uint64_t mmio_data = 0;
   
   //int desc_size = sizeof(desc)/sizeof(desc.control);
   int desc_size = sizeof(desc);
   printf("Descriptor size   = %d\n", desc_size);
   printf("desc.src_address  = %04X\n", desc.src_address);
   printf("desc.dest_address = %04X\n", desc.dest_address);
   printf("desc.len          = %d\n", desc.len);
   printf("desc.control      = %04X\n", desc.control);

   //send descriptor
   send_descriptor(accel_handle, DMA_DESC_BASE, desc);
   
   //TODO: the status register is only 32 bits.  Need to update this.
   mmio_read64_silent(accel_handle, DMA_STATUS_BASE, &mmio_data);
   // If the descriptor buffer is empty, then we are done
   while((mmio_data&0x1) == 0x1) {
   #ifdef USE_ASE
         sleep(1);
         mmio_read64(accel_handle, DMA_STATUS_BASE, &mmio_data, "dma_csr_base");
   #else
         mmio_read64_silent(accel_handle, DMA_STATUS_BASE, &mmio_data);
   #endif
   } 
}
