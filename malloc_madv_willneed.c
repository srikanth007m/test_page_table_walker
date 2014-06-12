#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/mman.h>

void sig_handle(int signo) { ; }

int main(int argc, char *argv[])
{
	int size = 2097152;
	int ret;
	void *p;

	if (argc > 1)
		size = strtol(argv[1], NULL, 0);
	ret = posix_memalign(&p, getpagesize(), size);
	if (ret != 0) {
		perror("posix_memalign");
		return 1;
	}
	/* should cause swap out by external configuration */
	memset(p, 'a', size);
	signal(SIGUSR1, sig_handle);
	pause();
	printf("call madvise(MADV_WILLNEED)\n");
	ret = madvise(p, size, MADV_WILLNEED);
	if (ret == -1) {
		perror("madvise");
		return 1;
	}
	pause();
	return 0;
}
