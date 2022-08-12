#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: cache_bench binary exists in the current directory

cache_capacity() {
    echo $(($CACHE_SIZE/$BLOCK_SIZE))
}

log2() {
    X=$1
    echo $(echo "l($X)/l(2)" | bc -l)
}

print_sep() {
    SEP=$1
    S=$(printf "%-$(tput cols)s $SEP")
    echo "${S// /$SEP}"
}

COMPILE=n
RUNS=1

BLOCK_SIZE=8192
OPS_PER_THREAD=20000000 #10000000

NUM_SHARDS_LIST=(64)
NUM_THREADS_LIST=(16)
CACHE_SIZE_LIST=(1073741824) #(1073741824 8589934592 34359738368) # 1GB, 8GB, 32GB
CACHE_TYPE_LIST=(lru_cache clock_cache) #(clock_cache lru_cache)

if [ "$COMPILE" == "y" ]
then
    DEBUG_LEVEL=0 make checkout_folly
    DEBUG_LEVEL=0 USE_FOLLY=1 ROCKSDB_NO_FBCODE=1 make -j24 cache_bench
fi

for j in `seq 1 $RUNS`
do
    print_sep \#
    echo -e "Run #$j"
    for NUM_SHARDS in ${NUM_SHARDS_LIST[@]}
    do
        for NUM_THREADS in ${NUM_THREADS_LIST[@]}
        do
            for CACHE_SIZE in ${CACHE_SIZE_LIST[@]}
            do
                for CACHE_TYPE in ${CACHE_TYPE_LIST[@]}
                do
                    NUM_SHARDS_BITS=$(printf %.0f $(log2 $NUM_SHARDS))
                    CACHE_CAP=$(cache_capacity)

                    SINGLETON=$CACHE_CAP                                    # 1 element
                    VERY_SMALL_SUPPORT=$(($CACHE_CAP / $NUM_SHARDS))        # 1 element per shard
                    SMALL_SUPPORT=10                                        # 10% of the cache
                    MEDIUM_SUPPORT=1                                        # 100% of the cache
                    MEDIUM_2_SUPPORT=0.89                                   # 1.125x the cache
                    MEDIUM_3_SUPPORT=0.8                                    # 1.25x the cache
                    MEDIUM_4_SUPPORT=0.67                                   # 1.5x the cache
                    MEDIUM_5_SUPPORT=0.5                                    # 2x the cache
                    LARGE_SUPPORT=0.1                                       # 10x the cache
                    VERY_LARGE_SUPPORT=0.01                                 # 100x the cache
                    HUGE_SUPPORT=0.001                                      # 1000x the cache
                    RESIDENT_RATIO_LIST=($MEDIUM_SUPPORT) #($SINGLETON $VERY_SMALL_SUPPORT $SMALL_SUPPORT $QUARTER_SUPPORT $THREE_QUARTERS_SUPPORT $HALF_SUPPORT $MEDIUM_SUPPORT $LARGE_SUPPORT $VERY_LARGE_SUPPORT $HUGE_SUPPORT)
                    SKEWED=false

                    echo -e "Random reads & insert negative lookups"
                    for i in `seq 0 $((${#RESIDENT_RATIO_LIST[@]}-1))`
                    do
                        print_sep =
                        RESIDENT_RATIO=${RESIDENT_RATIO_LIST[$i]}
                        SKEW=${SKEW_LIST[$i]}
                        echo -e "\tCache type: $CACHE_TYPE"
                        echo -e "\tCache size: $CACHE_SIZE"
                        echo -e "\tBlock size: $BLOCK_SIZE"
                        echo -e "\tNum shards: $NUM_SHARDS"
                        echo -e "\tResident ratio: $RESIDENT_RATIO"
                        echo -e "\tThreads: $NUM_THREADS"
                        echo -e "\tOps per thread: $OPS_PER_THREAD"
                        echo -e "\tPopulate cache: true"
                        echo -e "\tLookup insert percent: 100"
                        echo -e "\tInsert percent: 0"
                        ./cache_bench -lean -cache_type=$CACHE_TYPE -num_shard_bits=$NUM_SHARDS_BITS \
                            -skew=0 -skewed=$SKEWED \
                            -lookup_insert_percent=100 -lookup_percent=0 -insert_percent=0 -erase_percent=0 \
                            -populate_cache=true -cache_size=$CACHE_SIZE -ops_per_thread=$OPS_PER_THREAD \
                            -value_bytes=$BLOCK_SIZE -resident_ratio=$RESIDENT_RATIO -threads=$NUM_THREADS
                    done
                done
            done
        done
    done
done
