#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: cache_bench binary exists in the current directory

# This is the code for some of the experiments from https://docs.google.com/document/d/1YdAoWgl0sMWkkDY10JoHxgcOA48sm4WhxY3Nrl0Yz1M/edit?usp=sharing

# Experiment 2
N_PROC=$(grep -c processor /proc/cpuinfo)
N_THREADS=(1 2 4 8 16 24 32 40 48 56 64 72 80)
RESIDENT_RATIO=(2.097152 1048576 4194304)
CACHE_SIZE=34359738368
OPS_PER_THREAD=10000000
VALUE_BYTES=8192
NUM_SHARD_BITS=6

make -j$N_PROC cache_bench

for r in ${RESIDENT_RATIO[@]}
do
    for t in ${N_THREADS[@]}
    do
        echo -e "============================"
        echo -e "-resident_ratio=$r"
        echo -e "-threads=$t"
        ./cache_bench -num_shard_bits=$NUM_SHARD_BITS -skewed=true \
            -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
            -populate_cache=false -cache_size=$CACHE_SIZE -ops_per_thread=$OPS_PER_THREAD -value_bytes=$VALUE_BYTES -resident_ratio=$r -threads=$t
    done
done

# Experiment 3
CACHE_SIZE=1073741824
RESIDENT_RATIO=0.1
N_THREADS=16
OPS_PER_THREAD=10000000
SKEW=(1 2 4 8 16 32 64 128 256 512 1024)
NUM_SHARD_BITS=6

for s in ${SKEW[@]}
do
    echo -e "============================"
    echo -e "-skew=$s"
    ./cache_bench -num_shard_bits=$NUM_SHARD_BITS -skew=$s \
                -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
                -populate_cache=false -cache_size=$CACHE_SIZE -ops_per_thread=$OPS_PER_THREAD -value_bytes=$VALUE_BYTES -resident_ratio=$RESIDENT_RATIO -threads=$N_THREADS
done
