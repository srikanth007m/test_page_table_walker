#include <stdio.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <asm/unistd.h>
#include <numa.h>
#include <numaif.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>
#include <sys/time.h>
#include "test_core/lib/include.h"
#include "test_core/lib/hugepage.h"

#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

int checked_mbind(char *addr, unsigned long size, struct bitmask *bmask) {
	int ret = mbind(addr, size, MPOL_BIND, bmask->maskp, bmask->size + 1,
			MPOL_MF_MOVE_ALL);
			/* MPOL_MF_MOVE|MPOL_MF_STRICT); */
	if (ret == -1)
		perror("mbind");
}

void get_range(unsigned long *start, unsigned long *end) {
	return;
}

void set_new_nodes(struct bitmask *mask, unsigned long node) {
	numa_bitmask_clearall(mask);
	numa_bitmask_setbit(mask, node);
}

int main(int argc, char *argv[]) {
	int i;
	int nr = 2;
	int ret;
	int fd = -1;
	int hugetlbfd1 = -1;
	int hugetlbfd2 = -1;
	int node;
	char c;
	char *p;
	unsigned long memsize = 2*1024*1024;
	int mapflag = MAP_ANONYMOUS;
	unsigned long offset;
	unsigned long length;
	unsigned long address = ADDR_INPUT;
	char *pmem;
	char *phugetlb;
	char *phugetlbfile1;
	char *phugetlbfile2;
	char *pshmhugetlb;
	char *pthp;
	char *pfile1;
	char *pfile2;
	char *file = NULL;
	char *hugetlbfile1 = "work/mount/testfile1";
	char *hugetlbfile2 = "work/mount/testfile2";
	char wbuf[PS];
	unsigned long nodemask;
	struct timeval tv;
	struct bitmask *nodes;
	unsigned long nr_nodes;
	unsigned long HPS = 2*1024*1024;
	unsigned long nr_hps = 1;
	unsigned long type = 0xffff;
	int oneshot = 0;
	int sleep = 0;

	while ((c = getopt(argc, argv, "p:vf:n:t:os")) != -1) {
		switch(c) {
		case 'p':
			testpipe = optarg;
			{
				struct stat stat;
				lstat(testpipe, &stat);
				if (!S_ISFIFO(stat.st_mode))
					errmsg("Given file is not fifo.\n");
			}
			break;
		case 'v':
			verbose = 1;
			break;
		case 'f':
			file = optarg;
			break;
		case 'n':
			nr_hps = strtoul(optarg, NULL, 0);
			memsize = nr_hps * HPS;
			break;
		case 't':
			type = strtoul(optarg, NULL, 0);
			break;
		case 'o':
			oneshot = 1;
			break;
		case 's':
			sleep = 1;
			break;
		default:
			errmsg("invalid option\n");
			break;
		}
	}

	nr_nodes = numa_max_node() + 1; /* numa_num_possible_nodes(); */
	nodes = numa_bitmask_alloc(nr_nodes);
	if (nr_nodes < 2)
		errmsg("A minimum of 2 nodes is required for this test.\n");

	if (!file)
		errmsg("no file given with -f option.\n");

	gettimeofday(&tv, NULL);
	srandom(tv.tv_usec);

	if (type & (1 << 0)) {
		mapflag = MAP_PRIVATE|MAP_ANONYMOUS;
		pmem = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag, -1, 0);
		madvise(pmem, memsize, MADV_NOHUGEPAGE);
		memset(pmem, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 1)) {
		mapflag = MAP_PRIVATE|MAP_ANONYMOUS|MAP_HUGETLB;
		phugetlb = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag, -1, 0);
		memset(phugetlb, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 2)) {
		mapflag = MAP_PRIVATE|MAP_ANONYMOUS;
		pthp = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag, -1, 0);
		memset(pthp, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 3)) {
		fd = checked_open(file, O_RDWR);
		mapflag = MAP_PRIVATE;
		pfile1 = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag, fd, 0);
		memset(pfile1, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 4)) {
		hugetlbfd1 = open(hugetlbfile1, O_CREAT|O_RDWR, 0755);
		if (hugetlbfd1 == -1)
			errmsg("open hugetlbfs");
		mapflag = MAP_SHARED;
		phugetlbfile1 = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag, hugetlbfd1, 0);
		memset(phugetlbfile1, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 5)) {
		hugetlbfd2 = open(hugetlbfile2, O_CREAT|O_RDWR, 0755);
		if (hugetlbfd2 == -1)
			errmsg("open hugetlbfs");
		mapflag = MAP_PRIVATE;
		phugetlbfile2 = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag, hugetlbfd2, 0);
		memset(phugetlbfile2, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 6)) {
		pshmhugetlb = alloc_shm_hugepage(memsize);
		memset(pshmhugetlb, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 7)) {
		fd = checked_open(file, O_RDWR);
		mapflag = MAP_SHARED;
		pfile2 = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag, fd, 0);
		memset(pfile2, 'a', memsize);
		address += memsize;
	}
	signal(SIGUSR1, sig_handle);
	if (sleep)
		pause();

	signal(SIGUSR1, sig_handle_flag);
	pprintf("entering busy loop\n");

	while (flag) {
		if (type & (1 << 0)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, node);
			offset = (random() % (memsize / PS)) * PS;
			length = (random() % (memsize/PS - offset/PS)) * PS;
			offset = PS;
			length = PS;
			printf("1: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(pmem + offset, length, nodes);
		}
		if (type & (1 << 1)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, random() & nr_nodes);
			offset = (random() % (memsize / HPS)) * HPS;
			length = (random() % (memsize/HPS - offset/HPS)) * HPS;
			offset = HPS;
			length = HPS;
			printf("2: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(phugetlb + offset, length, nodes);
		}
		if (type & (1 << 2)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, random() & nr_nodes);
			offset = (random() % (memsize / PS)) * PS;
			length = (random() % (memsize/PS - offset/PS)) * PS;
			printf("3: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(pthp + offset, length, nodes);
		}
		if (type & (1 << 3)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, random() & nr_nodes);
			offset = (random() % (memsize / PS)) * PS;
			length = (random() % (memsize/PS - offset/PS)) * PS;
			printf("4: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(pfile1 + offset, length, nodes);
		}
		if (type & (1 << 4)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, random() & nr_nodes);
			offset = (random() % (memsize / HPS)) * HPS;
			length = (random() % (memsize/HPS - offset/HPS)) * HPS;
			printf("5: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(phugetlbfile1 + offset, length, nodes);
		}
		if (type & (1 << 5)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, random() & nr_nodes);
			offset = (random() % (memsize / HPS)) * HPS;
			length = (random() % (memsize/HPS - offset/HPS)) * HPS;
			printf("6: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(phugetlbfile2 + offset, length, nodes);
		}
		if (type & (1 << 6)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, random() & nr_nodes);
			offset = (random() % (memsize / HPS)) * HPS;
			length = (random() % (memsize/HPS - offset/HPS)) * HPS;
			printf("7: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(pshmhugetlb + offset, length, nodes);
		}
		if (type & (1 << 7)) {
			node = random() % nr_nodes;
			set_new_nodes(nodes, random() & nr_nodes);
			offset = (random() % (memsize / PS)) * PS;
			length = (random() % (memsize/PS - offset/PS)) * PS;
			printf("8: node:%x, offset:%x, length:%x\n", node, offset, length);
			checked_mbind(pfile2 + offset, length, nodes);
		}
		/* usleep(1000); */
		if (type & (1 << 0))
			memset(pmem, 'a', memsize);
		if (type & (1 << 1))
			memset(phugetlb, 'a', memsize);
		if (type & (1 << 2))
			memset(pthp, 'a', memsize);
		if (type & (1 << 3))
			memset(pfile1, 'a', memsize);
		if (type & (1 << 4))
			memset(phugetlbfile1, 'a', memsize);
		if (type & (1 << 5))
			memset(phugetlbfile2, 'a', memsize);
		if (type & (1 << 6))
			memset(pshmhugetlb, 'a', memsize);
		if (type & (1 << 7))
			memset(pfile2, 'a', memsize);
		if (oneshot)
			flag = 0;
	}

	pprintf("mbind exit\n");
	if (type & (1 << 0))
		munmap(pmem, memsize);
	if (type & (1 << 1))
		munmap(phugetlb, memsize);
	if (type & (1 << 2))
		munmap(pthp, memsize);
	if (type & (1 << 3))
		munmap(pfile1, memsize);
	if (type & (1 << 4))
		munmap(phugetlbfile1, memsize);
	if (type & (1 << 5))
		munmap(phugetlbfile2, memsize);
	if (type & (1 << 6)) {
		munmap(pshmhugetlb, memsize);
		free_shm_hugepage(shmkey, pshmhugetlb);
	}
	if (type & (1 << 7))
		munmap(pfile2, memsize);
	return 0;
}
