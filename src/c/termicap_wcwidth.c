/*
 * termicap_wcwidth.c - Portable LC_CTYPE constant helper
 *
 * Copyright (c) 2026 Termicap Contributors
 * SPDX-License-Identifier: Apache-2.0
 *
 * Returns the platform-specific numeric value of LC_CTYPE so that Ada
 * code can call setlocale(LC_CTYPE, NULL) portably without hardcoding
 * the value (0 on Linux/glibc, 2 on macOS/FreeBSD).
 *
 * Requirements Coverage:
 *   FUNC-WCW-006: Portable LC_CTYPE value for locale guard
 */

#include <locale.h>

int termicap_lc_ctype (void)
{
   return LC_CTYPE;
}
