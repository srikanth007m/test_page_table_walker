#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

MINCORE=$(dirname $(readlink -f $BASH_SOURCE))/mincore
[ ! -x "$MINCORE" ] && echo "${MINCORE} not found." >&2 && exit 1

echo always > /sys/kernel/mm/transparent_hugepage/enabled

prepare_test() {
    get_kernel_message_before
}

prepare_mincore() {
    dd if=/dev/zero of=${TMPF}.holefile bs=4096 count=2 > /dev/null 2>&1
    dd if=/dev/zero of=${TMPF}.holefile bs=4096 count=2 seek=2046 > /dev/null 2>&1
    sysctl vm.nr_hugepages=10
    prepare_test
}

cleanup_test() {
    get_kernel_message_after
    get_kernel_message_diff
}

cleanup_mincore() {
    sysctl vm.nr_hugepages=0
    cleanup_test
}

control_mincore() {
    local pid="$1"
    local line="$2"

    echo "$line" >> ${TMPF}.mincore
    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "entering busy loop")
            cat /proc/${pid}/maps > ${TMPF}.maps
            ${PAGETYPES} -p ${pid} -rl > ${TMPF}.page-types
            kill -SIGUSR1 $pid
            ;;
        "mincore exit")
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
check_mincore() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
    check_mincore_map "mincore1" '\b1\{256\}0\{256\}\b' || return 1
    check_mincore_map "mincore2" '\b1\{512\}\b' || return 1
    check_mincore_map "mincore3" '\b1\{512\}\b' || return 1
    check_mincore_map "mincore4" '\b1\{128\}0\{128\}\b' || return 1
    check_mincore_map "mincore5" '\b110\{2044\}11\b' || return 1
    check_mincore_map "mincore6" '\b10\b' || return 1
    check_mincore_map "mincore7" '\b10\b' || return 1
}

check_mincore_map() {
    local tag="$1"
    local pattern="$2"
    count_testcount
    grep "${tag}" ${TMPF}.mincore | grep "${pattern}" > /dev/null
    if [ $? -eq 0 ] ; then
        count_success "correct mincore map in ${tag}."
        return 0
    else
        count_failure "got incorrect mincore map in ${tag} $(grep "${tag}" ${TMPF}.mincore | cut -f2 -d:)"
        return 1
    fi
}
