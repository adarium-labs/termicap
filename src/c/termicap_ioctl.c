/* termicap_ioctl.c -- Thin C wrapper for ioctl(TIOCGWINSZ)
 *
 * ioctl is variadic (int ioctl(int, unsigned long, ...)), so Ada cannot
 * import it directly.  This wrapper provides a fixed-signature function
 * that Ada can bind via pragma Import.
 *
 * Copyright (c) 2026 Termicap Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <sys/ioctl.h>

int termicap_get_winsize(int fd,
                         unsigned short *cols,
                         unsigned short *rows,
                         unsigned short *xpixel,
                         unsigned short *ypixel)
{
    struct winsize ws;
    int result = ioctl(fd, TIOCGWINSZ, &ws);
    if (result < 0) {
        return -1;
    }
    *cols   = ws.ws_col;
    *rows   = ws.ws_row;
    *xpixel = ws.ws_xpixel;
    *ypixel = ws.ws_ypixel;
    return 0;
}
