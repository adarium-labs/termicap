/* termicap_sigwinch.c -- C signal trampoline for SIGWINCH handling
 *
 * This file provides the SIGWINCH signal handler and associated C-side state.
 * All signal-handler operations are async-signal-safe (ioctl, write, volatile
 * sig_atomic_t writes).  The Ada protected object reads state via the query
 * functions below.
 *
 * Copyright (c) 2026 Termicap Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#if defined(__unix__) || defined(__APPLE__)

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <unistd.h>

/* Previous signal disposition, saved at install time for faithful restoration
 * (FUNC-SWC-006). */
static struct sigaction old_action;

/* Terminal FD used for ioctl re-queries from the signal handler. */
static int registered_fd = 1;

/* Write end of the self-pipe; -1 when not installed (FUNC-SWC-004). */
static int pipe_write_fd = -1;

/* Volatile state updated by the signal handler and read by Ada query functions.
 * sig_atomic_t guarantees atomic reads/writes on the pending flag.
 * unsigned short matches ws_col/ws_row/ws_xpixel/ws_ypixel in struct winsize. */
static volatile sig_atomic_t resize_pending = 0;
static volatile unsigned short cached_cols   = 80;
static volatile unsigned short cached_rows   = 24;
static volatile unsigned short cached_xpixel = 0;
static volatile unsigned short cached_ypixel = 0;

/* Signal handler -- only async-signal-safe operations (POSIX.1-2008 Table 2-1):
 *   ioctl, write, volatile writes, errno save/restore.                        */
static void sigwinch_handler(int sig)
{
    struct winsize ws;
    (void)sig;

    /* Re-query terminal dimensions; retain cached values on ioctl failure
     * (FUNC-SWC-002). */
    if (ioctl(registered_fd, TIOCGWINSZ, &ws) == 0) {
        cached_cols   = ws.ws_col;
        cached_rows   = ws.ws_row;
        cached_xpixel = ws.ws_xpixel;
        cached_ypixel = ws.ws_ypixel;
    }

    /* Set the pending flag (FUNC-SWC-003). */
    resize_pending = 1;

    /* Write one byte to the self-pipe (FUNC-SWC-004).
     * Save/restore errno so the interrupted code sees its own errno value.
     * Ignore EAGAIN: pipe already has unread bytes, FD is already readable. */
    if (pipe_write_fd >= 0) {
        int saved_errno = errno;
        char byte = 1;
        (void)write(pipe_write_fd, &byte, 1);
        errno = saved_errno;
    }
}

/* Install the SIGWINCH handler using sigaction so the previous disposition is
 * saved for restoration (FUNC-SWC-006).  Also performs the initial ioctl query
 * so the cached size is valid immediately after install (FUNC-SWC-010).
 * Returns 0 on success, -1 on error.                                          */
int termicap_sigwinch_install(int fd, int write_fd)
{
    struct sigaction sa;
    struct winsize   ws;

    registered_fd = fd;
    pipe_write_fd = write_fd;
    resize_pending = 0;

    /* Initial dimension query at install time (FUNC-SWC-010). */
    if (ioctl(fd, TIOCGWINSZ, &ws) == 0) {
        cached_cols   = ws.ws_col;
        cached_rows   = ws.ws_row;
        cached_xpixel = ws.ws_xpixel;
        cached_ypixel = ws.ws_ypixel;
    } else {
        cached_cols   = 80;
        cached_rows   = 24;
        cached_xpixel = 0;
        cached_ypixel = 0;
    }

    sa.sa_handler = sigwinch_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;

    return sigaction(SIGWINCH, &sa, &old_action);
}

/* Restore the previous SIGWINCH disposition saved at install time (FUNC-SWC-006).
 * Resets all C-side state to safe defaults.
 * Returns 0 on success, -1 on error.                                          */
int termicap_sigwinch_restore(void)
{
    int result;

    pipe_write_fd  = -1;
    resize_pending = 0;
    cached_cols    = 80;
    cached_rows    = 24;
    cached_xpixel  = 0;
    cached_ypixel  = 0;

    result = sigaction(SIGWINCH, &old_action, NULL);
    return result;
}

/* Return 1 if a resize is pending, 0 otherwise (FUNC-SWC-003). */
int termicap_sigwinch_pending(void)
{
    return (int)resize_pending;
}

/* Clear the resize-pending flag (FUNC-SWC-003). */
void termicap_sigwinch_acknowledge(void)
{
    resize_pending = 0;
}

/* Copy the most recently cached terminal dimensions into the caller's pointers.
 * All reads are from volatile storage; no locking required because the Ada
 * protected object serialises calls to this function (FUNC-SWC-002, FUNC-SWC-010). */
void termicap_sigwinch_get_size(unsigned short *cols,
                                unsigned short *rows,
                                unsigned short *xpixel,
                                unsigned short *ypixel)
{
    *cols   = cached_cols;
    *rows   = cached_rows;
    *xpixel = cached_xpixel;
    *ypixel = cached_ypixel;
}

/* Set O_NONBLOCK on the given file descriptor.
 * Keeps O_NONBLOCK's numeric value inside the C layer where <fcntl.h> guarantees
 * the correct per-platform constant (Linux=2048, Darwin/BSD=4, ...).
 * Returns 0 on success, -1 on error.                                          */
int termicap_set_nonblock(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        return -1;
    }
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

#endif /* __unix__ || __APPLE__ */
