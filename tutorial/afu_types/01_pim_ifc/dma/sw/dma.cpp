// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <poll.h>
#include <pthread.h>

//#include <iostream>
//using namespace std;

#include <opae/fpga.h>
#include "dma.h"
#include "dma_util.h"

///typedef struct
///{
///    volatile char *ptr;
///    uint64_t wsid;
///    uint64_t pa;
///}
///t_pinned_buffer;

static fpga_handle s_accel_handle;
static bool s_is_ase_sim;
static volatile uint64_t *s_mmio_buf;
static int s_error_count = 0;

static uint64_t dma_dfh_offset = -256*1024;

// Shorter runs for ASE
#define TOTAL_COPY_COMMANDS (s_is_ase_sim ? 1500L : 1000000L)
#define DMA_BUFFER_SIZE (1024*1024)

#define TEST_BUFFER_SIZE_ASE 8 * 1024
#define TEST_BUFFER_SIZE_HW 1024*1024-256

#define ON_ERR_GOTO(res, label, desc)  \
   do {                                \
      if ((res) != FPGA_OK) {          \
         print_err((desc), (res));     \
         s_error_count += 1;           \
         goto label;                   \
      }                                \
   } while (0)

void print_err(const char *s, fpga_result res) {
   fprintf(stderr, "Error %s: %s\n", s, fpgaErrStr(res));
}

// TODO: OBSOLETE
// Read a 64 bit CSR. When a pointer to CSR buffer is available, read directly.
// Direct reads can be significantly faster.
//
static inline uint64_t readMMIO64(uint32_t idx) {
    if (s_mmio_buf) {
        return s_mmio_buf[idx];
    } else {
        fpga_result r;
        uint64_t v;
        r = fpgaReadMMIO64(s_accel_handle, 0, 8 * idx, &v);
        assert(FPGA_OK == r);
        return v;
    }
}


// TODO: OBSOLETE
// Write a 64 bit CSR. When a pointer to CSR buffer is available, write directly.
//
static inline void writeMMIO64(uint32_t idx, uint64_t v) {
    if (s_mmio_buf) {
        s_mmio_buf[idx] = v;
    } else {
        fpgaWriteMMIO64(s_accel_handle, 0, 8 * idx, v);
    }
}


void print_csrs(){
    printf("AFU properties:\n");

    uint64_t dfh = readMMIO64(DMA_CSR_IDX_DFH);
    printf("  DMA_DFH:                %016lX\n", dfh);

    uint64_t guid_l = readMMIO64(DMA_CSR_IDX_GUID_L);
    printf("  DMA_GUID_L:             %016lX\n", guid_l);

    uint64_t guid_h = readMMIO64(DMA_CSR_IDX_GUID_H);
    printf("  DMA_GUID_H:             %016lX\n", guid_h);

    uint64_t rsvd_1 = readMMIO64(DMA_CSR_IDX_RSVD_1);
    printf("  DMA_RSVD_1:             %016lX\n", rsvd_1);

    uint64_t rsvd_2 = readMMIO64(DMA_CSR_IDX_RSVD_2);
    printf("  DMA_RSVD_2:             %016lX\n", rsvd_2);

    uint64_t src_addr = readMMIO64(DMA_CSR_IDX_SRC_ADDR);
    printf("  DMA_SRC_ADDR:           %016lX\n", src_addr);

    uint64_t dest_addr = readMMIO64(DMA_CSR_IDX_DEST_ADDR);
    printf("  DMA_DEST_ADDR:          %016lX\n", dest_addr);

    uint64_t length = readMMIO64(DMA_CSR_IDX_LENGTH);
    printf("  DMA_LENGTH:             %016lX\n", length);

    uint64_t descriptor_control = readMMIO64(DMA_CSR_IDX_DESCRIPTOR_CONTROL);
    printf("  DMA_DESCRIPTOR_CONTROL: %016lX\n", descriptor_control);

    uint64_t status = readMMIO64(DMA_CSR_IDX_STATUS);
    printf("  DMA_STATUS:             %016lX\n", status);

    uint64_t csr_control = readMMIO64(DMA_CSR_IDX_CONTROL);
    printf("  DMA_CONTROL:            %016lX\n", csr_control);

    uint64_t wr_re_fill_level = readMMIO64(DMA_CSR_IDX_WR_RE_FILL_LEVEL);
    printf("  DMA_WR_RE_FILL_LEVEL:   %016lX\n", wr_re_fill_level);

    uint64_t resp_fill_level = readMMIO64(DMA_CSR_IDX_RESP_FILL_LEVEL);
    printf("  DMA_RESP_FILL_LEVEL:    %016lX\n", resp_fill_level);

    uint64_t seq_num = readMMIO64(DMA_CSR_IDX_WR_RE_SEQ_NUM);
    printf("  DMA_WR_RE_SEQ_NUM:      %016lX\n", seq_num);

    uint64_t config1 = readMMIO64(DMA_CSR_IDX_CONFIG_1);
    printf("  DMA_CONFIG_1:           %016lX\n", config1);

    uint64_t config2 = readMMIO64(DMA_CSR_IDX_CONFIG_2);
    printf("  DMA_CONFIG_2:           %016lX\n", config2);

    uint64_t info = readMMIO64(DMA_CSR_IDX_TYPE_VERSION);
    printf("  DMA_TYPE_VERSION:       %016lX\n", info);

    printf("\n");
}



