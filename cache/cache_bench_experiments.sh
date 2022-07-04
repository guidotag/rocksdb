#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: cache_bench binary exists in the current directory

capacity() {
    echo $(($CACHE_SIZE/$BLOCK_SIZE))
}

log2() {
    echo $(echo "l($1)/l(2)" | bc -l)
}

# x/log2(x), where x is the cache capacity
f1() {
    CAP=$(capacity)
    LOG=$(log2 $CAP)
    printf %.0f $(echo "$CAP/$LOG" | bc -l)
}

# x/(log2(x))^2, where x is the cache capacity
f2() {
    CAP=$(capacity)
    LOG=$(log2 $cap)
    printf %.0f $(echo "$CAP/($LOG * $LOG)" | bc -l)
}

print_sep() {
    SEP=$1
    S=$(printf "%-$(tput cols)s $SEP")
    echo "${S// /$SEP}"
}

COMPILE=n
LOOKUP_BENCHMARKS=y
INSERT_BENCHMARKS=n
RUNS=10

CACHE_SIZE_LIST=(1073741824) #(1073741824 8589934592 34359738368) # 1GB, 8GB, 32GB
BLOCK_SIZE_LIST=(8192) #(8192 2097152) # 8kB, 2MB
NUM_THREADS=16
OPS_PER_THREAD=10000000
CACHE_TYPE_LIST=(lru_cache) #(lru_cache fast_lru_cache clock_cache)

if [ "$COMPILE" == "y" ]
then
    DEBUG_LEVEL=0 make checkout_folly
    DEBUG_LEVEL=0 USE_FOLLY=1 ROCKSDB_NO_FBCODE=1 make -j24 cache_bench
fi

for j in `seq 1 $RUNS`
do
    print_sep /
    echo -e "Run #$j"
    for CACHE_TYPE in ${CACHE_TYPE_LIST[@]}
    do
        for CACHE_SIZE in ${CACHE_SIZE_LIST[@]}
        do
            for BLOCK_SIZE in ${BLOCK_SIZE_LIST[@]}
            do
                NUM_SHARDS_LIST=(64)
                for NUM_SHARDS in ${NUM_SHARDS_LIST[@]}
                do
                    NUM_SHARDS_BITS=$(printf %.0f $(log2 $NUM_SHARDS))
                    CAP=$(capacity)

                    SINGLETON=$CAP                                  # 1 element
                    VERY_SMALL_SUPPORT=$(($CAP / $NUM_SHARDS))      # 1 element per shard
                    SMALL_SUPPORT=10                                # 10% of the cache
                    MEDIUM_SUPPORT=1                                # 100% of the cache
                    LARGE_SUPPORT=0.1                               # 10x the cache
                    VERY_LARGE_SUPPORT=0.01                         # 100x the cache
                    HUGE_SUPPORT=0.001                              # 1000x the cache
                    RESIDENT_RATIO_LIST=($SINGLETON $VERY_SMALL_SUPPORT $SMALL_SUPPORT $MEDIUM_SUPPORT $LARGE_SUPPORT $VERY_LARGE_SUPPORT $HUGE_SUPPORT)
                    SKEW_LIST=(0 0 0 0 0 0 0)

                    if [ "$LOOKUP_BENCHMARKS" == "y" ]
                    then
                        echo -e "Random reads & insert negative lookups"
                        for i in `seq 0 $((${#RESIDENT_RATIO_LIST[@]}-1))`
                        do
                            print_sep =
                            RESIDENT_RATIO=${RESIDENT_RATIO_LIST[$i]}
                            SKEW=${SKEW_LIST[$i]}
                            echo -e "\t-cache_type=$CACHE_TYPE"
                            echo -e "\t-cache_size=$CACHE_SIZE"
                            echo -e "\t-value_bytes=$BLOCK_SIZE"
                            echo -e "\t-num_shard_bits=$NUM_SHARDS_BITS"
                            echo -e "\t-resident_ratio=$RESIDENT_RATIO"
                            echo -e "\t-threads=$NUM_THREADS"
                            echo -e "\t-ops_per_thread=$OPS_PER_THREAD"
                            echo -e "\t-populate_cache=true"
                            echo -e "\t-skew=$SKEW"
                            echo -e "\t-lookup_insert_percent=100"
                            echo -e "\t-insert_percent=0"
                            ./cache_bench -cache_type=$CACHE_TYPE -num_shard_bits=$NUM_SHARDS_BITS -skew=$SKEW \
                                -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
                                -populate_cache=true -cache_size=$CACHE_SIZE -ops_per_thread=$OPS_PER_THREAD \
                                -value_bytes=$BLOCK_SIZE -resident_ratio=$RESIDENT_RATIO -threads=$NUM_THREADS
                        done
                    fi

                    if [ "$INSERT_BENCHMARKS" == "y" ]
                    then
                        echo -e "Random writes"
                        for i in `seq 0 $((${#RESIDENT_RATIO_LIST[@]}-1))`
                        do
                            print_sep =
                            RESIDENT_RATIO=${RESIDENT_RATIO_LIST[$i]}
                            SKEW=${SKEW_LIST[$i]}
                            echo -e "\t-cache_type=$CACHE_TYPE"
                            echo -e "\t-cache_size=$CACHE_SIZE"
                            echo -e "\t-value_bytes=$BLOCK_SIZE"
                            echo -e "\t-num_shard_bits=$NUM_SHARDS_BITS"
                            echo -e "\t-resident_ratio=$RESIDENT_RATIO"
                            echo -e "\t-threads=$NUM_THREADS"
                            echo -e "\t-ops_per_thread=$OPS_PER_THREAD"
                            echo -e "\t-populate_cache=true"
                            echo -e "\t-skew=$SKEW"
                            echo -e "\t-lookup_insert_percent=0"
                            echo -e "\t-insert_percent=100"
                            ./cache_bench -cache_type=$CACHE_TYPE -num_shard_bits=$NUM_SHARDS_BITS -skew=$SKEW \
                                -lookup_insert_percent=0 -lookup_percent=0 -insert_percent=100 -erase_percent=0 \
                                -populate_cache=true -cache_size=$CACHE_SIZE -ops_per_thread=$OPS_PER_THREAD \
                                -value_bytes=$BLOCK_SIZE -resident_ratio=$RESIDENT_RATIO -threads=$NUM_THREADS
                        done
                    fi
                done
            done
        done
    done
done
