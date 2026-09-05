/* Modifications Copyright (c) 2026 Donald Montaine
 *
 * This library is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
 * General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <https://www.gnu.org/licenses/>.
 *
 * Linking exception (additional permission under GNU LGPL version 3
 * section 7): as a special exception, the copyright holders give you
 * permission to link this library with independent modules to produce an
 * executable, regardless of the license terms of these independent modules,
 * and to copy and distribute the resulting executable under terms of your
 * choice, provided that you also meet, for each linked independent module,
 * the terms and conditions of the license of that module.  An independent
 * module is a module which is not derived from or based on this library.
 */

/* sd_connect.c - why the connection failed, in the library's own words.
 *
 * An application that reports "cannot connect" has thrown away the only
 * useful part of the failure.  QMError() distinguishes a name that will not
 * resolve, a port with nothing behind it, a server that accepts the socket
 * and then hangs up, and a login the server rejected - four different
 * problems with four different fixes, none of which is "cannot connect".
 *
 * Run with a host and port for the transport half, which needs no
 * credentials:
 *
 *     sd-connect.exe 10.0.0.5 4243
 *
 * Add credentials for the whole thing:
 *
 *     sd-connect.exe 10.0.0.5 4243 user password ACCOUNT
 *
 * The transport half deliberately repeats what OpenSocket() in sdclilib.c
 * does - dotted quad through inet_addr, anything else through
 * gethostbyname, then connect, then read the ACK - so that it fails where the
 * library fails, for the same reason.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <winsock2.h>
#include "qmclilib.h"

#define SD_ACK '\x06'

/* What the number means, for the handful that actually come up here.  Winsock
   codes are not in errno order and nothing on the machine will explain them
   at the point of failure. */
static const char* winsock_meaning(int err) {
    switch (err) {
        case 10060: return "timed out - a firewall dropping the packets, "
                           "or the wrong address entirely";
        case 10061: return "refused - the address is right and nothing is "
                           "listening on that port";
        case 10064: return "host is down";
        case 10065: return "no route to host";
        case 11001: return "host not found - the name does not resolve";
        default:    return NULL;
    }
}

static void report_winsock(const char* what, int err) {
    const char* meaning = winsock_meaning(err);
    if (meaning != NULL)
        printf("  FAILED  %s: Winsock error %d, %s\n", what, err, meaning);
    else
        printf("  FAILED  %s: Winsock error %d\n", what, err);
}

/* Returns 0 if the server completed the handshake, non-zero otherwise. */
static int transport_probe(const char* host, int port) {
    WSADATA wsadata;
    SOCKET sock;
    struct sockaddr_in addr;
    struct hostent* hostdata;
    unsigned long ip;
    unsigned int n1, n2, n3, n4;
    DWORD timeout = 5000;
    char ack;
    int n;

    if (WSAStartup(MAKEWORD(2, 2), &wsadata) != 0) {
        printf("  FAILED  WSAStartup\n");
        return 1;
    }

    if ((sscanf(host, "%u.%u.%u.%u", &n1, &n2, &n3, &n4) == 4) && (n1 <= 255) &&
        (n2 <= 255) && (n3 <= 255) && (n4 <= 255)) {
        ip = inet_addr(host);
        printf("  ok      address %s\n", host);
    } else {
        hostdata = gethostbyname(host);
        if (hostdata == NULL) {
            report_winsock("gethostbyname()", WSAGetLastError());
            WSACleanup();
            return 1;
        }
        memcpy(&ip, hostdata->h_addr, sizeof(ip));
        printf("  ok      %s resolves to %s\n", host,
               inet_ntoa(*(struct in_addr*)&ip));
    }

    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock == INVALID_SOCKET) {
        report_winsock("socket()", WSAGetLastError());
        WSACleanup();
        return 1;
    }

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = ip;
    addr.sin_port = htons((unsigned short)port);

    printf("  ...     connecting to port %d\n", port);
    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        report_winsock("connect()", WSAGetLastError());
        printf("\n  Nothing is answering on that port.  Check that the SD\n"
               "  server is running, that the sdclient service is registered\n"
               "  with inetd/xinetd on port %d, and that the port is open.\n",
               port);
        closesocket(sock);
        WSACleanup();
        return 1;
    }
    printf("  ok      TCP connection established\n");

    /* The server sends ACK once it is ready to talk.  Without the timeout a
       server that accepts and then says nothing would hang here rather than
       report anything. */
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const char*)&timeout,
               sizeof(timeout));
    n = recv(sock, &ack, 1, 0);
    if (n == 0) {
        printf("  FAILED  server closed the connection without sending ACK\n");
        printf("\n  The port is open but the service behind it did not talk.\n"
               "  That is the signature of a misconfigured sdclient entry -\n"
               "  wrong program path, wrong user, or the server refusing the\n"
               "  connection before the protocol starts.  The server's own\n"
               "  log will say which.\n");
    } else if (n == SOCKET_ERROR) {
        int err = WSAGetLastError();
        if (err == WSAETIMEDOUT)
            printf("  FAILED  no ACK within 5 seconds - connection accepted, "
                   "server silent\n");
        else
            report_winsock("recv()", err);
    } else if (ack != SD_ACK) {
        printf("  FAILED  first byte was 0x%02x, expected ACK (0x06)\n",
               (unsigned char)ack);
        printf("\n  Something is listening, but it is not an SD server.\n");
    } else {
        printf("  ok      server sent ACK - the transport is fine\n");
        closesocket(sock);
        WSACleanup();
        return 0;
    }

    closesocket(sock);
    WSACleanup();
    return 1;
}

int main(int argc, char* argv[]) {
    const char* host;
    int port;
    int transport_ok;

    if (argc != 3 && argc != 6) {
        fprintf(stderr,
                "usage: %s <host> <port>\n"
                "       %s <host> <port> <user> <password> <account>\n\n"
                "  Two arguments test the transport only, and need no\n"
                "  credentials.  Five test the whole login.  4243 is the\n"
                "  SD default port.\n",
                argv[0], argv[0]);
        return 2;
    }

    host = argv[1];
    port = atoi(argv[2]);

    printf("Transport\n");
    transport_ok = (transport_probe(host, port) == 0);

    if (argc == 3) {
        printf("\nNo credentials given, so the login was not tested.\n");
        return transport_ok ? 0 : 1;
    }

    printf("\nQMConnect\n");
    if (QMConnect((char*)host, port, argv[3], argv[4], argv[5])) {
        printf("  ok      connected to account %s\n", argv[5]);
        QMDisconnect();
        return 0;
    }

    printf("  FAILED  QMError(): %s\n", QMError());
    if (transport_ok)
        printf("\n  The transport worked, so this is the server rejecting the\n"
               "  login or the account: check the user name, the password, and\n"
               "  that the account exists and that user may reach it.\n");
    return 1;
}