void copy_to_dev_with_mmio(fpga_handle accel_handle, uint64_t *host_src, uint64_t dev_dest, int len) {
   //mmio requires 8 byte alignment
   assert(len % 8 == 0);
   assert(dev_dest % 8 == 0);
   
   uint64_t dev_addr = dev_dest;
   
   uint64_t *host_addr = host_src;
   
   uint64_t cur_mem_page = dev_addr & ~DMA_MEM_WINDOW_SPAN_MASK;
   fpgaWriteMMIO64(accel_handle, 0, DMA_CSR_IDX_DESCRIPTOR_CONTROL, cur_mem_page);
   
   for(int i = 0; i < len/8; i++) {
      uint64_t mem_page = dev_addr & ~DMA_MEM_WINDOW_SPAN_MASK;
      if(mem_page != cur_mem_page) {
         cur_mem_page = mem_page;
         fpgaWriteMMIO64(accel_handle, 0, DMA_CSR_IDX_DESCRIPTOR_CONTROL, cur_mem_page);
      }
      // 
      fpgaWriteMMIO64(accel_handle, 0, MEM_WINDOW_MEM(dma_dfh_offset)+(dev_addr&DMA_MEM_WINDOW_SPAN_MASK), *host_addr);
      
      host_addr += 1;
      dev_addr += 8;
   }
}

void copy_dev_to_dev_with_dma(fpga_handle accel_handle, uint64_t dev_src, uint64_t dev_dest, int len) {
   fpga_result     res = FPGA_OK;
   
   //dma requires 64 byte alignment
   //assert(len % 64 == 0);
   assert(dev_src % 64 == 0);
   assert(dev_dest % 64 == 0);
   
   //only 32bit for now
   const uint64_t MASK_FOR_32BIT_ADDR = 0xFFFFFFFF;
   
   dma_descriptor_t desc;
   // Set the DMA Transaction type: host_to_ddr, ddr_to_host, ddr_to_ddr
   e_dma_mode descriptor_mode = ddr_to_host;
   
   desc.src_address = dev_src & MASK_FOR_32BIT_ADDR;
   desc.dest_address = dev_dest & MASK_FOR_32BIT_ADDR;  
   desc.len = len;
   desc.control = 0x80000000 | (descriptor_mode << MODE_SHIFT);
      
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
   while((mmio_data&0x1) !=0x1) {
   #ifdef USE_ASE
         sleep(1);
         mmio_read64(accel_handle, DMA_STATUS_BASE, &mmio_data, "dma_csr_base");
   #else
         mmio_read64_silent(accel_handle, DMA_STATUS_BASE, &mmio_data);
   #endif
   }
}

