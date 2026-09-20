#!/usr/bin/env bash
# mail.sh - deliver a message to the other agent through the pCloud mailbox, PROVE it
# landed, and later say whether it has been picked up.  RUN IT FROM THE BASH TOOL (the
# mailbox is /p there; the Write tool given P:\ writes a literal C:\p folder instead).
#
#   bash mail.sh send   <draft.md> <2026-09-20T1609-windows-subject.md>
#   bash mail.sh status <2026-09-20T1609-windows-subject.md>
#
# WHY IT EXISTS - owner, 20 Sep 2026.  A reply was DECLINED at the tool prompt, the outbox
# stayed empty, and the Linux agent waited while the reply's author believed it was sent.  The
# next sentence he said: "you need to make multiple attempts to send a message if there is a
# failure and check that it is received".  So:
#
#   send    copies under a .partial name, renames (README rule 2), then READS THE FILE BACK
#           and compares its SHA-256 with the draft's.  Any failure - the copy, the rename,
#           a landing whose bytes differ - is retried (SDCORE_MAIL_ATTEMPTS, default 4,
#           with a growing pause).  It exits 0 ONLY when the bytes in the outbox are the
#           draft's, and 1 saying THE MESSAGE WAS NOT SENT when every attempt failed.  A
#           send that printed nothing is not a send.
#   status  says where a message is NOW, which is the only receipt there is:
#             ACKNOWLEDGED  in done/  - the receiver moves a message there when handled
#             DELIVERED     still in the outbox - synced, not yet handled
#             LOST          in neither - it was moved, deleted or never sent
#           Exit 0 acknowledged, 1 delivered but pending, 2 lost.
#
# "RECEIVED" CANNOT BE PROVEN FROM HERE BEYOND THAT: pCloud syncs the folder and the other
# agent's session moves a handled message to done/.  So a message pending for longer than a
# heartbeat or two is worth telling the owner, who can see both sessions.
#
# Overrides for testing: SDCORE_MAIL_OUT (the outbox), SDCORE_MAIL_DONE, SDCORE_MAIL_ATTEMPTS.

set -u
OUT="${SDCORE_MAIL_OUT:-/p/sdcore-mail/to-linux}"
DONE="${SDCORE_MAIL_DONE:-/p/sdcore-mail/done}"
ATTEMPTS="${SDCORE_MAIL_ATTEMPTS:-4}"

cmd="${1:-}"
case "$cmd" in
  send)
    draft="${2:-}"; name="${3:-}"
    if [ -z "$draft" ] || [ -z "$name" ]; then echo "REFUSED: usage: mail.sh send <draft.md> <final-name.md>"; exit 2; fi
    if [ ! -f "$draft" ]; then echo "REFUSED: no draft at $draft"; exit 2; fi
    case "$name" in *.partial*) echo "REFUSED: the final name must not contain .partial (that is the in-flight name)"; exit 2;; esac
    if [ ! -d "$OUT" ]; then echo "REFUSED: no outbox at $OUT - is the P: drive mounted?"; exit 2; fi
    want=$(sha256sum "$draft" | cut -d' ' -f1)
    echo "sending $draft -> $OUT/$name  (sha256 $want, up to $ATTEMPTS attempts)"
    i=1
    while [ "$i" -le "$ATTEMPTS" ]; do
      echo "attempt $i/$ATTEMPTS"
      if cp "$draft" "$OUT/$name.partial" && mv -f "$OUT/$name.partial" "$OUT/$name"; then
        got=$(sha256sum "$OUT/$name" 2>/dev/null | cut -d' ' -f1)
        if [ "$got" = "$want" ]; then
          echo "DELIVERED: $OUT/$name  sha256=$got  ($(wc -c < "$OUT/$name") bytes)"
          echo "  not yet ACKNOWLEDGED: check with  bash mail.sh status $name"
          exit 0
        fi
        echo "  it landed but the bytes differ (read back $got) - retrying"
      else
        echo "  the copy or the rename failed - retrying"
      fi
      rm -f "$OUT/$name.partial" 2>/dev/null
      sleep $((i * 2))
      i=$((i + 1))
    done
    echo "FAILED after $ATTEMPTS attempts - THE MESSAGE WAS NOT SENT.  Tell the owner."
    exit 1
    ;;
  status)
    name="${2:-}"
    if [ -z "$name" ]; then echo "REFUSED: usage: mail.sh status <final-name.md>"; exit 2; fi
    if [ -f "$DONE/$name" ]; then echo "ACKNOWLEDGED: $name is in done/ - the other agent has handled it"; exit 0; fi
    if [ -f "$OUT/$name" ]; then echo "DELIVERED, PENDING: $name is in the outbox and has not been moved to done/ yet ($(stat -c %y "$OUT/$name" 2>/dev/null | cut -c1-16))"; exit 1; fi
    echo "LOST: $name is in neither the outbox nor done/ - it was never delivered, or was removed"
    exit 2
    ;;
  *)
    echo "usage: bash mail.sh send <draft.md> <final-name.md> | status <final-name.md>"
    exit 2
    ;;
esac
