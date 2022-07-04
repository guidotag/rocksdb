#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: cache_bench binary exists in the current directory

make -j24 db_bench

capacity() {
    echo $(($CACHE_SIZE/$BLOCK_SIZE))
}

log2() {
    echo $(echo "l($1)/l(2)" | bc -l)
}

CACHE_SIZE_LIST=(1073741824) #(1073741824 8589934592 34359738368) # 1GB, 8GB, 32GB
BLOCK_SIZE_LIST=(8192) #(8192 2097152) # 8kB, 2MB
DB_DIR=/data/m/rx
KEY_SIZE=20
VALUE_SIZE=400
REPORT_FILE_DIR=bm.lc.nt32.cm1.d0/hash.def
BENCHMARKS=(fillrandom readrandom readwhilewriting)
SEED=1652227743

for CACHE_SZE in ${CACHE_SIZE[@]}
do
    for BLOCK_SIZE in ${BLOCK_SIZE[@]}
    do
        NUM_SHARDS_LIST=(64)
        for NUM_SHARDS in ${NUM_SHARDS_LIST[@]}
        do
            NUM_SHARD_BITS=$(printf %.0f $(log2 $NUM_SHARDS))
            CAP=$(capacity)

            SINGLETON=1
            SMALL_SUPPORT=$NUM_SHARDS
            MEDIUM_SUPPORT=$CAP
            LARGE_SUPPORT=$(($CAP * 100))
            NUM_ELEMS_LIST=($SINGLETON $SMALL_SUPPORT $MEDIUM_SUPPORT $LARGE_SUPPORT)
            USE_EXISTING_DB=(0 1 1)
            for i in ${!BENCHMARKS[@]}
            do
                for NUM_ELEMS in ${NUM_ELEMS_LIST[@]}
                do
                    numactl --interleave=all ./db_bench --benchmarks=${BENCHMARKS[i]} --use_existing_db=${USE_EXISTING_DB[i]} \
                        --level0_file_num_compaction_trigger=4 --level0_slowdown_writes_trigger=20 --level0_stop_writes_trigger=30 \
                        --num=$NUM_ELEMS --key_size=$KEY_SIZE --value_size=$VALUE_SIZE --value_size_distribution_type=fixed \ # key-value parameters
                        --block_size=$block_size --cache_size=$CACHE_SIZE --cache_numshardbits=$NUM_SHARD_BITS \ # cache parameters
                        --max_write_buffer_number=4 --write_buffer_size=16777216 --target_file_size_base=16777216 --max_bytes_for_level_base=67108864 --max_bytes_for_level_multiplier=8 \ #LSM structural parameters
                        --compression_type=none --disable_wal=1 \ # no compression, no log
                        --cache_index_and_filter_blocks=1 --pin_l0_filter_and_index_blocks_in_cache=1 --partition_index_and_filters=1 --cache_high_pri_pool_ratio=0.5 \ # index/filter caching
                        --statistics=0 --stats_per_interval=1 --stats_interval_seconds=20 --report_interval_seconds=5 --histogram=1 \ # stats
                        --compaction_style=2 --fifo_compaction_allow_compaction=0 \ # no compaction
                        --max_background_jobs=16 --threads=16 \
                        --duration=600 \
                        --memtablerep=skip_list \
                        --verify_checksum=1 \
                        --bloom_bits=16 \
                        --seed=$SEED \
                        --db=$DB_DIR \
                        --report_file=$REPORT_FILE_DIR/benchmark_${BENCHMARKS[i]}_non_skewed_${num_elems}.csv
                done
            done
        done
    done
done
