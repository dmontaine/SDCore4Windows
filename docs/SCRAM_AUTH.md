# SCRAM authentication for the SD API

Scoped 19 Aug 2026, accepted by the repository owner the same day. Replaces the
cleartext `SrvrLogin` exchange and the `!CRED_VERIFY` password comparison it
depends on.

**Status.** Phases 1 to 4 are complete and verified — the primitives against
the RFC 7677 vectors in C, BASIC **and now the client's own Windows crypto**;
`$CRED` version 2 end to end; the server exchange proved by
`gplbld/verify-scramlogin.ps1` **24/24**; and the client exchange proved
end to end by `gplbld/verify-apiport.ps1` on the 21:43:02 install of
19 Aug 2026 — right password admitted, wrong password refused, `SDSYS`
refused. Phases 5 and 6 are not started.

**`SrvrLogin` is no longer sent by this client, and no longer served.**
Phase 5 retired request 24 on 20 Aug 2026; what follows described the plan and
remains the only point of no return.

**The exchange below is no longer a specification; it is what runs.** The
server signature, the nonce freshness, the replay refusal and the absence of
the password from the wire were each measured rather than reasoned about.

**The structural fact this document exists to record:**

> **The API is the one door SD cannot secure with the operating system.** A
> console session is a process Windows started with the user's token, so
> `LOGIN` needs no password. An API connection is bytes arriving on a loopback
> port from any local process, carrying no identity at all — `getpeereid()` has
> no Windows equivalent and `peer_usr_id` is deliberately left unassigned
> (PROJECT_STATUS.md §7 step 6). The credential *is* the identity here, which is
> why it has to be a good one.

Today that credential crosses the wire in clear and is compared against an
Argon2 verifier. SCRAM removes the first half entirely and re-shapes the second.

## What it buys, and what it does not

The password stops existing on the wire. SCRAM is a challenge–response: the
client proves knowledge of the password by answering a nonce, and the password
itself is never transmitted in any form. A capture of the whole exchange yields
an offline guessing attack bounded by the key-derivation cost, and nothing else.

Replay dies with it — every exchange is bound to a fresh client nonce and a
fresh server nonce.

**And authentication becomes mutual**, which is the part easily overlooked. The
server closes by returning a signature only the holder of that account's
`ServerKey` can compute. A rogue process that takes port 4243 before SD starts
cannot harvest credentials by impersonating the server: it can collect a proof
it cannot use, and it cannot produce the closing signature, so the client
detects it and fails.

Three things it does **not** fix, recorded so they are not later mistaken for
oversights:

- **No channel binding without TLS.** SCRAM protects the credential, not the
  session. An attacker able to modify traffic cannot learn the password or
  replay the login, but can relay the handshake and ride the authenticated
  connection. Over loopback or inside an SSH tunnel this is moot; for direct
  remote TCP it is not. The fix is TLS plus `SCRAM-SHA-256-PLUS`.
- **The password still sits in the client application's configuration.** A
  third-party application hands a cleartext password to `QMConnect` and must
  keep one somewhere. Only SSPI removes that, and SSPI needs a domain.
- **There is still no lockout.** A failed login sleeps three seconds and that is
  the whole brake.

## The decision that shapes everything: PBKDF2, not Argon2

SCRAM derives everything from `SaltedPassword = KDF(password, salt, cost)`, and
**both sides must compute it**. That single choice fixes the client's
dependencies, the strength of the stored verifier, and whether a future client
in another language is three lines or a package hunt. It is also the only
decision here that is hard to reverse, because it is baked into every stored
credential.

**The KDF is PBKDF2-HMAC-SHA256 at 600,000 iterations**, giving standard
`SCRAM-SHA-256` exactly as RFC 7677 specifies it.

Argon2id was the tempting alternative — it is what `$CRED` uses today, the
server side already works, and it is materially better against offline cracking
of a stolen credential file. It was rejected on a constraint rather than a
preference:

