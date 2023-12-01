// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <poll.h>
#include <pthread.h>

#include <opae/fpga.h>
#include "dma.h"

///typedef struct
///{
///	 volatile char *ptr;
///	 uint64_t wsid;
///	 uint64_t pa;
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

//
// Allocate a buffer in I/O memory, shared with the FPGA.
//
static volatile void* alloc_buffer(fpga_handle accel_handle,
                                   ssize_t size,
                                   uint64_t *wsid,
                                   uint64_t *io_addr)
{
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
// Read a 64 bit CSR. When a pointer to CSR buffer is available, read directly.
// Direct reads can be significantly faster.
//
static inline uint64_t readMMIO64(uint32_t idx)
{
    if (s_mmio_buf)
    {
        return s_mmio_buf[idx];
    }
    else
    {
        fpga_result r;
        uint64_t v;
        r = fpgaReadMMIO64(s_accel_handle, 0, 8 * idx, &v);
        assert(FPGA_OK == r);
        return v;
    }
}


//
// Write a 64 bit CSR. When a pointer to CSR buffer is available, write directly.
//
static inline void writeMMIO64(uint32_t idx, uint64_t v)
{
    if (s_mmio_buf)
    {
        s_mmio_buf[idx] = v;
    }
    else
    {
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

void copy_to_dev_with_mmio(fpga_handle afc_handle, uint64_t *host_src, uint64_t dev_dest, int len) {
	//mmio requires 8 byte alignment
	assert(len % 8 == 0);
	assert(dev_dest % 8 == 0);
	
	uint64_t dev_addr = dev_dest;
	uint64_t *host_addr = host_src;
	
	uint64_t cur_mem_page = dev_addr & ~DMA_MEM_WINDOW_SPAN_MASK;
	fpgaWriteMMIO64(afc_handle, 0, DMA_CSR_IDX_DESCRIPTOR_CONTROL, cur_mem_page);
	
	for(int i = 0; i < len/8; i++) {
		uint64_t mem_page = dev_addr & ~DMA_MEM_WINDOW_SPAN_MASK;
		if(mem_page != cur_mem_page) {
			cur_mem_page = mem_page;
			fpgaWriteMMIO64(afc_handle, 0, DMA_CSR_IDX_DESCRIPTOR_CONTROL, cur_mem_page);
		}
		fpgaWriteMMIO64(afc_handle, 0, MEM_WINDOW_MEM(dma_dfh_offset)+(dev_addr&DMA_MEM_WINDOW_SPAN_MASK), *host_addr);
		
		host_addr += 1;
		dev_addr += 8;
	}
}


int run_basic_ddr_dma_test(fpga_handle afc_handle) {
	volatile uint64_t *dma_buf_ptr  = NULL;
	uint64_t        dma_buf_wsid;
	uint64_t dma_buf_iova;
	
	uint64_t data = 0;
	fpga_result     res = FPGA_OK;

#ifdef USE_ASE
	const int TEST_BUFFER_SIZE = 256;
	//const int TEST_BUFFER_SIZE = 256*128;
#else
	const int TEST_BUFFER_SIZE = 1024*1024-256;
#endif

   uint64_t desc_control;
	const int TEST_BUFFER_WORD_SIZE = TEST_BUFFER_SIZE/8;
	char test_buffer[TEST_BUFFER_SIZE];
	uint64_t *test_buffer_word_ptr = (uint64_t *)test_buffer;
	char test_buffer_zero[TEST_BUFFER_SIZE];
	const uint64_t DEST_PTR = 1024*1024;

	res = fpgaPrepareBuffer(afc_handle, DMA_BUFFER_SIZE,
		(void **)&dma_buf_ptr, &dma_buf_wsid, 0);
	ON_ERR_GOTO(res, release_buf, "allocating dma buffer");
	memset((void *)dma_buf_ptr,  0x0, DMA_BUFFER_SIZE);
	
	res = fpgaGetIOAddress(afc_handle, dma_buf_wsid, &dma_buf_iova);
	ON_ERR_GOTO(res, release_buf, "getting dma DMA_BUF_IOVA");
	
	printf("TEST_BUFFER_SIZE = %d\n", TEST_BUFFER_SIZE);
	printf("DMA_BUFFER_SIZE = %d\n", DMA_BUFFER_SIZE);
	
	memset(test_buffer_zero, 0, TEST_BUFFER_SIZE);
	
	
	for(int i = 0; i < TEST_BUFFER_WORD_SIZE; i++)
		test_buffer_word_ptr[i] = i;


    printf("About to write go bit");
    writeMMIO64(DMA_CSR_IDX_DESCRIPTOR_CONTROL, 0x9400000F);
    printf("Wrote go bit");
    printf("entering dowhile loop");
    do {
       desc_control = readMMIO64(DMA_CSR_IDX_DESCRIPTOR_CONTROL);
       printf("Waitin for busy done.  DMA_DESCRIPTOR_CONTROL: %016lX\n", desc_control);
    } while (GET_CONTROL_BUSY(desc_control));

 
   release_buf:
      res = fpgaReleaseBuffer(afc_handle, dma_buf_wsid); 

}

int dma(
    fpga_handle accel_handle, bool is_ase_sim,
    uint32_t chunk_size,
    uint32_t completion_freq,
    bool use_interrupts,
    uint32_t max_reqs_in_flight)
{
    fpga_result r;
    pthread_t intr_thread = 0;

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

    // TODO: Testing
    print_csrs();
    writeMMIO64(DMA_CSR_IDX_SRC_ADDR, 0x00FF);
    writeMMIO64(DMA_CSR_IDX_DEST_ADDR, 0xFF00);
    writeMMIO64(DMA_CSR_IDX_LENGTH, 0x0010);
    run_basic_ddr_dma_test(s_accel_handle);
    printf("\n");
    print_csrs();
    
}
