// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
// Search for all accelerators matching the requested properties and
// connect to them. The input value of *num_handles is the maximum
// number of connections allowed. (The size of accel_handles.) The
// output value of *num_handles is the actual number of connections.
//
static fpga_result
connect_to_matching_accels(const char *accel_uuid,
                           uint32_t *num_handles,
                           fpga_handle *accel_handles,
                           bool *is_ase_sim)
{
    fpga_properties filter = NULL;
    fpga_guid guid;
    const uint32_t max_tokens = 32;
    fpga_token accel_tokens[max_tokens];
    uint32_t num_matches;
    fpga_result r;

    assert(num_handles && *num_handles);
    assert(accel_handles);

    // Limit num_handles to max_tokens. We could be smarter and dynamically
    // allocate accel_tokens.
    if (*num_handles > max_tokens)
        *num_handles = max_tokens;

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
    r = fpgaEnumerate(&filter, 1, accel_tokens, *num_handles, &num_matches);
    if (*num_handles > num_matches)
        *num_handles = num_matches;

    if ((FPGA_OK != r) || (num_matches < 1))
    {
        fprintf(stderr, "Accelerator %s not found!\n", accel_uuid);
        goto out_destroy;
    }

    // Open accelerators
    uint32_t num_found = 0;
    for (uint32_t i = 0; i < *num_handles; i += 1)
    {
        r = fpgaOpen(accel_tokens[i], &accel_handles[num_found], 0);
        if (FPGA_OK == r)
        {
            num_found += 1;

            // While the token is available, check whether it is for HW
            // or for ASE simulation, recording it so probeForASE() below
            // doesn't have to run through the device list again.
            fpga_properties accel_props;
            uint16_t vendor_id, dev_id;
            fpgaGetProperties(accel_tokens[i], &accel_props);
            fpgaPropertiesGetVendorID(accel_props, &vendor_id);
            fpgaPropertiesGetDeviceID(accel_props, &dev_id);
            *is_ase_sim = (vendor_id == 0x8086) && (dev_id == 0xa5e);
        }

        fpgaDestroyToken(&accel_tokens[i]);
    }
    *num_handles = num_found;
    if (0 != num_found) r = FPGA_OK;

  out_destroy:
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
    static const uint32_t max_handles = 32;
    fpga_handle accel_handles[max_handles];
    uint32_t num_handles = max_handles;
    volatile char *buf;
    uint64_t wsid;
    uint64_t buf_pa;
    bool is_ase_sim = false;
    fpga_result r;

    // Find and connect to the accelerators
    r = connect_to_matching_accels(AFU_ACCEL_UUID, &num_handles, accel_handles,
                                   &is_ase_sim);
    if ((r != FPGA_OK) || (0 == num_handles))
        exit(1);

    if (is_ase_sim)
    {
        printf("   *** ASE only detects a single AFU (port 0) ***\n");
    }

    printf("Found %d instance(s) of hello_world:\n\n", num_handles);

    for (uint32_t i = 0; i < num_handles; i += 1)
    {
        // Allocate a single page memory buffer
        buf = (volatile char*)alloc_buffer(accel_handles[i], getpagesize(),
                                           &wsid, &buf_pa);
        assert(NULL != buf);

        // Set the low byte of the shared buffer to 0.  The FPGA will write
        // a non-zero value to it.
        buf[0] = 0;

        // Tell the accelerator the address of the buffer using cache line
        // addresses.  The accelerator will respond by writing to the buffer.
        fpgaWriteMMIO64(accel_handles[i], 0, 0, buf_pa / CL(1));

        // Spin, waiting for the value in memory to change to something non-zero.
        while (0 == buf[0])
        {
            // A well-behaved program would use _mm_pause(), nanosleep() or
            // equivalent to save power here.
        };

        // Print the string written by the FPGA
        printf("%d: %s\n", i, buf);

        // Done
        fpgaReleaseBuffer(accel_handles[i], wsid);
        fpgaClose(accel_handles[i]);
    }

    return 0;
}
