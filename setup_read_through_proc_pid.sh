control_read_through_proc_pid() {
    ls -1 /proc | grep ^[0-9] > $TMPF.pids
    while read pid ; do
        cat /proc/$pid/maps > /dev/null 2>&1
        cat /proc/$pid/smaps > /dev/null 2>&1
        cat /proc/$pid/numa_maps > /dev/null 2>&1
    done < $TMPF.pids
    set_return_code EXIT
}

check_read_through_proc_pid() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}
