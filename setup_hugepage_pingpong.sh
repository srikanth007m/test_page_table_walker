#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

# Main test programs
HUGEPAGE_PINGPONG=$(dirname $(readlink -f $BASH_SOURCE))/hugepage_pingpong
[ ! -x "$HUGEPAGE_PINGPONG" ] && echo "$HUGEPAGE_PINGPONG} not found." >&2 && exit 1
TESTFILE=${WDIR}/testfile
sysctl vm.nr_hugepages=500

prepare_test() {
    get_kernel_message_before
}

cleanup_test() {
    get_kernel_message_after
    get_kernel_message_diff
}

check_test() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

control_hugepage_pingpong() {
    echo "start hugepage_pingpong" | tee -a ${OFILE}
    ${HUGEPAGE_PINGPONG} -n 10 -t 0xff > ${TMPF}.fuz.out 2>&1 &
    local pid=$!
    echo "pid $pid"
    sleep 10
    pkill -SIGUSR1 $pid
    set_return_code EXIT
}

control_hugepage_pingpong_race() {
    echo "start 2 hugepage_pingpong processes" | tee -a ${OFILE}
    ${HUGEPAGE_PINGPONG} -n 1 -t 0xff > ${TMPF}.fuz.out1 2>&1 &
    local pid1=$!
    echo "pid $pid1"
    ${HUGEPAGE_PINGPONG} -n 1 -t 0xff > ${TMPF}.fuz.out2 2>&1 &
    local pid2=$!
    echo "pid $pid2"
    sleep 10
    kill -SIGUSR1 $pid1
    kill -SIGUSR1 $pid2
    set_return_code EXIT
}

NUMA_MAPS_READER=${TMPF}.read_numa_maps.sh
cat <<EOF > ${NUMA_MAPS_READER}
while true ; do
    cat /proc/\$1/numa_maps > /dev/null 2>&1
    cat /proc/\$2/numa_maps > /dev/null 2>&1
done
EOF

control_hugepage_pingpong_race_with_numa_maps() {
    echo "start 2 hugepage_pingpong processes" | tee -a ${OFILE}
    ${HUGEPAGE_PINGPONG} -n 1 -t 0xff > ${TMPF}.fuz.out1 2>&1 &
    local pid1=$!
    echo "pid $pid1"
    ${HUGEPAGE_PINGPONG} -n 1 -t 0xff > ${TMPF}.fuz.out2 2>&1 &
    local pid2=$!
    echo "pid $pid2"
    bash ${NUMA_MAPS_READER} "$pid1" "$pid2" &
    local pid=$!
    sleep 10
    kill -SIGKILL $pid
    kill -SIGUSR1 $pid1
    kill -SIGUSR1 $pid2
    set_return_code EXIT
}

prepare_hugepage_pingpong() {
    pkill -SIGKILL -f ${HUGEPAGE_PINGPONG}
    mkdir -p ${WDIR}/mount
    mount -t hugetlbfs none ${WDIR}/mount
    prepare_test
}

cleanup_hugepage_pingpong() {
    cleanup_test
    echo "cleanup pingpong process" | tee -a ${OFILE}
    pkill -SIGKILL -f ${HUGEPAGE_PINGPONG}
    echo "remove hugetlbfs files" | tee -a ${OFILE}
    rm -rf ${WDIR}/mount/*
    echo "umount hugetlbfs" | tee -a ${OFILE}
    umount -f ${WDIR}/mount
}

# inside cheker you must tee output in you own.
check_hugepage_pingpong() {
    check_test
    __check_hugepage_pingpong
}

__check_hugepage_pingpong() {
    echo "check done." | tee -a ${OFILE}
}