> **A KDF's cost is set by the weakest client that must run it, and the weakest
> client here is a shipping deliverable.** mvDeveloper, the free 32-bit editor
> intended to ship with SD for Windows, is an API client. libsodium's
> interactive Argon2 preset wants 64 MB per connection, moderate 256 MB and
> sensitive a gigabyte — which a 32-bit process with a 2 GB address space
> cannot reliably allocate. The memory-hardness that justifies Argon2 would have
> to be turned down to roughly the point where it stops being the reason to
> choose it, on the platform that matters most.

PBKDF2 has no memory term, so the cost knob stays free. It also costs the client
nothing in dependencies: `BCryptDeriveKeyPBKDF2` is in `bcrypt.dll`, part of
Windows, so `qmclilib.dll` remains a single file copied next to the application.

**Store the iteration count in each credential record, not in configuration.**
Raising the cost later then applies to new passwords without invalidating old
ones.

The price is real and is accepted: PBKDF2 is weaker than Argon2id against GPU
cracking at equal wall-clock. The `$CRED` ACL (PROJECT_STATUS.md §7 step 6)
remains the primary protection for the credential file, exactly as it is now.

## The exchange

Two new request types carry it. The highest currently defined is
`SrvrMarkMapping` 46, so 47 and 48 are free. Both use the existing packet header
— length, error, status — with the SCRAM message as the body.

| | Message |
| --- | --- |
| **47 →** | `n,,n=<user>,r=<client-nonce>` |
| **← 47** | `r=<client-nonce><server-nonce>,s=<salt>,i=<iterations>` |
| **48 →** | `c=biws,r=<combined-nonce>,p=<ClientProof>` |
| **← 48** | `v=<ServerSignature>` |

`n,,` declares no channel binding; `biws` is its base64, echoed back so it
cannot be stripped. The client nonce is 18 random bytes. The client must check
that its own nonce is a prefix of the combined nonce — that is what stops a
replayed server response.

```
SaltedPassword  = PBKDF2-HMAC-SHA256(password, salt, i, 32)
ClientKey       = HMAC-SHA256(SaltedPassword, "Client Key")
StoredKey       = SHA256(ClientKey)
ServerKey       = HMAC-SHA256(SaltedPassword, "Server Key")

AuthMessage     = client-first-bare + "," + server-first + "," + client-final-without-proof
ClientSignature = HMAC-SHA256(StoredKey, AuthMessage)
ClientProof     = ClientKey XOR ClientSignature
ServerSignature = HMAC-SHA256(ServerKey, AuthMessage)
```

The server stores only `salt`, `i`, `StoredKey` and `ServerKey`. It verifies by
recovering `ClientKey' = ClientProof XOR HMAC(StoredKey, AuthMessage)` and
checking `SHA256(ClientKey')` against `StoredKey`, **in constant time**.

Note what a stolen `$CRED` then yields: `StoredKey` alone does *not* let an
attacker authenticate as the client, because forming a proof needs `ClientKey`,
its SHA-256 preimage. It does let them impersonate the server. The ACL stays
exactly as important as it is now.

**The server does not run PBKDF2 at login.** It holds `StoredKey` directly, so
the expensive derivation happens only in `SET.PASSWORD`. Per-login server cost
is two HMACs and a hash.

## Server-side changes

