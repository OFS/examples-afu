# `One Pipe IO Streaming with SYCL IO Pipes` Sample

This sample is forked from oneapi-sample open source repo. Link to the code sample - https://github.com/oneapi-src/oneAPI-samples/tree/master/DirectProgramming/C%2B%2BSYCL_FPGA/Tutorials/DesignPatterns/io_streaming. You can refer README in link mentioned to understand more about IO Strreaming and for build steps.

## Purpose

The purpose of this code sample is to help users quickly build IO Streaming sample with one pipe/channel and test it out.

## Key Implementation Details
In this design we transfer data from host DDR to fpga DDR. Then we send that data over IO Pipes to HSSI SubSystem and loop it back over cable in lab. IO Pipes are implemented in ASP. This example demonstrates use of one pipe. We loop data back to FPGA DDR and subsequently transfer in back to host DDR for verification.