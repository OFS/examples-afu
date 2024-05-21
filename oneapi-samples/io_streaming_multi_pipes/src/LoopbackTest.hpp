// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __LOOPBACKTEST_HPP__
#define __LOOPBACKTEST_HPP__

#include <sycl/ext/intel/fpga_extensions.hpp>
#include <sycl/sycl.hpp>

#include "FakeIOPipes.hpp"

// If the 'USE_REAL_IO_PIPE' macro is defined, this test will use real IO pipes.
// To use this, ensure you have a BSP that supports IO pipes.
// NOTE: define this BEFORE including the LoopbackTest.hpp and
// SideChannelTest.hpp which will check for the presence of this macro.
#define USE_REAL_IO_PIPES
#define OUTER_LOOP_COUNT 1
#define INNER_LOOP_COUNT 128
#define PIPE_COUNT 4

using namespace sycl;

// declare the kernel and pipe ID stucts globally to reduce name mangling
struct LoopBackMainKernel;
// struct LoopBackReadIOPipeID { static constexpr unsigned id = 0; };
struct LoopBackReadIOPipeID_1 {
  static constexpr unsigned id = 1;
};
struct LoopBackReadIOPipeID_2 {
  static constexpr unsigned id = 3;
};
struct LoopBackReadIOPipeID_3 {
  static constexpr unsigned id = 5;
};
struct LoopBackReadIOPipeID_4 {
  static constexpr unsigned id = 7;
};

// struct LoopBackWriteIOPipeID_0 { static constexpr unsigned id = 5; };
struct LoopBackWriteIOPipeID_1 {
  static constexpr unsigned id = 0;
};
struct LoopBackWriteIOPipeID_2 {
  static constexpr unsigned id = 2;
};
struct LoopBackWriteIOPipeID_3 {
  static constexpr unsigned id = 4;
};
struct LoopBackWriteIOPipeID_4 {
  static constexpr unsigned id = 6;
};

//
// The simplest processing kernel. Streams data in 'IOPipeIn' and streams
// it out 'IOPipeOut'. The developer of this kernel uses this abstraction
// to create a streaming kernel. They don't particularly care whether the IO
// pipes are 'real' or not, that is up to the system designer who works on
// stitching together the whole system. In this tutorial, the stitching of the
// full system is done below in the 'RunLoopbackSystem' function.
//
template <class IOPipeIn_1, class IOPipeIn_2, class IOPipeIn_3,
          class IOPipeIn_4, class IOPipeOut_1, class IOPipeOut_2,
          class IOPipeOut_3, class IOPipeOut_4>
event SubmitLoopbackKernel(queue &q, size_t count, bool &passed) {
  std::cout << "inside SubmitLoopbackKernel \n";
  unsigned long int *datain_host =
      (unsigned long int *)malloc(PIPE_COUNT * OUTER_LOOP_COUNT *
                                  INNER_LOOP_COUNT * sizeof(unsigned long int));

  for (int pipe_count = 0; pipe_count < PIPE_COUNT; pipe_count++) {
    for (size_t count = 0; count < (OUTER_LOOP_COUNT * INNER_LOOP_COUNT);
         count++) {
      datain_host[pipe_count * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + count] =
          count;
    }
  }
  unsigned long int *dataout_host =
      (unsigned long int *)malloc(PIPE_COUNT * OUTER_LOOP_COUNT *
                                  INNER_LOOP_COUNT * sizeof(unsigned long int));

  buffer<unsigned long int, 1> buf_in(
      datain_host, range<1>(PIPE_COUNT * OUTER_LOOP_COUNT * INNER_LOOP_COUNT));
  buffer<unsigned long int, 1> buf_out(
      dataout_host, range<1>(PIPE_COUNT * OUTER_LOOP_COUNT * INNER_LOOP_COUNT));

  event kevent = q.submit([&](handler &h) {
    auto in = buf_in.get_access<access::mode::read_write>(h);
    auto out = buf_out.get_access<access::mode::read_write>(h);

    h.single_task<LoopBackMainKernel>([=] {
      for (size_t inner_loop_count = 0; inner_loop_count < INNER_LOOP_COUNT;
           inner_loop_count++) {
        IOPipeOut_1::write(
            in[0 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count]);
        IOPipeOut_2::write(
            in[1 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count]);
        IOPipeOut_3::write(
            in[2 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count]);
        IOPipeOut_4::write(
            in[3 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count]);
      }
      for (size_t inner_loop_count = 0; inner_loop_count < INNER_LOOP_COUNT;
           inner_loop_count++) {
        out[0 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count] =
            IOPipeIn_1::read();
        out[1 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count] =
            IOPipeIn_2::read();
        out[2 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count] =
            IOPipeIn_3::read();
        out[3 * OUTER_LOOP_COUNT * INNER_LOOP_COUNT + inner_loop_count] =
            IOPipeIn_4::read();
      }
    });
  });

  buf_out.get_access<access::mode::read>();

  for (size_t i = 0; i < (PIPE_COUNT * OUTER_LOOP_COUNT * INNER_LOOP_COUNT);
       i++) {
    if (dataout_host[i] != datain_host[i]) {
      std::cerr << "ERROR: output mismatch in dataout_host at entry " << i
                << ": " << dataout_host[i] << " != " << datain_host[i]
                << " (out != in)\n";
      passed &= false;
    }
  }

  std::cout << "passed = " << passed << "\n";

  return kevent;
}

