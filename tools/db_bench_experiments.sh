#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: db_bench binary exists in the current directory

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

CACHE_SIZE_LIST=(1073741824) #(1073741824 8589934592 34359738368) # 1GB, 8GB, 32GB
BLOCK_SIZE_LIST=(8192) #(8192 2097152) # 8kB, 2MB
DB_DIR=/data/users/tagliavini/db_bench
KEY_SIZE=20
VALUE_SIZE=400
DB_ELEM_COUNT=40000000
#REPORT_FILE_DIR=
BENCHMARK_LIST=(readrandom readwhilewriting)
SEED=1652227743
NUM_THREADS=64
DURATION=60
CACHE_TYPE_LIST=(clock_cache lru_cache)

# TODO Use the following thread counts:
# - Small: 1 thread
# - Medium: Number of cores
# - Large: Number of HW threads (so, 2x number of cores if HT is enabled)
# - XL: 2x Large

if [ "$COMPILE" == "y" ]
then
    DEBUG_LEVEL=0 make checkout_folly
    DEBUG_LEVEL=0 USE_FOLLY=1 ROCKSDB_NO_FBCODE=1 make -j24 db_bench
fi

for CACHE_TYPE in ${CACHE_TYPE_LIST[@]}
do
    for CACHE_SIZE in ${CACHE_SIZE_LIST[@]}
    do
        for BLOCK_SIZE in ${BLOCK_SIZE_LIST[@]}
        do
            NUM_SHARDS_LIST=(64)
            for NUM_SHARDS in ${NUM_SHARDS_LIST[@]}
            do
                NUM_SHARD_BITS=$(printf %.0f $(log2 $NUM_SHARDS))
                CACHE_CAP=$(cache_capacity)

                SINGLETON=1
                VERY_SMALL_SUPPORT=$NUM_SHARDS
                SMALL_SUPPORT=$(($CACHE_CAP / 10))
                MEDIUM_SUPPORT=$(($CACHE_CAP))
                LARGE_SUPPORT=$(($CACHE_CAP * 10))
                VERY_LARGE_SUPPORT=$(($CACHE_CAP * 100))
                SUPPORT_SIZE_LIST=($SINGLETON $VERY_SMALL_SUPPORT $SMALL_SUPPORT $MEDIUM_SUPPORT $LARGE_SUPPORT $VERY_LARGE_SUPPORT)
                for SUPPORT_SIZE in ${SUPPORT_SIZE_LIST[@]}
                do
                    print_sep \#
                    # Populate the database.
                    numactl --interleave=all ./db_bench --benchmarks=fillseq,flush,waitforcompaction,compact0,waitforcompaction,compact1,waitforcompaction \
                        --db=$DB_DIR --use_existing_db=0 \
                        --allow_concurrent_memtable_write=false --level0_file_num_compaction_trigger=4 --level0_slowdown_writes_trigger=20 --level0_stop_writes_trigger=30 \
                        --num=$DB_ELEM_COUNT --key_size=$KEY_SIZE --value_size=$VALUE_SIZE --value_size_distribution_type=fixed `#key-value parameters` \
                        --cache_type=$CACHE_TYPE --block_size=$BLOCK_SIZE --cache_size=$CACHE_SIZE --cache_numshardbits=$NUM_SHARD_BITS `# cache parameters` \
                        --max_write_buffer_number=4 --write_buffer_size=16777216 --target_file_size_base=16777216 --max_bytes_for_level_base=67108864 --max_bytes_for_level_multiplier=8 `#LSM structural parameters` \
                        --compression_type=none --disable_wal=1 `# no compression, no log` \
                        --cache_index_and_filter_blocks=1 --pin_l0_filter_and_index_blocks_in_cache=1 --partition_index_and_filters=1 --cache_high_pri_pool_ratio=0.5 `# index/filter caching` \
                        --statistics=0 --stats_per_interval=0 --stats_interval_seconds=0 --report_interval_seconds=0 --histogram=0 `# stats` \
                        --compaction_style=2 --fifo_compaction_allow_compaction=0 `# FIFO compaction` \
                        --max_background_jobs=16 --threads=1 \
                        --memtablerep=skip_list \
                        --verify_checksum=1 \
                        --bloom_bits=16 \
                        --seed=$SEED

                    for BENCHMARK in ${BENCHMARK_LIST[@]}
                    do
                        print_sep =
                        echo -e "\tCache type: $CACHE_TYPE"
                        echo -e "\tCache size: $CACHE_SIZE"
                        echo -e "\tBlock size: $BLOCK_SIZE"
                        echo -e "\tNum shards: $NUM_SHARDS"
                        echo -e "\tSupport size: $SUPPORT_SIZE"
                        echo -e "\tThreads: $NUM_THREADS"
                        echo -e "\tBenchmark: $BENCHMARK"
                        numactl --interleave=all ./db_bench --benchmarks=$BENCHMARK \
                            --db=$DB_DIR --use_existing_db=1 \
                            --level0_file_num_compaction_trigger=4 --level0_slowdown_writes_trigger=20 --level0_stop_writes_trigger=30 \
                            --num=$SUPPORT_SIZE --key_size=$KEY_SIZE --value_size=$VALUE_SIZE --value_size_distribution_type=fixed `#key-value parameters` \
                            --cache_type=$CACHE_TYPE --block_size=$BLOCK_SIZE --cache_size=$CACHE_SIZE --cache_numshardbits=$NUM_SHARD_BITS `# cache parameters` \
                            --max_write_buffer_number=4 --write_buffer_size=16777216 --target_file_size_base=16777216 --max_bytes_for_level_base=67108864 --max_bytes_for_level_multiplier=8 `#LSM structural parameters` \
                            --compression_type=none --disable_wal=1 `# no compression, no log` \
                            --cache_index_and_filter_blocks=1 --pin_l0_filter_and_index_blocks_in_cache=1 --partition_index_and_filters=1 --cache_high_pri_pool_ratio=0.5 `# index/filter caching` \
                            --statistics=0 --stats_per_interval=0 --stats_interval_seconds=0 --report_interval_seconds=0 --histogram=0 `# stats` \
                            --compaction_style=2 --fifo_compaction_allow_compaction=0 `# FIFO compaction` \
                            --max_background_jobs=16 --threads=$NUM_THREADS \
                            --duration=$DURATION \
                            --memtablerep=skip_list \
                            --verify_checksum=1 \
                            --bloom_bits=16 \
                            --seed=$SEED
                    done
                done
            done
        done
    done
done
