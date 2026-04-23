/* termicap_osc.c -- C helpers for OSC probe session terminal I/O
 *
 * Provides fixed-signature wrappers for termios, select, and ioctl
 * operations that cannot be imported directly from Ada.
 *
 * Copyright (c) 2026 Termicap Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#if defined(__unix__) || defined(__APPLE__)

#include <errno.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>

/* termicap_osc_open_tty -- open /dev/tty for direct terminal I/O.
 * Returns the file descriptor on success, -1 on failure.             */
int termicap_osc_open_tty(void)
{
    /* open(2) with O_RDWR only -- no mode argument required.
     * Using a fixed-signature wrapper avoids the variadic open() signature. */
    extern int open(const char *, int, ...);
    return open("/dev/tty", 2);  /* O_RDWR = 2 on POSIX */
}

/* termicap_osc_close_fd -- close a file descriptor.
 * Returns 0 on success, -1 on failure.                               */
int termicap_osc_close_fd(int fd)
{
    return close(fd);
}

/* termicap_osc_save_termios -- save the current termios state.
 *
 * Calls tcgetattr(fd, &t), then copies sizeof(struct termios) bytes
 * into buf.  Sets *actual_size to sizeof(struct termios).
 * Returns 0 on success, -1 if buf_size is too small or tcgetattr fails. */
int termicap_osc_save_termios(int fd, void *buf, int buf_size, int *actual_size)
{
    struct termios t;

    if (buf_size < (int)sizeof(struct termios)) {
        return -1;
    }

    if (tcgetattr(fd, &t) != 0) {
        return -1;
    }

    memcpy(buf, &t, sizeof(struct termios));
    *actual_size = (int)sizeof(struct termios);
    return 0;
}

/* termicap_osc_restore_termios -- restore a previously saved termios state.
 *
 * Copies size bytes from buf into a struct termios, then applies it via
 * tcsetattr(fd, TCSANOW, &t).
 * Returns 0 on success, -1 on failure.                               */
int termicap_osc_restore_termios(int fd, const void *buf, int size)
{
    struct termios t;

    if (size < (int)sizeof(struct termios)) {
        return -1;
    }

    memcpy(&t, buf, sizeof(struct termios));
    return tcsetattr(fd, TCSANOW, &t);
}

/* termicap_osc_set_raw -- switch a terminal to raw mode.
 *
 * Copies the saved termios from saved_buf, then clears ICANON, ECHO, ISIG
 * from c_lflag and IXON, ICRNL, BRKINT from c_iflag, sets VMIN=0 and
 * VTIME=0, and applies the result via tcsetattr(fd, TCSANOW, &raw).
 * Returns 0 on success, -1 on failure.                               */
int termicap_osc_set_raw(int fd, const void *saved_buf, int size)
{
    struct termios raw;

    if (size < (int)sizeof(struct termios)) {
        return -1;
    }

    memcpy(&raw, saved_buf, sizeof(struct termios));

    /* Clear echo and canonical mode flags from c_lflag. */
    raw.c_lflag &= ~(tcflag_t)(ICANON | ECHO | ISIG);

    /* Clear flow-control and newline translation flags from c_iflag. */
    raw.c_iflag &= ~(tcflag_t)(IXON | ICRNL | BRKINT);

    /* Non-blocking character-at-a-time reads: VMIN=0, VTIME=0. */
    raw.c_cc[VMIN]  = 0;
    raw.c_cc[VTIME] = 0;

    return tcsetattr(fd, TCSANOW, &raw);
}

/* termicap_osc_timed_read -- select() + read() with millisecond timeout.
 *
 * Waits up to timeout_ms milliseconds for fd to become readable using
 * select().  If readable, calls read() into buf.
 *
 * On return:
 *   *bytes_read  -- number of bytes placed in buf (0 on timeout or error)
 *   *timed_out   -- 1 if select() returned 0 (no data within timeout), else 0
 *
 * Returns 0 on success (including a clean timeout), -1 on select() or
 * read() error.                                                        */
int termicap_osc_timed_read(int fd, void *buf, int buf_size,
                             int timeout_ms, int *bytes_read, int *timed_out)
{
    fd_set rfds;
    struct timeval tv;
    int sel;
    ssize_t n;

    *bytes_read = 0;
    *timed_out  = 0;

    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);

    tv.tv_sec  = (long)(timeout_ms / 1000);
    tv.tv_usec = (long)((timeout_ms % 1000) * 1000);

    sel = select(fd + 1, &rfds, NULL, NULL, &tv);

    if (sel < 0) {
        return -1;  /* select() error */
    }

    if (sel == 0) {
        *timed_out = 1;
        return 0;   /* timeout, not an error */
    }

    /* FD is readable -- perform the read. */
    n = read(fd, buf, (size_t)buf_size);
    if (n < 0) {
        return -1;  /* read() error */
    }

    *bytes_read = (int)n;
    return 0;
}

/* termicap_osc_write -- write bytes to a file descriptor.
 *
 * Calls write(fd, buf, len).  Sets *written to the number of bytes
 * actually written.
 * Returns 0 on success, -1 on write() error.                         */
int termicap_osc_write(int fd, const void *buf, int len, int *written)
{
    ssize_t n;

    *written = 0;

    n = write(fd, buf, (size_t)len);
    if (n < 0) {
        return -1;
    }

    *written = (int)n;
    return 0;
}

/* termicap_osc_is_foreground -- check if the calling process is in the
 * terminal's foreground process group.
 *
 * Calls ioctl(fd, TIOCGPGRP, &pgrp) to obtain the terminal's foreground
 * process group, then compares with getpgrp().
 * Returns 1 if equal (foreground), 0 on ioctl failure or if in background. */
int termicap_osc_is_foreground(int fd)
{
    pid_t fg_pgrp;
    pid_t my_pgrp;

    if (ioctl(fd, TIOCGPGRP, &fg_pgrp) != 0) {
        return 0;
    }

    my_pgrp = getpgrp();
    return (fg_pgrp == my_pgrp) ? 1 : 0;
}

/* termicap_osc_termios_size -- return sizeof(struct termios) on this platform.
 * Used by Ada to verify the opaque buffer is large enough.            */
int termicap_osc_termios_size(void)
{
    return (int)sizeof(struct termios);
}

#endif /* __unix__ || __APPLE__ */
