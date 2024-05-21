# `Multi Pipe IO Streaming with SYCL IO Pipes` Sample

This sample is forked from oneapi-sample open source repo. Link to the code sample [here](https://github.com/oneapi-src/oneAPI-samples/tree/master/DirectProgramming/C%2B%2BSYCL_FPGA/Tutorials/DesignPatterns/io_streaming). You can refer README in link mentioned to understand more about IO Strreaming and for build steps.

## Pre-requisites
Building and running this sample requires setup described in Perquisites section in oneAPI Accelerator Support Package (ASP): Getting Started User Guide under oneAPI tab [here](https://ofs.github.io/ofs-2023.1/hw/common/user_guides/oneapi_asp/ug_oneapi_asp/).

## Purpose
The purpose of this code sample is to help users quickly build 4 pipes/channels IO Streaming sample with OneAPI-ASP and test it out.
For more information about OneAPI-ASP, please refer OneAPI-ASP repo [here](https://github.com/OFS/oneapi-asp)
For more information about IO Streaming/Pipes refer [here](https://github.com/oneapi-src/oneAPI-samples/tree/master/DirectProgramming/C%2B%2BSYCL_FPGA/Tutorials/DesignPatterns/io_streaming)

## Key Implementation Details
In this design we transfer data from host DDR to fpga DDR. Then we send that data over IO Pipes to HSSI SubSystem and loop it back over cable in lab. IO Pipes are implemented in ASP. This example demonstrates use of multi pipes, in this case we use 4 pipes. We loop data back to FPGA DDR and subsequently transfer in back to host DDR for verification.

## Build Steps
Build steps are largely same as build steps for other oneapi-samples (you need to update board_spec.xml file with number of pipes/channels you want , 4 in this case). You need to build ASP and use it to compile io pipes. One needs to use ofs_n6001_iopipes, ofs_n6001_usm_iopipes hardware variants. 

Once you have built ASP and set appropriate environment variables you can run below steps to compile io pipes samples
  - mkdir ofs_n6001_usm_iopipes or mkdir ofs_n6001_iopipes
  - cd ofs_n6001_usm_iopipes or cd ofs_n6001_iopipes
  - cmake .. -DFPGA_DEVICE=< path-to-asp >:< board-variant >
  - make fpga

Before running the executable users need to set follwing env variables
- export LOCAL_IP_ADDRESS = local ip address
- export LOCAL_MAC_ADDRESS = local mac address 
- export LOCAL_NETMASK = netmask
- export LOCAL_UDP_PORT = local udp port 
- export REMOTE_IP_ADDRESS = remote ip address , destination ip address
- export REMOTE_MAC_ADDRESS= remote mac address , destination mac address
- export REMOTE_UDP_PORT= remote udp port
