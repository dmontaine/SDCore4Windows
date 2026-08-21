/* win32peer.h - see win32peer.c.  No Windows types cross this interface. */
#ifndef PEER_PROBE_WIN32_H
#define PEER_PROBE_WIN32_H
unsigned long win32_peer_pid(unsigned short our_port, unsigned short peer_port);
int win32_pid_user(unsigned long pid, char* out, int outlen);
#endif
