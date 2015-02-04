#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

# Main test programs
MBIND=$(dirname $(readlink -f $BASH_SOURCE))/mbind
MBIND_FUZZ=$(dirname $(readlink -f $BASH_SOURCE))/mbind_fuzz
MBIND_UNMAP=$(dirname $(readlink -f $BASH_SOURCE))/mbind_unmap_race
[ ! -x "$MBIND" ] && echo "${MBIND} not found." >&2 && exit 1
[ ! -x "$MBIND_FUZZ" ] && echo "${MBIND_FUZZ} not found." >&2 && exit 1
[ ! -x "$MBIND_UNMAP" ] && echo "${MBIND_UNMAP} not found." >&2 && exit 1
TESTFILE=${WDIR}/testfile

check_numa_node_nr() {
    local nr_node=$(numactl -H | grep ^available: | cut -f2 -d' ')
    if [ "$nr_node" -gt 1 ] ; then
        echo "System has $nr_node NUMA node."
        return 0
    else
        echo "System is not a NUMA system."
        return 1
    fi
}

prepare_test() {
    get_kernel_message_before
}

cleanup_test() {
    get_kernel_message_after
    get_kernel_message_diff
}

prepare_mbind() {
    check_numa_node_nr || return 1
    sysctl vm.nr_hugepages=200
    prepare_test
}

cleanup_mbind() {
    cleanup_test
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

check_test() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

# inside cheker you must tee output in you own.
check_mbind() {
    check_test
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
    sysctl vm.nr_hugepages=200
    pkill -9 -P $$ -f $(basename $MBIND_FUZZ) 2> /dev/null
    pkill -9 -P $$ -f $(basename $MBIND_UNMAP) 2> /dev/null
    dd if=/dev/urandom of=${TESTFILE} bs=4096 count=$[512*10]
    mkdir -p ${WDIR}/mount
    mount -t hugetlbfs none ${WDIR}/mount
    prepare_test
}

cleanup_mbind_fuzz() {
    cleanup_test
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
    check_test
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