int run_basic_ddr_dma_test(fpga_handle accel_handle) {
   // Shared buffer in host memory 
   volatile uint64_t *dma_buf_ptr  = NULL;
   // Workspace ID used by OPAE to identify buffer
   uint64_t          dma_buf_wsid;
   // Return status buffer for OPAE library calls
   fpga_result        res  = FPGA_OK;
   int         num_errors  = 0;

   // Set test transfer size 
   uint32_t test_buffer_size;
   if(s_is_ase_sim)  
      test_buffer_size = TEST_BUFFER_SIZE_ASE;
   else              
      test_buffer_size = TEST_BUFFER_SIZE_HW; 

   // Set transfer size in number of beats of size awsize 
   const uint32_t awsize = 64; // 64 bytes per transfer - TODO: read the awsize from config register?
   uint32_t      dma_len = ((test_buffer_size - 1) / awsize) + 1; // Ceiling of test_buffer_size / awsize 
   printf("dma_len = %d\n", dma_len);

   // Create expected result 
   uint32_t test_buffer_word_size = test_buffer_size/8;
   char expected_result[test_buffer_size];
   uint64_t *expected_result_word_ptr = (uint64_t *)expected_result;
   for(int i = 0; i < test_buffer_word_size; i++) {
      expected_result_word_ptr[i] = (i % DMA_BURST_SIZE_WORDS == 0) ? 
                                    (i / DMA_BURST_SIZE_WORDS) + 1  : 0;
      printf("expected_result[%d] = %016lx\n", i, expected_result_word_ptr[i]);
   }

   printf("TEST_BUFFER_SIZE = %d\n", test_buffer_size);
   printf("DMA_BUFFER_SIZE  = %d\n", DMA_BUFFER_SIZE);

   // Initialize shared buffer
   res = fpgaPrepareBuffer(accel_handle, DMA_BUFFER_SIZE, 
                           (void **)&dma_buf_ptr, &dma_buf_wsid, 0);
   ON_ERR_GOTO(res, release_buf, "allocating dma buffer");
   memset((void *)dma_buf_ptr,  0x0, DMA_BUFFER_SIZE);

   // Store virtual address of IO registers
   uint64_t dma_buf_iova;
   res = fpgaGetIOAddress(accel_handle, dma_buf_wsid, &dma_buf_iova);
   ON_ERR_GOTO(res, release_buf, "getting dma DMA_BUF_IOVA");

   // DMA Transfer
   // Basic DMA transfer, DDR to Host
   printf ("\nBuffer before transfer:\n");
   for(int i = 0; i < test_buffer_word_size; i++) {
       printf("buffer[%d] = %016lx\n", i, dma_buf_ptr[i]);
   }
   copy_dev_to_dev_with_dma(accel_handle, 0, dma_buf_iova | DMA_HOST_MASK, dma_len);
   
   printf ("\nBuffer after transfer:\n");
   for(int i = 0; i < test_buffer_word_size; i++) {
       printf("buffer[%d] = %016lx\n", i, dma_buf_ptr[i]);
   }

   // Check expected result
   if(memcmp((void *)dma_buf_ptr, (void *)expected_result, test_buffer_size) != 0) {
		printf("ERROR: memcmp failed!\n");
		num_errors++;
	} else {
       printf("Success!");
   }

   release_buf:
      res = fpgaReleaseBuffer(accel_handle, dma_buf_wsid); 

}

