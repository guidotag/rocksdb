#!/usr/bin/env bash
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
# REQUIRE: db_bench binary exists in the current directory

cache_capacity() {
    KV_SIZE=$(($KEY_SIZE + $VALUE_SIZE))
    echo $(($CACHE_SIZE/$KV_SIZE))
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
POPULATE=n

# Machine params
NUM_HW_THREADS=24

# DB params
KEY_SIZE=20
VALUE_SIZE=400
BLOCK_SIZE=8192
DB_ELEM_COUNT=400000000
DURATION=120
SEED=1652227743

# DB and report directories
DB=/data/db_bench-db
DB_BENCH_REPORTS_DIR=/data/db_bench-reports

NUM_SHARDS_LIST=(64)
NUM_THREADS_LIST=(1 16 32 64 80 160)
CACHE_SIZE_LIST=(1073741824) # 1GB
CACHE_TYPE_LIST=(clock_cache lru_cache)

if [ "$COMPILE" == "y" ]
then
    DEBUG_LEVEL=0 make checkout_folly
    DEBUG_LEVEL=0 USE_FOLLY=1 ROCKSDB_NO_FBCODE=1 make -j${NUM_HW_THREADS} db_bench
fi

mkdir -p $DB_BENCH_REPORTS_DIR

if [ "$POPULATE" == "y" ]
then
    # Populate the database.
    numactl --interleave=all ./db_bench --benchmarks=fillseq,flush,waitforcompaction,compact0,waitforcompaction,compact1,waitforcompaction \
        --db=$DB --use_existing_db=0 \
        --allow_concurrent_memtable_write=false --level0_file_num_compaction_trigger=4 --level0_slowdown_writes_trigger=20 --level0_stop_writes_trigger=30 \
        --num=$DB_ELEM_COUNT --key_size=$KEY_SIZE --value_size=$VALUE_SIZE --value_size_distribution_type=fixed `#key-value parameters` \
        --block_size=$BLOCK_SIZE --cache_size=68719476736 --cache_numshardbits=6 `# cache parameters` \
        --max_write_buffer_number=4 --write_buffer_size=16777216 --target_file_size_base=16777216 --max_bytes_for_level_base=67108864 --max_bytes_for_level_multiplier=8 `#LSM structural parameters` \
        --compression_type=none --disable_wal=1 `# no compression, no log` \
        --cache_index_and_filter_blocks=1 --pin_l0_filter_and_index_blocks_in_cache=1 --partition_index_and_filters=1 --cache_high_pri_pool_ratio=0.5 `# index/filter caching` \
        --statistics=0 --stats_per_interval=0 --stats_interval_seconds=0 --histogram=0 `# stats` \
        --compaction_style=0 `# level-based compaction` \
        --max_background_jobs=16 --threads=1 \
        --memtablerep=skip_list \
        --verify_checksum=1 \
        --bloom_bits=16 \
        --seed=$SEED \
        --report_interval_seconds=0
    # For FIFO compaction use --compaction_style=2 --fifo_compaction_max_table_files_size_mb=10000 --fifo_compaction_allow_compaction=0
    # Warning: fifo_compaction_max_table_files_size_mb acts as a hard limit on the DB size.
fi

for NUM_SHARDS in ${NUM_SHARDS_LIST[@]}
do
    for NUM_THREADS in ${NUM_THREADS_LIST[@]}
    do
        for CACHE_SIZE in ${CACHE_SIZE_LIST[@]}
        do
            for CACHE_TYPE in ${CACHE_TYPE_LIST[@]}
            do
                NUM_SHARD_BITS=$(printf %.0f $(log2 $NUM_SHARDS))
                CACHE_CAP=$(cache_capacity)

                SINGLETON=1
                VERY_SMALL_SUPPORT=$NUM_SHARDS
                SMALL_SUPPORT=$(($CACHE_CAP / 10))
                MEDIUM_SUPPORT=$(($CACHE_CAP))
                MEDIUM_2_SUPPORT=$(($CACHE_CAP * 1125 / 1000))
                MEDIUM_3_SUPPORT=$(($CACHE_CAP * 125 / 100))
                MEDIUM_4_SUPPORT=$(($CACHE_CAP * 15 / 10))
                MEDIUM_5_SUPPORT=$(($CACHE_CAP * 2))
                LARGE_SUPPORT=$(($CACHE_CAP * 10))
                VERY_LARGE_SUPPORT=$(($CACHE_CAP * 100))
                HUGE_SUPPORT=$(($CACHE_CAP * 1000))
                #SUPPORT_SIZE_LIST=($SINGLETON $VERY_SMALL_SUPPORT $SMALL_SUPPORT $MEDIUM_SUPPORT $LARGE_SUPPORT $VERY_LARGE_SUPPORT $HUGE_SUPPORT)
                SUPPORT_SIZE_LIST=($MEDIUM_2_SUPPORT $MEDIUM_3_SUPPORT $MEDIUM_4_SUPPORT $MEDIUM_5_SUPPORT)
                for SUPPORT_SIZE in ${SUPPORT_SIZE_LIST[@]}
                do
                    print_sep \#
                    print_sep =
                    echo -e "\tCache type: $CACHE_TYPE"
                    echo -e "\tCache size: $CACHE_SIZE"
                    echo -e "\tBlock size: $BLOCK_SIZE"
                    echo -e "\tNum shards: $NUM_SHARDS"
                    echo -e "\tSupport size: $SUPPORT_SIZE"
                    echo -e "\tThreads: $NUM_THREADS"
                    print_sep =

                    numactl --interleave=all ./db_bench --benchmarks=readrandom \
                        --db=$DB --use_existing_db=1 \
                        --level0_file_num_compaction_trigger=4 --level0_slowdown_writes_trigger=20 --level0_stop_writes_trigger=30 \
                        --num=$SUPPORT_SIZE --key_size=$KEY_SIZE --value_size=$VALUE_SIZE --value_size_distribution_type=fixed `#key-value parameters` \
                        --cache_type=$CACHE_TYPE --block_size=$BLOCK_SIZE --cache_size=$CACHE_SIZE --cache_numshardbits=$NUM_SHARD_BITS `# cache parameters` \
                        --max_write_buffer_number=4 --write_buffer_size=16777216 --target_file_size_base=16777216 --max_bytes_for_level_base=67108864 --max_bytes_for_level_multiplier=8 `#LSM structural parameters` \
                        --compression_type=none --disable_wal=1 `# no compression, no log` \
                        --cache_index_and_filter_blocks=1 --pin_l0_filter_and_index_blocks_in_cache=1 --partition_index_and_filters=1 --cache_high_pri_pool_ratio=0.5 `# index/filter caching` \
                        --statistics=1 --stats_per_interval=1 --stats_interval_seconds=1 --histogram=0 `# stats` \
                        --compaction_style=0 `# level-based compaction` \
                        --max_background_jobs=16 --threads=$NUM_THREADS \
                        --duration=$DURATION \
                        --memtablerep=skip_list \
                        --verify_checksum=1 \
                        --bloom_bits=16 \
                        --seed=$SEED \
                        --report_file=${DB_BENCH_REPORTS_DIR}/db_bench-report-${NUM_SHARDS}-${NUM_THREADS}-${CACHE_SIZE}-${CACHE_TYPE}-${SUPPORT_SIZE}.csv \
                        --report_interval_seconds=1 \
                        1>${DB_BENCH_REPORTS_DIR}/db_bench-stdout-${NUM_SHARDS}-${NUM_THREADS}-${CACHE_SIZE}-${CACHE_TYPE}-${SUPPORT_SIZE}.txt \
                        2>${DB_BENCH_REPORTS_DIR}/db_bench-stderr-${NUM_SHARDS}-${NUM_THREADS}-${CACHE_SIZE}-${CACHE_TYPE}-${SUPPORT_SIZE}.txt
                done
            done
        done
    done
done
