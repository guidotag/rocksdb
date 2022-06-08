#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: cache_bench binary exists in the current directory

make -j$N_PROC cache_bench

capacity() {
    echo $(($cache_size/$block_size))
}

log() {
    echo $(echo "l($1)/l(2)" | bc -l)
}

n_shards_small() {
    cap=$(capacity)
    l=$(log $cap)
    printf %.0f $(echo "$cap/$l" | bc -l)
}

n_shards_opt() {
    cap=$(capacity)
    l=$(log $cap)
    printf %.0f $(echo "$cap/($l * $l)" | bc -l)
}

CACHE_SIZE=(8388608 1073741824 34359738368) # 8MB, 1GB, 32GB
BLOCK_SIZE=(8192 2147483648) # 8kB, 2MB
N_THREADS=16
OPS_PER_THREAD=10000000

for cache_size in ${CACHE_SIZE[@]}
do
    for block_size in ${BLOCK_SIZE[@]}
    do
        N_SHARDS=(64 $(n_shards_small) $(n_shards_opt))
        for n_shards in ${N_SHARDS[@]}
        do
            num_shard_bits=$(printf %.0f $(log $n_shards))
            cap=$(capacity)

            # Non-skewed access patterns
            singleton=$cap
            small_support=$((($cap * 10) / $n_shards))
            medium_support=1
            large_support=0.01
            RESIDENT_RATIO=($singleton $small_support $medium_support $large_support)
            for resident_ratio in ${RESIDENT_RATIO[@]}
            do
                #-skewed=true means it is not skewed
                ./cache_bench -num_shard_bits=$num_shard_bits -skewed=true \
                    -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
                    -populate_cache=true -cache_size=$cache_size -ops_per_thread=$OPS_PER_THREAD \
                    -value_bytes=$block_size -resident_ratio=$resident_ratio -threads=$N_THREADS
            done

            # Skewed access pattern
            RESIDENT_RATIO=0.1
            SKEW=512
            ./cache_bench -num_shard_bits=$num_shard_bits -skew=$SKEW \
                    -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
                    -populate_cache=true -cache_size=$cache_size -ops_per_thread=$OPS_PER_THREAD \
                    -value_bytes=$value_bytes -resident_ratio=$RESIDENT_RATIO -threads=$N_THREADS
        done
    done
done
