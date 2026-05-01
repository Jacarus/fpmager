/*
 * fly_bind.c — LD_PRELOAD shim for fly.io IPv6→IPv4 socket downgrade.
 *
 * Godot/ENet on Linux creates AF_INET6 sockets and calls bind() with a
 * sockaddr_in6. Because the machine may not have IPv6 dual-stack set up
 * correctly for the game port, we intercept socket() and force AF_INET,
 * then convert the subsequent bind(:::port) to bind(0.0.0.0:port).
 *
 * Source IP rewriting (0.0.0.0 → fly-global-services) is handled by an
 * iptables POSTROUTING SNAT rule set up before the server starts.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <stdio.h>
#include <inttypes.h>

#define GAME_PORT 24567

static int (*real_socket)(int, int, int) = NULL;
static int (*real_bind)(int, const struct sockaddr *, socklen_t) = NULL;

static void init_real(void) {
    if (!real_socket)
        real_socket = dlsym(RTLD_NEXT, "socket");
    if (!real_bind)
        real_bind = dlsym(RTLD_NEXT, "bind");
}

/* Force IPv6 UDP sockets to IPv4 so ENet stays on the SNATted IPv4 path. */
int socket(int domain, int type, int protocol) {
    init_real();
    if (domain == AF_INET6 && (type & SOCK_DGRAM)) {
        fprintf(stderr, "[fly_bind] socket(AF_INET6, SOCK_DGRAM) → AF_INET\n");
        domain = AF_INET;
    }
    return real_socket(domain, type, protocol);
}

/*
 * Convert bind(AF_INET6 wildcard : GAME_PORT) → bind(0.0.0.0 : GAME_PORT).
 * The socket was forced to AF_INET above, so ENet still passes sockaddr_in6;
 * we rewrite it to sockaddr_in with INADDR_ANY so the kernel accepts it.
 * Source IP is handled externally by iptables POSTROUTING SNAT.
 */
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    init_real();

    if (addr && addr->sa_family == AF_INET6) {
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)addr;
        uint16_t port = ntohs(in6->sin6_port);
        if (port == GAME_PORT) {
            struct sockaddr_in in4 = {0};
            in4.sin_family = AF_INET;
            in4.sin_port   = in6->sin6_port;
            in4.sin_addr.s_addr = INADDR_ANY;
            fprintf(stderr, "[fly_bind] bind(:::%" PRIu16 ") → bind(0.0.0.0:%" PRIu16 ")\n",
                    port, port);
            return real_bind(sockfd, (const struct sockaddr *)&in4, sizeof(in4));
        }
    }

    return real_bind(sockfd, addr, addrlen);
}
