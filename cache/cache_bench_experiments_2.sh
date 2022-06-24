#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: cache_bench binary exists in the current directory

DEBUG_LEVEL=0 make -j24 cache_bench

capacity() {
    echo $(($CACHE_SIZE/$BLOCK_SIZE))
}

log() {
    echo $(echo "l($1)/l(2)" | bc -l)
}

num_shards_small() {
    CAP=$(capacity)
    LOG=$(log $CAP)
    printf %.0f $(echo "$CAP/$LOG" | bc -l)
}

num_shards_opt() {
    CAP=$(capacity)
    LOG=$(log $cap)
    printf %.0f $(echo "$CAP/($LOG * $LOG)" | bc -l)
}

CACHE_SIZE_LIST=(1073741824 8589934592 34359738368) # 1GB, 8GB, 32GB
BLOCK_SIZE_LIST=(8192 2097152) # 8kB, 2MB
NUM_THREADS=16
OPS_PER_THREAD=10000000
CACHE_TYPE_LIST=(fast_lru_cache lru_cache)

for CACHE_TYPE in ${CACHE_TYPE_LIST[@]}
do
    for CACHE_SIZE in ${CACHE_SIZE_LIST[@]}
    do
        for BLOCK_SIZE in ${BLOCK_SIZE_LIST[@]}
        do
            #NUM_SHARDS_LIST=(64 $(num_shards_small) $(num_shards_opt))
            NUM_SHARDS_LIST=(64)
            for NUM_SHARDS in ${NUM_SHARDS_LIST[@]}
            do
                NUM_SHARDS_BITS=$(printf %.0f $(log $NUM_SHARDS))
                CAP=$(capacity)

                # Non-skewed access patterns
                SINGLETON=$CAP
                SMALL_SUPPORT=$((($CAP * 10) / $NUM_SHARDS))
                MEDIUM_SUPPORT=1
                LARGE_SUPPORT=0.01
                RESIDENT_RATIO_LIST=($LARGE_SUPPORT $SINGLETON $SMALL_SUPPORT $MEDIUM_SUPPORT)

                for RESIDENT_RATIO in ${RESIDENT_RATIO_LIST[@]}
                do
                    echo -e "====================================================="
                    echo -e "====================================================="
                    echo -e "\t-cache_type=$CACHE_TYPE"
                    echo -e "\t-cache_size=$CACHE_SIZE"
                    echo -e "\t-value_bytes=$BLOCK_SIZE"
                    echo -e "\t-num_shard_bits=$NUM_SHARDS_BITS"
                    echo -e "\t-resident_ratio=$RESIDENT_RATIO"
                    echo -e "\t-threads=$NUM_THREADS"
                    echo -e "\t-ops_per_thread=$OPS_PER_THREAD"
                    echo -e "\t-lookup_insert_percent=100"
                    echo -e "\t-populate_cache=true"
                    echo -e "\t-skewed=true (not skewed)"
                    ./cache_bench -cache_type=$CACHE_TYPE -num_shard_bits=$NUM_SHARDS_BITS -skewed=true \
                        -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
                        -populate_cache=true -cache_size=$CACHE_SIZE -ops_per_thread=$OPS_PER_THREAD \
                        -value_bytes=$BLOCK_SIZE -resident_ratio=$RESIDENT_RATIO -threads=$NUM_THREADS
                done

                # Skewed access pattern
                RESIDENT_RATIO=0.1
                SKEW=512
                echo -e "====================================================="
                echo -e "====================================================="
                echo -e "\t-cache_type=$CACHE_TYPE"
                echo -e "\t-cache_size=$CACHE_SIZE"
                echo -e "\t-value_bytes=$BLOCK_SIZE"
                echo -e "\t-num_shard_bits=$NUM_SHARDS_BITS"
                echo -e "\t-resident_ratio=$RESIDENT_RATIO"
                echo -e "\t-threads=$NUM_THREADS"
                echo -e "\t-ops_per_thread=$OPS_PER_THREAD"
                echo -e "\t-lookup_insert_percent=100"
                echo -e "\t-populate_cache=true"
                echo -e "\t-skew=$SKEW"
                ./cache_bench -cache_type=$CACHE_TYPE -num_shard_bits=$NUM_SHARDS_BITS -skew=$SKEW \
                        -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
                        -populate_cache=true -cache_size=$CACHE_SIZE -ops_per_thread=$OPS_PER_THREAD \
                        -value_bytes=$BLOCK_SIZE -resident_ratio=$RESIDENT_RATIO -threads=$NUM_THREADS
            done
        done
    done
done
