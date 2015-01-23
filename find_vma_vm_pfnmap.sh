#!/bin/bash

ls -1 /proc | grep ^[0-9] | sort -n | tail -n10 | while read pid ; do
    if grep ^VmFlags: /proc/$pid/smaps | grep "pf" > /dev/null ; then
        # echo $pid "$(cat /proc/$pid/cmdline)"
        grep -hr -e ^VmFlags -e ^[0-9] /proc/$pid/smaps | grep -B1 -e "pf" | grep ^[0-9] | cut -f1 -d' ' | tr '-' ' ' > $TMPF.$pid.pfnmap_ranges
        cmd="$PAGETYPES -p $pid -Nl"

        while read spfn epfn ; do
            # printf "$cmd -a 0x%lx,0x%lx" $[0x$spfn / 4096] $[0x$epfn / 4096]
            cmd=$(printf "$cmd -a 0x%lx,0x%lx" $[0x$spfn / 4096] $[0x$epfn / 4096])
        done < $TMPF.$pid.pfnmap_ranges
        echo $cmd
        eval $cmd
    fi
done 2> /dev/null
