# Secure Design — Importing Espanso Snippets

Status: **design, not implemented** · 2026-09-14 · rafter-secure-design pass

## What changes

Today Tippi *references* Espanso match files: it reads
`~/Library/Application Support/espanso/match/*.yml` on every load, and the file
on disk stays the source of truth. The plan is to *import* them into Tippi's own
store so snippets survive path changes and no longer depend on Espanso.

## Why this is a security decision, not a storage decision

Espanso matches may contain shell variables. Tippi runs them:

```swift
// SnippetVariableResolver.swift
process.executableURL = URL(fileURLWithPath: "/bin/sh")
process.arguments = ["-c", cmd]
```

That is arbitrary command execution with the user's full privileges, triggered
by typing a short string in any app. Everything below exists to keep that path
closed.

## The control that exists today

`approvedShellHash.<absolute-path>` in UserDefaults stores a content hash of an
approved file. `isFileApproved` compares the stored hash against the file's
current hash on **every load**. Any edit invalidates the approval and re-prompts.

Two properties are easy to miss and both matter:

1. **Verification is continuous, not one-time.** The check runs whenever the file
   is read, so it also catches an edit made long after approval.
2. **The hash covers the whole file**, not only its shell matches — an attacker
   cannot append a shell match to an already-approved file.

## The trap in the naive import

Moving to an import turns continuous verification into one-time verification.
Once a snippet lives in Tippi's own store, the file that was hashed is no longer
consulted, so nothing re-checks it.

The store is a plain JSON file in Application Support, writable by any process
running as the user and protected by no signature. The attack is short:

1. A process with user privileges edits Tippi's snippet store.
2. It adds — or rewrites — a snippet with a shell variable.
3. Tippi treats store contents as already-approved, because approval happened at
   import time.
4. The command runs the next time the trigger is typed.

Today the same attempt fails: editing the YAML changes its hash and Tippi
re-prompts. **A naive import is therefore a downgrade, not a refactor.**

## Decided design

Split by risk instead of treating all snippets alike. The two groups have
nothing in common except their file of origin.

### Snippets without shell variables — import freely

The large majority. Plain text replacements, date variables, cursor hints. No
execution surface, so no consent, no hash coupling, no re-prompting. This is the
group whose approvals broke silently over path changes, and importing them fixes
that completely.

### Snippets with shell variables — per-snippet consent, integrity-protected

- Consent is requested **per snippet**, showing the exact command, not per file.
  This is strictly better than today: a harmless edit elsewhere in the file no
  longer revokes an unrelated approval.
- Each approved shell snippet is stored with an HMAC over
  `(trigger, command)`, keyed by a secret held in the **Keychain**, not in
  UserDefaults and not in the store file.
- The HMAC is verified **immediately before execution**, not at load. This
  restores the continuous-verification property the file hash provided.
- Verification failure never runs the command; it surfaces a prompt naming the
  snippet and the command that changed.

The Keychain key is what makes this work: an attacker who can write the store
file cannot forge an HMAC without also extracting a Keychain item, which is a
materially higher bar and one macOS prompts about.

### Re-import must not silently re-approve

Re-importing a file is the obvious way to launder a modified command into an
approved state. Rules:

- Matching an existing snippet by trigger is **not** sufficient to inherit its
  approval. The approval is bound to the command text via the HMAC.
- If the command changed, the snippet arrives unapproved regardless of history.
- An import never upgrades an existing snippet's trust level. It may only add
  new unapproved entries or leave approved ones untouched.

### Importing a foreign YAML

Import from an arbitrary path (file picker) is the same trust boundary as the
Espanso directory, with a worse prior: the user did not author it. It runs the
identical path — shell snippets arrive unapproved and are shown individually
with their commands before anything can run. No blanket "trust this file"
option; that control is exactly what this design removes.

## Ingestion limits

The parser itself is sound: Yams with a typed `YAMLDecoder`, so there is no
arbitrary object graph and no deserialization gadget surface. Missing bounds
should be added with the import:

- Max file size (a match file is kilobytes; cap generously, e.g. 1 MB).
- Max match count per file and max command length.
- Partial-failure semantics are already decided and correct — parsing is
  per-file, a malformed file is logged and skipped rather than taking down the
  rest.

## STRIDE notes worth keeping

- **Tampering** is the dominant category here and drove the whole design. The
  store is the asset; the HMAC plus Keychain key is the control.
- **Elevation of privilege**: a snippet trigger is a low-privilege action (typing
  a few characters) that reaches a high-privilege capability (shell). The consent
  gate is the only thing separating them, which is why it must be verified at
  execution time.
- **Repudiation** is minor for a single-user local app, but shell executions
  should stay logged with the trigger name — without the command output, which
  must never reach the log.
- **Spoofing** and **Information disclosure** add nothing new here: no network
  boundary, and `stderr` is already discarded so command errors cannot leak into
  expanded text.

## Explicitly rejected

- **Import everything, keep a single global "snippets approved" flag.** Loses
  per-command granularity and re-introduces blanket trust.
- **Keep the file hash after import.** The file is no longer read, so the hash
  verifies nothing.
- **Drop shell support entirely.** Simplest and safest, but removes working
  functionality; revisit only if per-snippet consent proves too noisy in use.

## Migration — decided 2026-09-14: ask once

Existing file-level approvals are **not** carried over. At first import every
shell snippet arrives unapproved and is presented for consent once, even when
its file was approved before and its command is byte-identical.

Michael's call, and the safer of the two options. Inheriting approvals would
mean the first run of the new trust model starts with a set of permissions
nobody granted under its rules — the exact pattern the rest of this document
argues against. The cost is one pass through a consent list, once, for a handful
of shell snippets.

Two consequences for the implementation:

- The migration writes no MACs. There is no code path that mints an approval
  without the user having seen that specific command.
- Snippets without shell variables are unaffected — they never needed consent
  and must not appear in the migration prompt. A migration that asks about
  plain text replacements would train the user to click through it.
