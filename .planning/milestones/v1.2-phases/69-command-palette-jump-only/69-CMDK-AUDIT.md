# cmdk dependency audit (D-01)

**Package:** `cmdk`
**Version audited:** `1.1.1` (latest stable as of audit date)
**Audit date:** 2026-05-18
**Auditor:** gsd-executor (Phase 69, Plan 01, Task 1)
**Per:** CONTEXT.md D-01 + `feedback_dep_security_audit` memory

This artifact is regenerated live from a clean shell — it is NOT a copy of
`69-RESEARCH.md`'s legitimacy section. Every probe below was re-run against the
live npm registry / GitHub on the audit date.

---

## Commands run (verbatim) + output excerpts

### 1. Version probe

```
$ cd gui && npm view cmdk version
1.1.1
```

### 2. Registry metadata (size, files, maintainers, signature)

```
$ cd gui && npm view cmdk dist.unpackedSize dist.fileCount maintainers dist.signatures
dist.unpackedSize = 81852
dist.fileCount = 13
maintainers = [ 'paco <miners.keeps-0z@icloud.com>', 'dipnpm <benji@dip.org>' ]
dist.signatures = {
  sig: 'MEUCIH5gdD8aAcbaPB2bT8E1HmrUwmaL/6hyV0e5bKy9xdrKAiEAoCzciYcGtwYEJGusM6X6BsgiaDkPOmWk/3MW9BTHxt0=',
  keyid: 'SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U'
}
```

### 3. Install-time script surface

```
$ cd gui && npm view cmdk scripts.postinstall scripts.preinstall scripts.install scripts
(scripts.postinstall, scripts.preinstall, scripts.install: all empty/undefined)
scripts = { dev: 'tsup src --watch', build: 'tsup src' }
```

No `postinstall`, `preinstall`, or `install` hook. The two scripts present
(`dev`, `build`) are build-time scripts that run on the publisher's machine,
not on the consumer at install time.

### 4. Dependency tree (direct + peer)

```
$ cd gui && npm view cmdk dependencies peerDependencies
dependencies = {
  '@radix-ui/react-id': '^1.1.0',
  '@radix-ui/react-dialog': '^1.1.6',
  '@radix-ui/react-primitive': '^2.0.2',
  '@radix-ui/react-compose-refs': '^1.1.1'
}
peerDependencies = {
  react: '^18 || ^19 || ^19.0.0-rc',
  'react-dom': '^18 || ^19 || ^19.0.0-rc'
}
```

Four direct deps — all official Radix UI primitives. Project already uses the
`radix-ui@^1.4.3` umbrella, so transitive Radix sub-packages are familiar
terrain. Peer deps match the project's `react@^19.1.0`.

### 5. slopcheck verdict

```
$ cd gui && slopcheck install -e npm cmdk

slopcheck checking 1 package(s) on npm before install...

  Installing: cmdk
  Running: npm install cmdk

  [OK] cmdk (npm)

==================================================
  scanned 1 packages
  1 OK
```

slopcheck v0.6.1 verdict: **OK** (1 OK / 0 SLOP / 0 SUS / 0 ASSUMED).

### 6. GitHub repo health (`dip/cmdk` — `pacocoursey/cmdk` redirects here)

```
$ gh api repos/dip/cmdk | head -40
{
  "id":514395914,
  "name":"cmdk",
  "full_name":"dip/cmdk",
  "owner":{"login":"dip", "type":"Organization", ...},
  "description":"Fast, unstyled command menu React component.",
  "created_at":"2022-07-15T20:22:47Z",
  "updated_at":"2026-05-18T17:23:28Z",
  "pushed_at":"2025-10-29T04:13:58Z",
  "size":798,
  "stargazers_count":12601,
  "watchers_count":12601,
  "forks_count":368,
  "archived":false,
  "disabled":false,
  "license":{"key":"mit","name":"MIT License","spdx_id":"MIT"},
  "topics":["combobox","command-menu","command-palette","radix-ui","react"],
  ...
}
```

archived=false, disabled=false, MIT, 12.6K stars, last push 2025-10-29
(README only; v1.1.1 code commit was 2025-03-14). Stable, non-abandoned.

---

## Findings table

| Field              | Value                                                            | Verdict |
|--------------------|------------------------------------------------------------------|---------|
| Publisher          | `paco <miners.keeps-0z@icloud.com>` (Paco Coursey, Vercel)       | OK — author of cmdk; co-maintainer `dipnpm <benji@dip.org>` is paco's org |
| Signature present  | yes; SHA-256 keyid `DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U` | OK |
| Install scripts    | none (postinstall / preinstall / install all empty)              | OK — no install-time code execution |
| Unpacked size      | 81,852 bytes (~80 KB), 13 files                                  | OK — reasonable for a palette library |
| Direct deps        | 4 (all `@radix-ui/*` — react-id, react-dialog, react-primitive, react-compose-refs) | OK — only official Radix primitives |
| Peer deps          | `react ^18 \|\| ^19 \|\| ^19.0.0-rc`; `react-dom` same           | OK — compatible with project's react@^19.1.0 |
| slopcheck          | `[OK]` (1 OK / 0 SLOP / 0 SUS)                                   | OK |
| Repo health        | github.com/dip/cmdk: 12.6K stars, MIT, archived=false, disabled=false, last code push 2025-10-29 | OK |
| Repo ownership     | `pacocoursey/cmdk → dip/cmdk` (org rename; same maintainer email) | OK — not a hostile takeover; canonical homepage redirects transparently |

---

## Verdict

**Audit verdict: PASS**

All probes match `69-RESEARCH.md` expectations. No suspicious behavior was
surfaced. The phase may proceed to install `cmdk@1.1.1` and ship the rest of
Plan 01.

---

## Post-install verification

Performed immediately after `npm install cmdk@1.1.1 --save-exact`.

```
$ cd gui && npm install cmdk@1.1.1 --save-exact
(success — adds 1 dependency, lockfile updated)

$ node -e "console.log(require('./package.json').dependencies.cmdk)"
1.1.1

$ npm ls @radix-ui/react-dialog
gui@0.1.0 /home/itay/projects/Julia-STREAM/.claude/worktrees/agent-af6adfb51a32e5ae2/gui
├─┬ cmdk@1.1.1
│ └── @radix-ui/react-dialog@1.1.15
└─┬ radix-ui@1.4.3
  ├─┬ @radix-ui/react-alert-dialog@1.1.15
  │ └── @radix-ui/react-dialog@1.1.15 deduped
  └── @radix-ui/react-dialog@1.1.15 deduped
```

Exactly **one hoisted version** of `@radix-ui/react-dialog` (`1.1.15`) is
resolved — cmdk's `^1.1.6` requirement is satisfied by the existing radix-ui
umbrella's `1.1.15`, and npm deduplicates both into a single hoisted
installation. Pitfall 4 from RESEARCH.md (duplicate Dialog → focus-trap
conflict + bundle bloat) is **not present**.

`gui/package.json` `dependencies.cmdk` is pinned to the exact string `1.1.1`
(via `--save-exact`). `gui/package-lock.json` resolves cmdk@1.1.1 with the
integrity hash and matching @radix-ui/* subtree.

---

*Audit complete. Plan 01 Tasks 2-4 may proceed.*
