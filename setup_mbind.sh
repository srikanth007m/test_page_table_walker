#!/bin/bash

check_and_define_tp test_mbind
check_and_define_tp test_mbind_fuzz
check_and_define_tp test_mbind_unmap_race

TESTFILE=${WDIR}/testfile

kill_test_programs_mbind() {            
    pkill -9 -f $test_mbind
    pkill -9 -f $test_mbind_fuzz
    pkill -9 -f $test_mbind_unmap_race
    return 0
}                                 

check_numa_node_nr() {
    local nr_node=$(numactl -H | grep ^available: | cut -f2 -d' ')

    if [ "$nr_node" -gt 1 ] ; then
        echo "System has $nr_node NUMA node." | tee -a ${OFILE}
        return 0
    else
        echo "System is not a NUMA system." | tee -a ${OFILE}
        return 1
    fi
}

__prepare_mbind() {
    prepare_system_default
    kill_test_programs_mbind
}

__cleanup_mbind() {
    kill_test_programs_mbind
    cleanup_system_default
}

prepare_mbind() {
    check_numa_node_nr || return 1
    set_and_check_hugetlb_pool 200
    __prepare_mbind
}

cleanup_mbind() {
    __cleanup_mbind
    sysctl vm.nr_hugepages=0
    hugetlb_empty_check
}

control_mbind() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before mbind")
            ${PAGETYPES} -p ${pid} -a 0x700000000+0x2000 -Nrl >> ${OFILE}
            cat /proc/${pid}/numa_maps | grep "^70" > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            sleep 0.5
            kill -SIGUSR1 $pid
            ;;
        "mbind exit")
            ${PAGETYPES} -p ${pid} -a 0x700000000+0x2000 -Nrl >> ${OFILE}
            cat /proc/${pid}/numa_maps | grep "^70" > ${TMPF}.numa_maps2
            kill -SIGUSR1 $pid
            set_return_code "EXIT"
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

# inside cheker you must tee output in you own.
check_mbind() {
    check_system_default
    check_mbind_numa_maps "700000000000"  || return 1
    check_mbind_numa_maps "700000200000"  || return 1
    check_mbind_numa_maps "700000400000"  || return 1
}

get_numa_maps_nodes() {
    local numa_maps=$1
    local vma_start=$2
    grep "^${vma_start} " ${numa_maps} | tr ' ' '\n' | grep -E "^N[0-9]=" | tr '\n' ' '
}

check_mbind_numa_maps() {
    local address=$1
    local node1=$(get_numa_maps_nodes ${TMPF}.numa_maps1 ${address})
    local node2=$(get_numa_maps_nodes ${TMPF}.numa_maps2 ${address})

    count_testcount
    if [ ! -f ${TMPF}.numa_maps1 ] || [ ! -f ${TMPF}.numa_maps2 ] ; then
        count_failure "numa_maps file not exist."
        return 1
    fi

    if [ "$node1" == "$node2" ] ; then
        count_failure "vaddr ${address} is not migrated. map1=${node1}, map2=${node2}."
        return 1
    else
        count_success "vaddr ${address} is migrated."
    fi
}

prepare_mbind_fuzz() {
    check_numa_node_nr || return 1
    set_and_check_hugetlb_pool 200
    pkill -9 -P $$ -f $(basename $MBIND_FUZZ) 2> /dev/null
    pkill -9 -P $$ -f $(basename $MBIND_UNMAP) 2> /dev/null
    dd if=/dev/urandom of=${TESTFILE} bs=4096 count=$[512*10]
    mkdir -p ${WDIR}/mount
    mount -t hugetlbfs none ${WDIR}/mount
    prepare_system_default
}

cleanup_mbind_fuzz() {
    cleanup_system_default
    pkill -9 -P $$ -f $(basename $MBIND_FUZZ)
    pkill -9 -P $$ -f $(basename $MBIND_UNMAP)
    ipcs -m | cut -f2 -d' ' | egrep '[0-9]' | xargs ipcrm shm > /dev/null 2>&1
    ipcs -m | cut -f2 -d' ' | egrep '[0-9]' | xargs ipcrm -m > /dev/null 2>&1
    rm -rf ${WDIR}/mount/*
    echo 3 > /proc/sys/vm/drop_caches
    sync
    umount -f ${WDIR}/mount
    umount -f ${WDIR}/mount
    umount -f ${WDIR}/mount
    umount -f ${WDIR}/mount
    sysctl vm.nr_hugepages=0
    hugetlb_empty_check
}

control_mbind_fuzz() {
    echo "start mbind_fuzz" | tee -a ${OFILE}
    ${MBIND_FUZZ} -f ${TESTFILE} -n 10 -N 10 -t 0xff > ${TMPF}.fuz.out 2>&1 &
    local pid=$!
    sleep 5
    ${PAGETYPES} -p $pid     > /dev/null
    cat /proc/$pid/numa_maps > /dev/null
    cat /proc/$pid/smaps     > /dev/null
    cat /proc/$pid/maps      > /dev/null
    pkill -SIGUSR1 $pid
    set_return_code EXIT
}

check_mbind_fuzz() {
    echo "---" | tee -a ${OFILE}
    check_system_default
}

control_mbind_fuzz_normal_heavy() {
    echo "start mbind_fuzz_normal_heavy" | tee -a ${OFILE}
    local threads=100
    local nr=1000
    local type=0x80
    for i in $(seq $threads) ; do
        ${MBIND_FUZZ} -f ${TESTFILE} -n $nr -t $type > ${TMPF}.fuz.out 2>&1 &
        # echo "pid $!"
    done
    sleep 5
    pkill -SIGUSR1 -f ${MBIND_FUZZ}
    set_return_code EXIT
}

control_mbind_unmap_race() {
    echo "start mbind_unmap_race" | tee -a ${OFILE}
    local threads=10
    local nr=1000
    local type=0x80
    for i in $(seq $threads) ; do
        ${MBIND_UNMAP} -f ${TESTFILE} -n $nr -N 2 -t $type > ${TMPF}.fuz.out 2>&1 &
        echo "pid $!"
    done
    sleep 10
    pkill -SIGUSR1 -f ${MBIND_UNMAP}
    set_return_code EXIT
}
