# Pricing (initial sketch)

This is a planning document, not a commitment.

| Tier   | Price                | Includes                                                  |
| ------ | -------------------- | --------------------------------------------------------- |
| Free   | $0                   | 50 panel asks / month, 1 drawer, max 50 drawer items      |
| Plus   | $10 / month          | Unlimited panel asks, 10 drawers, max 1000 items / drawer |
| BYOK   | $0 (post-Phase 1)    | User supplies their own Anthropic / OpenAI key            |
| Teams  | TBD (post-Phase 5)   | Shared drawers, SSO, audit log                            |

## Cost drivers

- **Vision tokens** are the single biggest line item. Mitigations:
  - Downsample to ≤ 768 px on the long edge.
  - Cache images by SHA-256; reuse across the same session.
  - Skip vision when AX text is sufficient.
- **Drawer queries** can include many chunks; we cap default top-K at 8
  and surface the estimated cost before send.
- **Tool-use round-trips** in Phase 4 multiply token usage; plan for
  ~2-3x base cost per automation request.

## What free tier needs to be

The free tier must be **useful enough to keep on**: 50 asks/month is
roughly 1-2/day, which is the right level for a curious user but
clearly inadequate for daily use, encouraging upgrade.

## BYOK

Adds:
- Per-user encrypted key storage (Keychain on the client; never sent
  to the backend).
- A lightweight backend mode that just signs/forwards requests, billed
  at a small flat fee or free.

## Open questions

- Do we charge for the drawer storage itself (not just queries)?
  Probably not at launch — local-only storage means our cost is the
  embedding compute, which is on-device.
- Education / open-source maintainer discount? Probably yes,
  hand-managed at first.
