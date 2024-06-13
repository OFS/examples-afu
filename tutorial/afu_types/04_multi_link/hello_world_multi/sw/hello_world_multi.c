// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <uuid/uuid.h>

#include <opae/fpga.h>

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)


//
// Connect to an accelerator matching UUID
//
static fpga_result
connect_to_matching_accel(const char *accel_uuid,
                          fpga_handle *accel_handle,
                          bool *is_ase_sim)
{
    fpga_properties filter = NULL;
    fpga_guid guid;
    fpga_token accel_token;
    uint32_t num_matches;
    fpga_result r;

    assert(accel_handle);

    // Don't print verbose messages in ASE by default
    setenv("ASE_LOG", "0", 0);
    *is_ase_sim = false;

    // Set up a filter that will search for an accelerator
    fpgaGetProperties(NULL, &filter);
    fpgaPropertiesSetObjectType(filter, FPGA_ACCELERATOR);

    // Add the desired UUID to the filter
    uuid_parse(accel_uuid, guid);
    fpgaPropertiesSetGUID(filter, guid);

    // Do the search across the available FPGA contexts
    r = fpgaEnumerate(&filter, 1, &accel_token, 1, &num_matches);
    if ((FPGA_OK != r) || (num_matches < 1))
    {
        fprintf(stderr, "Accelerator %s not found!\n", accel_uuid);
        goto out_destroy_filter;
    }

    // Open accelerator
    r = fpgaOpen(accel_token, accel_handle, 0);
    if (FPGA_OK != r)
    {
        fprintf(stderr, "Error opening accelerator %s!\n", accel_uuid);
        goto out_destroy_token;
    }

    // While the token is available, check whether it is for HW
    // or for ASE simulation, recording it so probeForASE() below
    // doesn't have to run through the device list again.
    fpga_properties accel_props;
    uint16_t vendor_id, dev_id;
    fpgaGetProperties(accel_token, &accel_props);
    fpgaPropertiesGetVendorID(accel_props, &vendor_id);
    fpgaPropertiesGetDeviceID(accel_props, &dev_id);
    *is_ase_sim = (vendor_id == 0x8086) && (dev_id == 0xa5e);

  out_destroy_token:
    fpgaDestroyToken(&accel_token);
  out_destroy_filter:
    fpgaDestroyProperties(&filter);

    return r;
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

    r = fpgaPrepareBuffer(accel_handle, size, (void*)&buf, wsid, 0);
    if (FPGA_OK != r) return NULL;

    // Get the physical address of the buffer in the accelerator
    r = fpgaGetIOAddress(accel_handle, *wsid, io_addr);
    assert(FPGA_OK == r);

    return buf;
}


int main(int argc, char *argv[])
{
    fpga_handle accel_handle;
    volatile char *buf;
    uint64_t wsid;
    uint64_t buf_pa;
    bool is_ase_sim = false;
    fpga_result r;
    uint32_t i;

    // Find and connect to the accelerators
    r = connect_to_matching_accel(AFU_ACCEL_UUID, &accel_handle, &is_ase_sim);
    if (r != FPGA_OK)
    {
        fprintf(stderr, "Failure -- exiting\n");
        exit(1);
    }

    if (is_ase_sim)
    {
        printf("   *** ASE only detects a single AFU (port 0) ***\n");
    }

    // The DFHv1 spec encodes the offset to the AFU's registers at 0x18
    // in the primary header.
    uint64_t csr_base;
    fpgaReadMMIO64(accel_handle, 0, 0x18, &csr_base);
    printf("Parent CSRs at 0x%" PRIx64 "\n", csr_base);

    // The AFU returns the data bus width at csr_base+8
    uint64_t bus_width_bytes;
    fpgaReadMMIO64(accel_handle, 0, csr_base + 0x8, &bus_width_bytes);
    printf("Bus width is %" PRId64 " bytes\n", bus_width_bytes);

    // Allocate a single page memory buffer. This buffer will be accessible
    // from the parent and all children at the same address (buf_pa).
    buf = (volatile char*)alloc_buffer(accel_handle, getpagesize(),
                                       &wsid, &buf_pa);
    assert(NULL != buf);

    // Set the low byte of the shared buffer to 0.  The FPGA will write
    // a non-zero value to it.
    buf[0] = 0;

    // Tell the accelerator the address of the buffer using cache line
    // addresses.  The accelerator will respond by writing to the buffer.
    fpgaWriteMMIO64(accel_handle, 0, 0, buf_pa / CL(1));

    // Spin, waiting for the value in memory to change to something non-zero.
    while (0 == buf[0])
    {
        // A well-behaved program would use _mm_pause(), nanosleep() or
        // equivalent to save power here.
    };

    // Print the string written by the FPGA
    printf("%s\n", buf);


    //
    // Now access the children. In this AFU, each child has its own MMIO
    // control space.
    //
    fpga_handle child_handles[8];
    uint32_t num_child_handles;
    r = fpgaGetChildren(accel_handle, 8, child_handles, &num_child_handles);
    printf("Num children: %d\n", num_child_handles);

    // Trigger a memory request in each child. The buffer is available
    // on all children at the same address. Except for the MMIO write handle,
    // this loop is the same sequence as the parent above.
    for (i = 0; i < num_child_handles; i += 1)
    {
        buf[0] = 0;
        // Write to a child MMIO space
        fpgaWriteMMIO64(child_handles[i], 0, 0, buf_pa / CL(1));

        while (0 == buf[0]) {};
        printf("%s\n", buf);
    }

    // Done
    fpgaReleaseBuffer(accel_handle, wsid);
    // The children are closed as a side effect of closing the parent handle
    fpgaClose(accel_handle);

    return 0;
}