| Component | Change | Notes |
| --- | --- | --- |
| `$CRED` record | **breaks** — new format | `CRED$VERIFIER` becomes `CRED$STOREDKEY` and `CRED$SERVERKEY`; add `CRED$VERSION`, `CRED$MECH`, `CRED$ITER`. No migration is possible — the plaintext is not stored, by design. |
| `SET.PASSWORD` | rewrite the derivation | Computes and writes the four new values. The verb, its argument handling and its administrator gate are unchanged. |
| `!CRED_VERIFY` | rewritten for v2 | **Corrected 19 Aug 2026.** This scope first said delete it, because SCRAM has no "verify this password" step and its only caller was said to be the login path. `SET_ACC_PASSWORD` calls it too — "changing your own password requires the current one" — and there the password genuinely is in hand, locally, in an elevated session. It keeps its signature and its callers; only what it reads changes, and the comparison moves to constant time. |
| `APISRVR` `vb.login` | replace with two handlers | Session state must hold the nonces, salt and `AuthMessage` between requests 47 and 48, and must abort if 48 arrives without 47. |
| Crypto helpers | new `SDEXT` keys 104–109 | SHA-256, HMAC-SHA256, PBKDF2, random bytes, XOR, constant-time compare — alongside the existing `SD_SALT` 100 and `SD_KEYFROMPW` 101. |
| `SrvrLogin` 24 | **breaks** — refuse | **Done, 20 Aug 2026.** No fallback. `vb.login` answers message 5275 and drops the connection. It stays in the pre-authentication gate so the reply can name the reason; dropping it there would answer 5270 "Not logged in" instead. |
| `SDCLIENT` class | **rewritten** | Not foreseen by this document. `!sdclient` is the BASIC-callable client and sent request 24, so phase 5 would have broken it silently — it is catalogued on every install, has no caller in this tree and had no test. It speaks SCRAM from 20 Aug 2026, is `$internal` because the derivation needs `SDEXT`, and is exercised by `sdsys/bp/TESTSDCLI`. |
| Group check (§7 step 6c) | unchanged | `ACC$GROUP` membership still gates account entry, reading the identity SCRAM established. |

### Keep binary out of BASIC strings

Every value here is binary: 32-byte keys, nonces, salts. SD BASIC strings are
delimited by mark characters — `0xFE`, `0xFD`, `0xFC` — and a 32-byte digest
contains one roughly one time in nine. A raw digest in a dynamic-array field
would corrupt field extraction, showing up as an occasional, irreproducible
login failure and nothing else.

So the helpers take and return **base64 throughout**, converting only inside C.
The existing bridge settles this rather than merely recommending it: `SDEXT`
passes arguments as NUL-terminated C strings and returns through
`k_put_c_string()`, so raw binary could not survive the round trip in any case.
`!SD_KEY_FROM_PW` already returns base64 for the same reason.

### Two key tables and two include paths

Both bit during phase 1 and phase 2, and both will bite again.

**The `SDEXT` key numbers live in two files that nothing cross-checks.**
`gplsrc/keys.h` for C and `sdsys/syscom/KEYS.H` for BASIC. Adding a key to one
and not the other gives six undeclared-identifier errors on the C side, or
`WARNING: SD_x is not assigned a value` on the BASIC side.

**Treat that warning as an error.** A `$define` that does not resolve becomes an
ordinary unassigned variable, so `SDEXT(..., SD_PBKDF2)` compiles cleanly,
reports "0 error(s)", catalogues, and calls `SDEXT` with a null key. Phase 2
catalogued two programs in exactly that state.

**`$include NAME` resolves against the source's own file, then syscom**
(`BCOMP:2990`). So `gpl.bp` programs find `INT$KEYS.H` as a sibling, and
programs in `bp` do not — they need the three-token form,
`$include gpl.bp INT$KEYS.H`. `KEYS.H` is in syscom and resolves from either.

**And the installed tree is a separate copy.** Editing the source tree changes
nothing until the file is copied to `C:\ProgramData\SD\sdsys`, and a stale
installed include fails in the silent way described above rather than by
reporting a missing file.

## Client-side changes

`QMConnect(host, port, user, password, account)` does not change — not its
arguments, not its return, not `QMError()`. Applications are unaffected and
unaware, which is what makes this viable for a third-party client such as
mvDeveloper whose source is not available.

Everything happens inside `sdclilib.c`. The primitives come from Windows
itself: `BCryptDeriveKeyPBKDF2`, `BCryptGenRandom` and HMAC-SHA256 via
`BCRYPT_ALG_HANDLE_HMAC_FLAG` in `bcrypt.dll`; base64 from
`CryptBinaryToStringA` in `crypt32.dll`, or inline. Both ship with Windows, so
the DLL stays a single file — the property the 32-bit build was already careful
to preserve.

