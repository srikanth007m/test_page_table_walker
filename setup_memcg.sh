#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

if [ ! -d /sys/fs/cgroup/memory ] ; then
    echo "memory cgroup is not supported on this kernel $(uname -r)"
    return
fi

MEMCGDIR=/sys/fs/cgroup/memory
MALLOC_MADV_WILLNEED=$(dirname $(readlink -f $BASH_SOURCE))/malloc_madv_willneed
[ ! -x "$MALLOC_MADV_WILLNEED" ] && echo "${MALLOC_MADV_WILLNEED} not found." >&2 && exit 1

yum install -y libcgroup-tools

prepare_test() {
    get_kernel_message_before
}

prepare_memcg() {
    pkill -9 sleep
    cgdelete memory:test1 2> /dev/null
    cgdelete memory:test2 2> /dev/null
    cgcreate -g memory:test1
    cgcreate -g memory:test2
    echo 1 > $MEMCGDIR/test1/memory.move_charge_at_immigrate
    echo 1 > $MEMCGDIR/test2/memory.move_charge_at_immigrate
    prepare_test
}

cleanup_test() {
    get_kernel_message_after
    get_kernel_message_diff
}

cleanup_memcg() {
    pkill -9 sleep
    cgdelete memory:test1
    cgdelete memory:test2
    cleanup_test
}

control_memcg() {
    cgexec -g memory:test1 sleep 1000 &
    # cgexec -g memory:test1 sleep 1000 &
    # cgexec -g memory:test1 sleep 1000 &
    # cgexec -g memory:test1 sleep 1000 &
    # cgexec -g memory:test1 sleep 1000 &
    sleep 0.5
    cat $MEMCGDIR/test1/tasks > $TMPF.test1_tasks_1
    cat $MEMCGDIR/test2/tasks > $TMPF.test2_tasks_1
    cgclassify -g memory:test1 $(cat $MEMCGDIR/test1/tasks) || set_return_code MOVE_FAIL
    cat $MEMCGDIR/test1/tasks > $TMPF.test1_tasks_2
    cat $MEMCGDIR/test2/tasks > $TMPF.test2_tasks_2
    pkill -9 sleep
    set_return_code "EXIT"
    return 0
}

check_test() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

check_memcg() {
    check_test
    count_testcount
    if diff $TMPF.test1_tasks_1 $TMPF.test2_tasks_2 2> /dev/null >&2 ; then
        count_success "processes moved from memory:test1 to memory:test2"
    else
        count_failure "processes failed to move from memory:test1 to memory:test2"
    fi
}

prepare_force_swapin_readahead() {
    prepare_memcg
    dd if=/dev/zero of=$WDIR/swapfile bs=4096 count=10240 > /dev/null 2>&1
    mkswap $WDIR/swapfile
    chmod 0600 $WDIR/swapfile
    swapon $WDIR/swapfile
    swapon -s
}

cleanup_force_swapin_readahead() {
    swapoff $WDIR/swapfile
    rm -rf $WDIR/swapfile
    swapon -s
    cleanup_memcg
}

control_force_swapin_readahead() {
    echo 0x1000000 > $MEMCGDIR/test1/memory.limit_in_bytes
    echo 0x2000000 > $MEMCGDIR/test1/memory.memsw.limit_in_bytes
    # cgset -r memory.limit_in_bytes=0x1000000 test1
    # cgset -r memory.memsw.limit_in_bytes=0x2000000 test1
    cgget -g memory:test1 | grep limit
    cgexec -g memory:test1 $MALLOC_MADV_WILLNEED 0x1200000 &
    local pid=$!
    # echo $pid
    ps eo cmd,pid,pmem,rss $pid
    sleep 2
    free
    swapon -s
    cgset -r memory.limit_in_bytes=0x8000000 test1
    kill -SIGUSR1 $pid # MALLOC_MADV_WILLNEED calls madvise(MADV_WILLNEED)
    sleep 3
    free
    swapon -s
    kill -SIGUSR1 $pid
    wait $pid
    set_return_code "EXIT"
    return 0
}

check_force_swapin_readahead() {
    check_test
}
