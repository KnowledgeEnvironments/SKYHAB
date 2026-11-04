/*
 * skyHAB Project <src@lispm.net>
 * Copyright (c) 2026 I. Finder
 * SPDX-License-Identifier: MIT
 *
 * Minimal SkyWire/1 message encoder suitable for classic and vintage C clients.
 */
#include <stdio.h>
#include <string.h>

static int token(char *out, size_t capacity, const char *value) {
    int n = snprintf(out, capacity, "%lu:%s,", (unsigned long)strlen(value), value);
    return n < 0 || (size_t)n >= capacity ? -1 : n;
}

int main(void) {
    const char *parts[] = {"Q", "1", "PING"};
    char payload[128], message[160];
    size_t used = 0, i;
    for (i = 0; i < sizeof(parts) / sizeof(parts[0]); ++i) {
        int n = token(payload + used, sizeof(payload) - used, parts[i]);
        if (n < 0) return 1;
        used += (size_t)n;
    }
    if (snprintf(message, sizeof(message), "%lu:%s,", (unsigned long)used, payload) < 0) return 1;
    fwrite(message, 1, strlen(message), stdout);
    return 0;
}
