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

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "dma.h"


static uint32_t chunk_size = 8192;
static uint32_t completion_freq = 32;
static uint32_t max_reqs_in_flight = 0;
static bool use_interrupts = false;


//
// Print help
// TODO Out of date
//
static void
help(void)
{
    printf("\n"
           "Usage:\n"
           "    dma [-h] [--chunk-size=<num bytes>]\n"
           "                     [--completion-freq=<commands per completion>]\n"
           "                     [--interrupts]\n"
           "\n"
           "      -h,--help             Print this help\n"
           "\n"
           "      -c,--chunk-size       Size, in bytes, of data to move with each read\n"
           "                            or write request. (Default: 8KB)\n"
           "      -f,--completion-freq  Number of commands per completion. Synchronization\n"
           "                            overhead decreases as this value increases, since\n"
           "                            multiple completions are signaled with a single\n"
           "                            operation.\n"
           "      -i,--interrupts       Use interrupts to signal completion of a command.\n"
           "                            When not set, completion is signaled by a write\n"
           "                            to host memory.\n"
           "      -m,--max-reqs         Maximum number of commands in flight.\n"
           "\n");
}


//
// Parse command line arguments
//
#define GETOPT_STRING ":hc:f:im:"
static int
parse_args(int argc, char *argv[])
{
    struct option longopts[] = {
        {"help",            no_argument,       NULL, 'h'},
        {"chunk-size",      required_argument, NULL, 'c'},
        {"completion-freq", required_argument, NULL, 'f'},
        {"interrupts",      no_argument,       NULL, 'i'},
        {"max-reqs",        required_argument, NULL, 'm'},
        {0, 0, 0, 0}
    };

    int getopt_ret;
    int option_index;
    char *endptr = NULL;

    while (-1
           != (getopt_ret = getopt_long(argc, argv, GETOPT_STRING, longopts,
                        &option_index))) {
        const char *tmp_optarg = optarg;

        if ((optarg) && ('=' == *tmp_optarg)) {
            ++tmp_optarg;
        }

        switch (getopt_ret) {
        case 'h': /* help */
            help();
            return -1;

        case 'c': /* chunk-size */
            endptr = NULL;
            chunk_size = (uint32_t)strtoul(tmp_optarg, &endptr, 0);
            if ((endptr != tmp_optarg + strlen(tmp_optarg)) || (chunk_size == 0)) {
                fprintf(stderr, "Invalid chunk size: %s\n", tmp_optarg);
                return -1;
            }
            break;

        case 'f': /* completion-freq */
            endptr = NULL;
            completion_freq = (uint32_t)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "Invalid completion frequency: %s\n", tmp_optarg);
                return -1;
            }
            if ((completion_freq & (completion_freq - 1)) != 0) {
                fprintf(stderr, "Completion frequency must be a power of 2: %s\n", tmp_optarg);
                return -1;
            }
            break;

        case 'i': /* interrupts */
            use_interrupts = true;
            break;

        case 'm': /* max-reqs */
            endptr = NULL;
            max_reqs_in_flight = (uint32_t)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "Invalid maximum requests: %s\n", tmp_optarg);
                return -1;
            }
            if ((max_reqs_in_flight & (max_reqs_in_flight - 1)) != 0) {
                fprintf(stderr, "Maximum requests in flight must be a power of 2: %s\n", tmp_optarg);
                return -1;
            }
            break;

        case ':': /* missing option argument */
            fprintf(stderr, "Missing option argument. Use --help.\n");
            return -1;

        case '?':
        default: /* invalid option */
            fprintf(stderr, "Invalid cmdline options. Use --help.\n");
            return -1;
        }
    }

    if (optind != argc) {
        fprintf(stderr, "Unexpected extra arguments\n");
        return -1;
    }

    return 0;
}


//
// Search for an accelerator matching the requested UUID and connect to it.
//
static fpga_handle connect_to_accel(const char *accel_uuid, bool *is_ase_sim)
{
    fpga_properties filter = NULL;
    fpga_guid guid;
    fpga_token accel_token;
    uint32_t num_matches;
    fpga_handle accel_handle;
    fpga_result r;

    // Don't print verbose messages in ASE by default
    setenv("ASE_LOG", "0", 0);
    *is_ase_sim = NULL;

    // Set up a filter that will search for an accelerator
    fpgaGetProperties(NULL, &filter);
    fpgaPropertiesSetObjectType(filter, FPGA_ACCELERATOR);

    // Add the desired UUID to the filter
    uuid_parse(accel_uuid, guid);
    fpgaPropertiesSetGUID(filter, guid);

    // Do the search across the available FPGA contexts
    num_matches = 1;
    fpgaEnumerate(&filter, 1, &accel_token, 1, &num_matches);

    // Not needed anymore
    fpgaDestroyProperties(&filter);

    if (num_matches < 1)
    {
        fprintf(stderr, "Accelerator %s not found!\n", accel_uuid);
        return 0;
    }

    // Open accelerator
    r = fpgaOpen(accel_token, &accel_handle, 0);
    assert(FPGA_OK == r);

    // While the token is available, check whether it is for HW
    // or for ASE simulation.
    fpga_properties accel_props;
    uint16_t vendor_id, dev_id;
    fpgaGetProperties(accel_token, &accel_props);
    fpgaPropertiesGetVendorID(accel_props, &vendor_id);
    fpgaPropertiesGetDeviceID(accel_props, &dev_id);
    *is_ase_sim = (vendor_id == 0x8086) && (dev_id == 0xa5e);

    // Done with token
    fpgaDestroyToken(&accel_token);

    return accel_handle;
}


int main(int argc, char *argv[])
{
    fpga_result r;
    fpga_handle accel_handle;
    bool is_ase_sim;

    if (parse_args(argc, argv) < 0)
        return 1;

    // Find and connect to the accelerator(s)
    accel_handle = connect_to_accel(AFU_ACCEL_UUID, &is_ase_sim);
    if (NULL == accel_handle) return 0;

    if (is_ase_sim)
    {
        printf("Running in ASE mode\n");
    }

    // Run tests
    int status = 0;
    status = dma(accel_handle, is_ase_sim,
                         chunk_size, completion_freq, use_interrupts,
                         max_reqs_in_flight);

    // Done
    fpgaClose(accel_handle);

    return status;
}