int run_round_trip_transfer(fpga_handle accel_handle) {
   // Shared buffer in host memory 
   volatile uint64_t *dma_buf_ptr  = NULL;
   // Workspace ID used by OPAE to identify buffer
   uint64_t          dma_buf_wsid;
   // Return status buffer for OPAE library calls
   fpga_result        res  = FPGA_OK;
   int         num_errors  = 0;

   // Set test transfer size 
   uint32_t test_buffer_size;
   if(s_is_ase_sim)  
      test_buffer_size = TEST_BUFFER_SIZE_ASE;
   else              
      test_buffer_size = TEST_BUFFER_SIZE_HW; 
   uint32_t test_buffer_word_size = test_buffer_size/8;

   // Set transfer size in number of beats of size awsize 
   const uint32_t awsize = 64; // 64 bytes per transfer - TODO: read the awsize from config register?
   uint32_t      dma_len = ((test_buffer_size - 1) / awsize) + 1; // Ceiling of test_buffer_size / awsize 
   printf("dma_len = %d\n", dma_len);

   // Declare expected result buffer
   uint64_t *expected_result = (uint64_t *)malloc(DMA_BUFFER_SIZE);

   // Initialize shared buffer
   res = fpgaPrepareBuffer(accel_handle, DMA_BUFFER_SIZE, 
                           (void **)&dma_buf_ptr, &dma_buf_wsid, 0);
   ON_ERR_GOTO(res, release_buf, "allocating dma buffer");
   memset((void *)dma_buf_ptr,  0x0, DMA_BUFFER_SIZE);

   // Store virtual address of IO registers
   uint64_t dma_buf_iova;
   res = fpgaGetIOAddress(accel_handle, dma_buf_wsid, &dma_buf_iova);
   ON_ERR_GOTO(res, release_buf, "getting dma DMA_BUF_IOVA");
   
   printf ("\nBuffer before transfer:\n");
   for(int i = 0; i < test_buffer_word_size; i++) {
      dma_buf_ptr[i] = i;
      expected_result[i] = i;
      //printf("buffer[%d] = %016lx\n", i, dma_buf_ptr[i]);
   }

   uint64_t fpga_mem_addr;
   res = alloc_fpga_mem_buffer(test_buffer_size, &fpga_mem_addr);
   ON_ERR_GOTO(res, release_buf, "allocating fpga buffer");

   printf("FPGA mem addr: %lu\n", (uint64_t) fpga_mem_addr);
      
   // Transfer dma_buf to fpga memory
   dma_transfer(accel_handle, host_to_ddr, dma_buf_iova | DMA_HOST_MASK, fpga_mem_addr, dma_len);
   // Clear dma_buf
   memset((void *)dma_buf_ptr,  0x0, DMA_BUFFER_SIZE);
   // Read data back from fpga memory 
   dma_transfer(accel_handle, ddr_to_host, fpga_mem_addr, dma_buf_iova | DMA_HOST_MASK, dma_len); 

   printf ("\nBuffer after transfer:\n");
   for(int i = 0; i < test_buffer_word_size; i++) {
      //printf("buffer[%d] = %016lx\n", i, dma_buf_ptr[i]);
   }

   // Check expected result
   if(memcmp((void *)dma_buf_ptr, (void *)expected_result, test_buffer_size) != 0) {
		printf("ERROR: memcmp failed!\n");
		num_errors++;
	} else {
       printf("Success!");
   }

   release_buf:
      res = fpgaReleaseBuffer(accel_handle, dma_buf_wsid); 
   
   return 0;

}

int dma(
    fpga_handle accel_handle, bool is_ase_sim,
    uint32_t chunk_size,
    uint32_t completion_freq,
    bool use_interrupts,
    uint32_t max_reqs_in_flight)
{
    fpga_result r;

    s_accel_handle = accel_handle;
    s_is_ase_sim = is_ase_sim;

    // Get a pointer to the MMIO buffer for direct access. The OPAE functions will
    // be used with ASE since true MMIO isn't detected by the SW simulator.
    if (is_ase_sim)
    {
        s_mmio_buf = NULL;
    }
    else
    {
        uint64_t *tmp_ptr;
        r = fpgaMapMMIO(accel_handle, 0, &tmp_ptr);
        assert(FPGA_OK == r);
        s_mmio_buf = tmp_ptr;
    }

    //print_csrs();
    //run_basic_ddr_dma_test(s_accel_handle);
    //printf("\n");
    //print_csrs();

    run_round_trip_transfer(s_accel_handle);
    
}
