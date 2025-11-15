CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Iinclude -Wall -Wextra

SRCS = src/aabb_io.cpp src/seq.cpp
TARGET = bin/seq

all: $(TARGET)

$(TARGET): $(SRCS) | bin
	$(CXX) $(CXXFLAGS) -o $@ $(SRCS)

bin:
	@mkdir -p $@

clean:
	@rm -f $(TARGET)

.PHONY: all clean bin