//
// Run the loopback system
//
template <typename T, bool use_usm_host_alloc>
bool RunLoopbackSystem(queue &q, size_t count) {
  bool passed = true;

  //////////////////////////////////////////////////////////////////////////////
  // IO pipes
  constexpr size_t kIOPipeDepth = 4;
#ifndef USE_REAL_IO_PIPES
  // these are FAKE IO pipes (and their producer/consumer)
  using FakeIOPipeInProducer =
      Producer<LoopBackReadIOPipeID, T, use_usm_host_alloc, kIOPipeDepth>;
  using FakeIOPipeOutConsumer =
      Consumer<LoopBackWriteIOPipeID, T, use_usm_host_alloc, kIOPipeDepth>;
  using ReadIOPipe = typename FakeIOPipeInProducer::Pipe;
  using WriteIOPipe = typename FakeIOPipeOutConsumer::Pipe;

  // initialize the fake IO pipes
  FakeIOPipeInProducer::Init(q, count);
  FakeIOPipeOutConsumer::Init(q, count);
#else
  // these are REAL IO pipes
  using ReadIOPipe_1 =
      ext::intel::kernel_readable_io_pipe<LoopBackReadIOPipeID_1, T,
                                          kIOPipeDepth>;
  using ReadIOPipe_2 =
      ext::intel::kernel_readable_io_pipe<LoopBackReadIOPipeID_2, T,
                                          kIOPipeDepth>;
  using ReadIOPipe_3 =
      ext::intel::kernel_readable_io_pipe<LoopBackReadIOPipeID_3, T,
                                          kIOPipeDepth>;
  using ReadIOPipe_4 =
      ext::intel::kernel_readable_io_pipe<LoopBackReadIOPipeID_4, T,
                                          kIOPipeDepth>;

  using WriteIOPipe_1 =
      ext::intel::kernel_writeable_io_pipe<LoopBackWriteIOPipeID_1, T,
                                           kIOPipeDepth>;
  using WriteIOPipe_2 =
      ext::intel::kernel_writeable_io_pipe<LoopBackWriteIOPipeID_2, T,
                                           kIOPipeDepth>;
  using WriteIOPipe_3 =
      ext::intel::kernel_writeable_io_pipe<LoopBackWriteIOPipeID_3, T,
                                           kIOPipeDepth>;
  using WriteIOPipe_4 =
      ext::intel::kernel_writeable_io_pipe<LoopBackWriteIOPipeID_4, T,
                                           kIOPipeDepth>;
#endif
  //////////////////////////////////////////////////////////////////////////////

  // FAKE IO PIPES ONLY
#ifndef USE_REAL_IO_PIPES
  // get the pointer to the fake input data
  auto i_stream_data = FakeIOPipeInProducer::Data();

  // create some random input data for the fake IO pipe
  std::generate_n(i_stream_data, count, [&] { return rand() % 100; });
#endif

  // submit the main processing kernel
  std::cout << "before SubmitLoopbackKernel \n";
  auto kernel_event =
      SubmitLoopbackKernel<ReadIOPipe_1, ReadIOPipe_2, ReadIOPipe_3,
                           ReadIOPipe_4, WriteIOPipe_1, WriteIOPipe_2,
                           WriteIOPipe_3, WriteIOPipe_4>(q, count, passed);
  std::cout << "after SubmitLoopbackKernel \n";

  // FAKE IO PIPES ONLY
#ifndef USE_REAL_IO_PIPES
  // start the producer and consumer
  event produce_dma_e, produce_kernel_e;
  event consume_dma_e, consume_kernel_e;
  std::tie(produce_dma_e, produce_kernel_e) = FakeIOPipeInProducer::Start(q);
  std::tie(consume_dma_e, consume_kernel_e) = FakeIOPipeOutConsumer::Start(q);

  // wait for producer and consumer to finish including the DMA events.
  // NOTE: if USM host allocations are used, the dma events are noops.
  produce_dma_e.wait();
  produce_kernel_e.wait();
  consume_dma_e.wait();
  consume_kernel_e.wait();
#endif

  // Wait for main kernel to finish.
  // NOTE: we can only wait on the loopback kernel because it knows how much
  // data it expects to process ('count'). In general, this may not be the
  // case and you may want the processing kernel to run 'forever' (or until the
  // host tells it to stop). For an example of this, see 'SideChannelTest.hpp'.

  kernel_event.wait();

  // FAKE IO PIPES ONLY
#ifndef USE_REAL_IO_PIPES
  // get the pointer to the fake input data
  auto o_stream_data = FakeIOPipeOutConsumer::Data();

  // validate the output
  for (size_t i = 0; i < count; i++) {
    if (o_stream_data[i] != i_stream_data[i]) {
      std::cerr << "ERROR: output mismatch at entry " << i << ": "
                << o_stream_data[i] << " != " << i_stream_data[i]
                << " (out != in)\n";
      passed &= false;
    }
  }
#endif

  std::cout << " exit loopback function";
  return passed;
}

#endif /* __LOOPBACKTEST_HPP__ */
