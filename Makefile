CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Iinclude -Isrc -Wall -Wextra

SRCS = src/aabb_io.cpp src/seq_bruteforce.cpp src/seq_spatial_hashing.cpp src/seq_sort_and_sweep.cpp src/seq.cpp
TARGET = bin/seq

all: $(TARGET)

$(TARGET): $(SRCS) | bin
	$(CXX) $(CXXFLAGS) -o $@ $(SRCS)

bin:
	@mkdir -p $@

clean:
	@rm -f $(TARGET)

.PHONY: all clean bin