**A missing or invalid `server-final` is a failed connection, not a success with
a warning.** That is the whole value of mutual authentication, and it is exactly
the check that gets softened during debugging and never hardened again.

## Order of work

1. Crypto helpers in C plus their BASIC wrappers, verified against the RFC 7677
   test vectors. Nothing else can be trusted until these are.
2. `$CRED` version 2 and the `SET.PASSWORD` rewrite. Verify by inspecting a
   written record — no login path involved yet.
3. Server handlers for 47 and 48, exercised by a throwaway client that speaks
   the exchange directly.
4. Client exchange in `sdclilib.c`, behind the unchanged entry points. Both DLLs
   build from this one source.
5. Retire `SrvrLogin`. **This is the point of no return for old clients.**
   **Done 20 Aug 2026**, together with the `!sdclient` class the plan had
   overlooked.
6. Rebuild the 64-bit and 32-bit DLLs, re-run `SET.PASSWORD` for every account,
   re-test against mvDeveloper. mvDeveloper passed on 19 Aug, ahead of the
   phase; what remains is the rebuild and the re-set.

Steps 1 to 3 are additive and reversible — the existing login keeps working
throughout. The break is deliberately concentrated in step 5, so it happens
once, knowingly, rather than leaking across the whole change.

## Compatibility with sdb64 is not a goal

This changes the wire protocol, so the Windows server stops talking to the Linux
client library and vice versa. That is intended. This port targets a Windows
server with Windows clients; the Linux line is separately maintained and has
forked the clients that work against it. Recorded here because it is the
assumption that removes the last argument for keeping a fallback path.

## Still open

None of it blocks the first three phases.

- **Password normalization.** RFC 5802 specifies SASLprep, which needs Unicode
  tables. The pragmatic alternative is to accept UTF-8 bytes as given and
  document that a non-ASCII password must be entered identically on both sides.
  Usernames are already constrained by `valid_os_name()`.
- **Lockout.** Cheap to add while the credential record is changing anyway, and
  currently absent entirely. A failure count and lockout timestamp in `$CRED`
  would close the one gap SCRAM leaves wide.
- **User enumeration, introduced by phase 3 and left there deliberately.** An
  account with no usable credential is refused at request 47; a wrong password
  is refused at 48. Same message, same three-second sleep, different round
  trip — so the two are distinguishable. RFC 5802's answer is a dummy salt and
  iteration count derived from a server-held secret, so an unknown account
  gets a plausible server-first and fails at 48 like everyone else. It must be
  **deterministic per username and secret**, or two 47s for one unknown name
  give different salts and leak the same fact. `APISRVR` can read `$CRED` but
  not write it, so the secret has to be seeded where credentials already are —
  `CRED_SET`, elevated — under an id `valid_os_name()` cannot produce. Deferred
  because it re-opens verified phase 2 work and because it changes no stored
  credential and no wire format, so adding it later costs nothing.
- **TLS, later or never.** If `SCRAM-SHA-256-PLUS` is ever wanted, the
  channel-binding flag in the client-first message is where it attaches — worth
  sending `n,,` honestly now rather than something that would have to change.

## Test vectors

RFC 7677 §3, recomputed independently 19 Aug 2026 and in agreement. Any
implementation of the helpers in step 1 must reproduce these exactly.

```
username        user
password        pencil
salt            W22ZaJ0SNY7soEsUEjb6gQ==
iterations      4096

SaltedPassword  xKSVEDI6tPlSysH6mUQZOeeOp01r6B3fcJbodRPcYV0=
StoredKey       WG5d8oPm3OtcPnkdi4Uo7BkeZkBFzpcXkuLmtbsT4qY=
ServerKey       wfPLwcE6nTWhTAmQ7tl2KeoiWGPlZqQxSrmfPwDl2dU=
ClientProof     dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=
ServerSignature 6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=
```

client-first-bare and the messages that build `AuthMessage`:

```
n=user,r=rOprNGfwEbeRWgbNEkqO
r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096
c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0
```
