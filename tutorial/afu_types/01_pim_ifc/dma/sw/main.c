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
#include <stdbool.h>
#include <math.h>
#include <ctype.h>

#include <opae/fpga.h>

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "dma.h"


static uint32_t transfer_size = 8192;
static bool verbose = false;

//
// Print help
//
static void help(void) {
  printf("\n"
         "Usage:\n"
         "    dma [-h] [--transfer-size=<num bytes>]\n"
         "             [--verbose]\n"
         "                     \n"
         "\n"
         "      -h,--help                   Print this help\n"
         "\n"
         "      -s,--transfer-size          Size, in bytes, of data to move "
         "with each dma.\n"
         "                                  transfer. (Default: 8KB)\n"
         "      -v,--verbose                Verbose.  Shows debug messages and "
         "prints out source \n"
         "                                  before the transfer and "
         "destination buffer after\n"
         "                                  the transfer\n"
         "                                  overhead decreases as this value "
         "increases, since\n"
         "                                  multiple completions are signaled "
         "with a single\n"
         "                                  operation.\n"
         "\n");
}

//
// Helper function for setting transfer size
//
double evaluate_expression(const char *expr) {
  if (expr[0] == '0' && (expr[1] == 'x' || expr[1] == 'X')) {
    return strtod(expr, NULL);
  }

  char *endptr;
  double result = strtod(expr, &endptr);

  if (*endptr == '\0') {
    return result;
  } else {
    char op = *endptr++;
    double operand2 = strtod(endptr, &endptr);

    if (*endptr != '\0') {
      return -1;
    }

    switch (op) {
      case '+':
        return result + operand2;
      case '-':
        return result - operand2;
      case '*':
        return result * operand2;
      case '/':
        if (operand2 == 0) {
          return -1;
        }
        return result / operand2;
      case '^':
        return pow(result, operand2);
      default:
        return -1;
    }
  }
}


//
// Parse command line arguments
//
#define GETOPT_STRING ":hs:v"
static int
parse_args(int argc, char *argv[])
{
  struct option longopts[] = {{"help", no_argument, NULL, 'h'},
                              {"transfer-size", required_argument, NULL, 's'},
                              {"verbose", no_argument, NULL, 'v'},
                              {0, 0, 0, 0}};

  int getopt_ret;
  int option_index;
  char *endptr = NULL;

  while (-1 != (getopt_ret = getopt_long(argc, argv, GETOPT_STRING, longopts,
                                         &option_index))) {
    const char *tmp_optarg = optarg;

    if ((optarg) && ('=' == *tmp_optarg)) {
      ++tmp_optarg;
    }

    switch (getopt_ret) {
    case 'h': /* help */
      help();
      return -1;

    case 's': /* transfer-size */
      transfer_size = (uint32_t)evaluate_expression(tmp_optarg);
      if (transfer_size < 0) {
        fprintf(stderr, "Invalid expression in --transfer-size\n");
        return -1;
      }
      break;

    case 'v': /* verbose (debug) */
      verbose = true;
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

  if (num_matches < 1) {
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


int main(int argc, char *argv[]) {
  fpga_result r;
  fpga_handle accel_handle;
  bool is_ase_sim;

  if (parse_args(argc, argv) < 0)
    return 1;

  // Find and connect to the accelerator(s)
  accel_handle = connect_to_accel(AFU_ACCEL_UUID, &is_ase_sim);
  if (NULL == accel_handle)
    return 0;

  if (is_ase_sim) {
    printf("Running in ASE mode\n");
  }

  // Run tests
  int status = 0;
  status = dma(accel_handle, is_ase_sim, transfer_size, verbose);

  // Done
  fpgaClose(accel_handle);

  return status;
}
