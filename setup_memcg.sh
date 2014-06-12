#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

MEMCGDIR=/sys/fs/cgroup/memory
MALLOC_MADV_WILLNEED=$(dirname $(readlink -f $BASH_SOURCE))/malloc_madv_willneed
[ ! -x "$MALLOC_MADV_WILLNEED" ] && echo "${MALLOC_MADV_WILLNEED} not found." >&2 && exit 1

prepare_test() {
    get_kernel_message_before
}

prepare_memcg() {
    mkdir $MEMCGDIR/test1
    mkdir $MEMCGDIR/test2
    echo 1 > $MEMCGDIR/test1/memory.move_charge_at_immigrate
    echo 1 > $MEMCGDIR/test2/memory.move_charge_at_immigrate
    prepare_test
}

cleanup_test() {
    get_kernel_message_after
    get_kernel_message_diff
}

cleanup_memcg() {
    rm -rf $MEMCGDIR/test1
    rm -rf $MEMCGDIR/test2
    cleanup_test
}

control_memcg() {
    cgexec -g memory:test1 sleep 1000 &
    cgexec -g memory:test1 sleep 1000 &
    cgexec -g memory:test1 sleep 1000 &
    cgexec -g memory:test1 sleep 1000 &
    cgexec -g memory:test1 sleep 1000 &
    cat $MEMCGDIR/test1/tasks > $MEMCGDIR/test2/tasks || set_return_code MOVE_FAIL
    cat $MEMCGDIR/test2/tasks > $MEMCGDIR/test1/tasks || set_return_code MOVE_FAIL
    cat $MEMCGDIR/test1/tasks > $MEMCGDIR/test2/tasks || set_return_code MOVE_FAIL
    cat $MEMCGDIR/test2/tasks > $MEMCGDIR/test1/tasks || set_return_code MOVE_FAIL
    pkill sleep
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
    cgset -r memory.limit_in_bytes=0x1000000 test1
    cgexec -g memory:test1 $MALLOC_MADV_WILLNEED 0x1000000 &
    local pid=$!
    echo $pid
    sleep 2
    free
    swapon -s
    cgset -r memory.limit_in_bytes=0x8000000 test1
    kill -SIGUSR1 $pid
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
