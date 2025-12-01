CXX ?= g++
NVCC ?= nvcc
CXXFLAGS ?= -std=c++17 -O2 -Iinclude -Isrc -Wall -Wextra
NVCCFLAGS ?= -std=c++17 -O2 -Iinclude -Isrc

# Sequential target
SEQ_SRCS = src/aabb_io.cpp src/seq_bruteforce.cpp src/seq_spatial_hashing.cpp src/seq_sort_and_sweep.cpp src/seq.cpp
SEQ_TARGET = bin/seq

# CUDA target
CUDA_CU_SRCS = src/cuda_sort_and_sweep.cu src/cuda_spatial_hashing.cu
CUDA_CPP_SRCS = src/aabb_io.cpp src/cuda.cpp
CUDA_TARGET = bin/cuda

all: $(SEQ_TARGET) $(CUDA_TARGET)

seq: $(SEQ_TARGET)

cuda: $(CUDA_TARGET)

$(SEQ_TARGET): $(SEQ_SRCS) | bin
	$(CXX) $(CXXFLAGS) -o $@ $(SEQ_SRCS)

$(CUDA_TARGET): $(CUDA_CU_SRCS) $(CUDA_CPP_SRCS) | bin
	$(NVCC) $(NVCCFLAGS) -o $@ $(CUDA_CU_SRCS) $(CUDA_CPP_SRCS)

bin:
	@mkdir -p $@

clean:
	@rm -f $(SEQ_TARGET) $(CUDA_TARGET)

.PHONY: all seq cuda clean bin
