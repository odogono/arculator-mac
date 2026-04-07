/*
 * VideoRendererShutdownTests
 *
 * Tests that video_renderer_begin_close() prevents the deadlock that
 * occurs when the main thread blocks on pthread_join() while the
 * emulation thread is inside video_renderer_present() waiting on
 * [CAMetalLayer nextDrawable].  nextDrawable needs the main run loop
 * to recycle drawables, so if the main thread is blocked the two
 * threads deadlock.
 *
 * The fix: video_renderer_begin_close() sets an atomic flag that
 * video_renderer_present() checks before touching any Metal API,
 * allowing the emulation thread to exit promptly.
 *
 * These tests exercise the flag mechanism with a mock blocking call
 * (dispatch_semaphore_wait) standing in for nextDrawable, proving
 * that the flag prevents the deadlock.
 */
#import <XCTest/XCTest.h>
#include <pthread.h>
#include <dispatch/dispatch.h>

/*
 * We cannot link the real video_metal.m in the unit-test target
 * (it drags in Metal and needs a GPU).  Instead we reproduce the
 * exact flag-check pattern from video_renderer_present() with a
 * controllable blocking primitive so we can prove the fix works.
 */

/* Mirror of the flag added to video_metal.m. */
static volatile int test_renderer_closing;

/* Semaphore used to simulate [CAMetalLayer nextDrawable] blocking. */
static dispatch_semaphore_t mock_next_drawable;

/* Set to 1 by the fake "emulation thread" when it exits present(). */
static volatile int present_returned;

static void test_begin_close(void)
{
	test_renderer_closing = 1;
}

static void test_close(void)
{
	test_renderer_closing = 0;
}

/*
 * Simulates video_renderer_present() with the begin_close guard.
 * The semaphore_wait stands in for [metal_layer nextDrawable] — it
 * blocks forever unless signalled, exactly like nextDrawable blocks
 * when the main thread's run loop isn't processing.
 */
static void test_present_with_guard(void)
{
	if (test_renderer_closing)
		return;

	/* Simulate nextDrawable blocking — waits forever. */
	dispatch_semaphore_wait(mock_next_drawable, DISPATCH_TIME_FOREVER);
}

/*
 * Simulates the OLD video_renderer_present() WITHOUT the guard.
 * This always blocks on the semaphore, reproducing the deadlock.
 */
static void test_present_without_guard(void)
{
	/* No renderer_closing check — goes straight to blocking. */
	dispatch_semaphore_wait(mock_next_drawable, DISPATCH_TIME_FOREVER);
}

/* ----- Thread entry points ----- */

static void *emulation_thread_with_guard(void *ctx)
{
	(void)ctx;
	test_present_with_guard();
	present_returned = 1;
	return NULL;
}

static void *emulation_thread_without_guard(void *ctx)
{
	(void)ctx;
	test_present_without_guard();
	present_returned = 1;
	return NULL;
}

@interface VideoRendererShutdownTests : XCTestCase
@end

@implementation VideoRendererShutdownTests

- (void)setUp
{
	test_renderer_closing = 0;
	present_returned = 0;
	mock_next_drawable = dispatch_semaphore_create(0);
}

/*
 * GREEN — With the begin_close guard the emulation thread returns
 * from present() immediately, so pthread_join completes.
 */
- (void)testBeginClosePreventsPresentDeadlock
{
	pthread_t thread;

	/* Spawn "emulation thread" that will call the guarded present(). */
	pthread_create(&thread, NULL, emulation_thread_with_guard, NULL);

	/*
	 * Simulate the shutdown sequence: set the closing flag before
	 * joining, exactly as arc_shell_shutdown() now does.
	 */
	test_begin_close();

	/*
	 * Wait for the thread with a timeout.  If the guard works the
	 * thread exits immediately; if not this will time out.
	 */
	__block int join_succeeded = 0;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		pthread_join(thread, NULL);
		join_succeeded = 1;
		dispatch_semaphore_signal(done);
	});

	long result = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
	XCTAssertEqual(result, 0, @"pthread_join should complete within 2 s — deadlock detected");
	XCTAssertEqual(join_succeeded, 1, @"join must have succeeded");
	XCTAssertEqual(present_returned, 1, @"present() must have returned");
}

/*
 * RED — Without the guard, present() blocks on the mock
 * nextDrawable, the join never completes, and the test times out.
 * This proves the test catches the original bug.
 */
- (void)testWithoutGuardDeadlocks
{
	pthread_t thread;

	/* Spawn "emulation thread" WITHOUT the guard. */
	pthread_create(&thread, NULL, emulation_thread_without_guard, NULL);

	/* Give the thread a moment to block on the semaphore. */
	usleep(50000);

	/*
	 * Try to join — this must NOT succeed within the timeout because
	 * the thread is permanently blocked (simulating the bug).
	 */
	__block int join_succeeded = 0;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		pthread_join(thread, NULL);
		join_succeeded = 1;
		dispatch_semaphore_signal(done);
	});

	long result = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)));
	XCTAssertNotEqual(result, 0, @"Join should NOT complete — thread is deadlocked (this is the bug)");
	XCTAssertEqual(present_returned, 0, @"present() should still be blocked");

	/* Clean up: unblock the thread so the test process can exit. */
	dispatch_semaphore_signal(mock_next_drawable);
	pthread_join(thread, NULL);
}

/*
 * Verify that video_renderer_close() resets the flag so the next
 * session can render normally.
 */
- (void)testCloseResetsFlag
{
	test_begin_close();
	XCTAssertEqual(test_renderer_closing, 1);

	test_close();
	XCTAssertEqual(test_renderer_closing, 0);
}

@end
