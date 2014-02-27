CC=gcc
CFLAGS=-g # -Wall -Wextra
TESTCASE_FILTER=

src=mbind.c mbind_fuzz.c
exe=$(src:.c=)
srcdir=.
dstdir=/usr/local/bin
dstexe=$(addprefix $(dstdir)/,$(exe))

OPT=-DDEBUG
LIBOPT=-lnuma # -lcgroup

all: get_test_core $(exe)
%: %.c
	$(CC) $(CFLAGS) -o $@ $^ $(OPT) $(LIBOPT)

get_test_core:
	git clone https://github.com/Naoya-Horiguchi/test_core || true
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
