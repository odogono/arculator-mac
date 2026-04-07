#ifndef MACOS_UTIL_H
#define MACOS_UTIL_H

#import <dispatch/dispatch.h>
#import <Foundation/NSThread.h>

static inline void run_on_main_thread(void (^block)(void))
{
	if ([NSThread isMainThread])
	{
		block();
		return;
	}

	dispatch_sync(dispatch_get_main_queue(), block);
}

#endif
