CC=gcc
CFLAGS=-g # -Wall -Wextra
TESTCASE_FILTER=

src=test_mbind.c test_mbind_fuzz.c test_mbind_unmap_race.c test_malloc_madv_willneed.c test_mincore.c test_mbind_bug_reproducer.c test_vma_vm_pfnmap.c
exe=$(src:.c=)
srcdir=.
dstdir=/usr/local/bin
dstexe=$(addprefix $(dstdir)/,$(exe))

OPT=-DDEBUG
LIBOPT=-lnuma # -lcgroup

all: get_test_core get_rpms $(exe)
%: %.c
	$(CC) $(CFLAGS) -o $@ $^ $(OPT) $(LIBOPT)

get_test_core:
	@test -d "test_core" || git clone https://github.com/Naoya-Horiguchi/test_core
	@true

get_rpms:
	yum install -y numactl*
	@true

install: $(exe)
	for file in $? ; do \
	  mv $$file $(dstdir) ; \
	done

clean:
	@for file in $(exe) ; do \
	  rm $(dstdir)/$$file 2> /dev/null ; \
	  rm $(srcdir)/$$file 2> /dev/null ; \
	  true ; \
	done

test: all
	@bash run-test.sh -v -r page_table_walker.rc $(TESTCASE_FILTER)
