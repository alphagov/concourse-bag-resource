/* Workaround for https://github.com/proot-me/proot/issues/173
 * because debian's proot is ancient.
 *
 * Originally from https://github.com/termux/proot/issues/62#issuecomment-493779880
 */

#define prctl prctl_from_header
#define _GNU_SOURCE
#include <sys/prctl.h>
#include <dlfcn.h>
#undef prctl

int prctl(int option, unsigned long arg2, unsigned long arg3,
		 unsigned long arg4, unsigned long arg5)
{
	if (option == PR_SET_DUMPABLE) {
		return 0;
	}
	int (*real_prctl)(int, unsigned long, unsigned long, unsigned long, unsigned long);
	real_prctl = dlsym(RTLD_NEXT, "prctl");
	return real_prctl(option, arg2, arg3, arg4, arg5);
}
