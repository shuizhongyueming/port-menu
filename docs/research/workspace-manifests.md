# Workspace / package-set manifests in Node, Rust and Go

Research for issue #2 — *"Node / Rust / Go 的 workspace 清单如何声明包集合"* (part of #1).

Purpose: give whoever writes the Port Menu resolver (Swift) enough precision to turn a project
root — plus a dev-server process's **cwd** and **git root** — into one deterministic
`PackageRef` (display string + canonical relative path), without guessing.

> **Evidence-grade warning (read this first).**
> This session had **no working outbound HTTP**: `fetch_content` was refused for every host
> (`Blocked internal address … 198.18.0.0/15`, a TUN/fake-IP proxy), and `github.com` /
> `api.github.com` are rejected by the same guard. Test commands such as `gh issue view` / `git`
> could not be run either (no shell in the session).
> Consequently **no official page was read verbatim**. Every "documented" row below is
> *search-provider retrieval of the official page* (`source_check` / `web_search` with
> `fetchContent`), i.e. an **interpretation of the page by a retrieval tool**, not a quotation
> verified character-by-character. Rows are marked `D` (documented, corroborated by the official URL
> named) or `E` (empirical / inferred / not stated in docs).
> **Before shipping, re-read the URLs in §10 and delete this caveat.**

Legend: **D** = documented on the cited official page · **E** = empirical, inferred, or undocumented.

---

## 0. Answers to the issue's numbered facts (start here)

### 1. Node

| Sub-question | Answer | Grade | Source |
|---|---|---|---|
| `workspaces` array vs `{ packages: [...] }` object | **Array** is what npm documents (`"workspaces": ["packages/*"]`). The **object form with `packages`** is documented for **Yarn 1 (Classic)**, which also adds `nohoist`. Read `workspaces.packages` when the field is an object; ignore `nohoist` entirely. Yarn 2+ and npm take the array only. | D | [npm workspaces](https://docs.npmjs.com/cli/using-npm/workspaces/), [Yarn 1 workspaces](https://classic.yarnpkg.com/lang/en/docs/workspaces/), [Yarn modern](https://yarnpkg.com/features/workspaces) |
| `!` prefix semantics | **pnpm only.** In `pnpm-workspace.yaml.packages` a `!pattern` **removes** matching directories from the set (`- "packages/**"` + `- "!packages/**/fixtures/**"`). For **npm** the docs show only positive patterns — `!` is **not documented**; npm's expander is `@npmcli/map-workspaces`. In **Yarn 1's** object form the sibling key `nohoist` is a *hoisting* exception, **not** an exclusion list. | D (pnpm) / E (npm) | [pnpm workspaces](https://pnpm.io/workspaces/), [@npmcli/map-workspaces](https://www.npmjs.com/package/@npmcli/map-workspaces) |
| `**` and `*` support | **Both supported, in all of npm / Yarn / pnpm.** pnpm states the distinction explicitly: `packages/**` matches `packages/a` **and** `packages/group/b`, while `packages/*` matches **only one level** below `packages/`. Patterns are relative to the workspace root. | D (pnpm wording) / D for "globs supported" in npm & Yarn | [pnpm workspaces](https://pnpm.io/workspaces/) |
| Nested packages (workspace inside a workspace) | **Membership is purely pattern-driven — nesting grants nothing.** A package living at `packages/a/sub` is a member only if some root pattern matches `packages/a/sub`. With `packages/*` it is **not** a member (only one level); with `packages/**` it **is**. npm frames the same rule: nested folders are fine *as long as the root `workspaces` config matches their paths*; `--workspace=packages/a` on the CLI addresses a subtree of nested workspaces. There is no "implicit recursion" in any of the three. | D for the glob semantics, E for "no implicit recursion" | [pnpm workspaces](https://pnpm.io/workspaces/), [npm workspaces](https://docs.npmjs.com/cli/using-npm/workspaces/) |
| `pnpm-workspace.yaml.packages:` vs `package.json.workspaces` — precedence | **YAML wins.** pnpm's source of truth is `pnpm-workspace.yaml`. If both exist and disagree, pnpm reads the YAML and warns about the mismatch. If the YAML is **absent** but `package.json.workspaces` exists, newer pnpm (reported **≥ 12.7**) *generates* the YAML from those patterns on install and then treats the YAML as authoritative. Older pnpm never silently used the JSON field. | D, version-sensitive → **medium** | [pnpm workspaces](https://pnpm.io/workspaces/), [pnpm release notes](https://pnpm.io/blog?type=releases) |
| Do `catalog:` / `catalogs:` and other new keys change the package set? | **No.** `catalog` / `catalogs` centralise **dependency version ranges** (`catalog:` protocol) in `pnpm-workspace.yaml`; other keys there are pnpm settings (`onlyBuiltDependencies` / `allowBuilds`, …). **Only `packages:` defines the set.** Corollary: the mere existence of `pnpm-workspace.yaml` does *not* prove a monorepo — test that `packages` exists and is non-empty. | D | [pnpm catalogs](https://pnpm.io/catalogs), [pnpm settings](https://github.com/pnpm/pnpm/blob/main/pnpm/docs/settings.md) |
| pnpm project with a `package.json` that has **no** `workspaces` | **The YAML decides; the JSON is irrelevant.** This is the common real-world case: `package.json` exists for scripts/metadata only. Conversely, **no YAML + no JSON field = single package**, regardless of how many `package.json` files exist on disk. | D/E | [pnpm workspaces](https://pnpm.io/workspaces/) |

### 2. Rust

| Sub-question | Answer | Grade | Source |
|---|---|---|---|
| Does `[workspace] members` support globs? | **Yes, officially.** Canonical form `members = ["crates/*"]`. Paths are relative to the directory holding that `Cargo.toml`; every matched directory must contain a `Cargo.toml`. | D | [Cargo Book · Workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html) |
| How does `exclude` override `members`? | `exclude` **removes** directories from the set produced by expanding `members`. The Book's own rationale is *"useful if some path dependencies aren't desired to be in the workspace at all, or **using a glob pattern and you want to remove a directory**"* — i.e. the documented job of `exclude` is to carve holes in a glob. Whether an `exclude` entry may **itself** contain `*`/`**` is **not clearly documented**; see cargo [#11405](https://github.com/rust-lang/cargo/issues/11405) for how subtle the interaction is. Match `exclude` as a glob (superset; identical result for literal paths). | D (mechanism) / E (glob-in-exclude) | [Cargo Book · Workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html), [cargo#11405](https://github.com/rust-lang/cargo/issues/11405) |
| `default-members` | A **subset of `members`** used when a cargo command runs **in the workspace root** with no package-selection flags. It must name real members. **It is not the package set** — do not use it as the resolver's output. | D | same page |
| `[workspace]` in a non-root `Cargo.toml` vs a root that also has `[package]` | Two different things: **(i) virtual manifest** — a `Cargo.toml` with `[workspace]` and **no** `[package]`; it is a workspace root and is **not itself a package** (the common `/Cargo.toml` in Rust monorepos). **(ii) root-package workspace** — `Cargo.toml` with **both** `[package]` and `[workspace]`; the root **is a member and a package** in addition to being the root. **(iii) `[workspace]` in a nested `Cargo.toml`** — that directory is the root of **its own** workspace, not a member of the outer one; a downward walk must stop and re-root there. A package attaches itself to a root by **walking upward** to the nearest ancestor `Cargo.toml` with `[workspace]`, or explicitly via `[package] workspace = "../.."`. | D for (i)/(ii), E for (iii) and upward search | [Cargo Book · Workspaces](https://doc.rust-lang.org/cargo/reference/workspaces.html), [Cargo Book · Manifest](https://doc.rust-lang.org/cargo/reference/manifest.html) |

### 3. Go

| Sub-question | Answer | Grade | Source |
|---|---|---|---|
| `use` single value & block form | Both legal: `use ./service` and `use ( ./lib  ../another-module  /abs/path/mod )`. Each argument is **a directory containing that module's `go.mod`**. | D | [Go Modules Reference](https://go.dev/ref/mod#go-work-file) |
| Relative paths | Yes — relative to the **directory holding `go.work`**; absolute paths also accepted (empirically `use ../another-module` is the documented cross-repo idiom). | D/E | [go.dev/blog/get-familiar-with-workspaces](https://go.dev/blog/get-familiar-with-workspaces) |
| Wildcard support | **Officially none.** `use` takes literal directories; the grammar has no pattern form. The strongest corroboration is that Go ships `go work use -r <dir>` to **recursively add every directory containing a `go.mod`** — a flag that only needs to exist because patterns are not supported. Also: `use` does **not** pull in nested modules automatically. | D | [Go Modules Reference](https://go.dev/ref/mod), [cmd/go workcmd/use.go](https://go.dev/src/cmd/go/internal/workcmd/use.go) |
| Impact of `go.work` being git-ignored | Real and important: `go.work` (and `go.work.sum`, which holds workspace-specific checksums) are commonly **not committed** — the Go docs themselves frame committing as the *exception* for repos whose modules are "intentionally developed and tested together". Consequences for us: a fresh clone can have **multiple `go.mod` files and no `go.work`**, while the same tree on the developer's machine has one; and a `go.work` that references a directory missing on disk is an error for the go tool. So: **`go.work` present → trust it; absent → do not conclude "single module"** unless there is exactly one reachable `go.mod`. | D (checksums / commit guidance) + E (consequences) | [Go Modules Reference](https://go.dev/ref/mod), [go.dev/doc/tutorial/workspaces](https://go.dev/doc/tutorial/workspaces) |

### 4. Cross-ecosystem

| Sub-question | Answer | Grade |
|---|---|---|
| Repo has both `package.json` and `Cargo.toml` — who speaks? | **Neither "wins" globally: each manifest governs its own ecosystem, independently.** The correct question is not "which file wins" but "**which manifest claims this process's cwd**". Resolve per ecosystem, then let the claim nearest to the cwd decide the display string. | E (design decision, grounded in the per-ecosystem rules above) |
| Union the package sets? | **Union for the *inventory* (list of packages), never for one *identity*.** Different ecosystems can point at the same directory (e.g. a `packages/x` that is both an npm workspace and a Cargo member) — de-duplicate by canonical **real path** and keep one row per path with an ecosystem tag (or an ecosystem set). For a single display string, prefer the claim whose manifest lives **closest to the cwd** (see §6). | E |

---

## 1. Fact table (one screen)

| # | Ecosystem | Marker file | Key / field | Value type | Paths relative to | Glob support | Negation / exclude | Conf. |
|---|---|---|---|---|---|---|---|---|
| 1 | npm | `package.json` | `workspaces` | `string[]` of dir paths/globs | that `package.json`'s dir | yes (`*`, `**`, `?`) | **none documented** | D/E |
| 2 | Yarn 1 | `package.json` | `workspaces` | `string[]` **or** `{ packages: string[], nohoist: string[] }` | same | yes | object form: `nohoist` is hoisting, not exclusion | D |
| 3 | Yarn ≥2 | `package.json` | `workspaces` | `string[]` only | same | yes | none | D |
| 4 | pnpm | `pnpm-workspace.yaml` | `packages:` | glob strings, order matters | the YAML file's dir | yes, `**` ≠ `*` | **yes**, `!` entries | D |
| 5 | pnpm | `package.json` | `workspaces` | as npm | same | yes | — | fallback only (§2.3) |
| 6 | Cargo | `Cargo.toml` | `[workspace] members` | `string[]` paths/globs | that `Cargo.toml`'s dir | **yes** | see next row | D |
| 7 | Cargo | `Cargo.toml` | `[workspace] exclude` | `string[]` paths | same | ambiguous (§3.2) | removes from `members` | D/E |
| 8 | Cargo | `Cargo.toml` | `[workspace] default-members` | `string[]` | same | must name members | **not** the package set | D |
| 9 | Cargo | member `Cargo.toml` | `[package] workspace = "../"` | path | — | no | pins the root | D |
| 10 | Go | `go.work` | `use` | directory literals | the `go.work` dir (or absolute) | **none** | none | D |
| 11 | Go | `go.mod` | `module` | module path | — | — | one module | D |

Only **five** field shapes** must be parsed: `package.json.workspaces` (array | `{packages}`),
`pnpm-workspace.yaml.packages`, `Cargo.toml [workspace] {members, exclude, default-members}`,
`go.work {use}`.

---

## 2. Node — detail

### 2.1 npm: `package.json.workspaces`
- **Root-only.** The field is meaningful only in the repo's root `package.json`.
- Documented shape: `"workspaces": ["packages/*", "apps/*"]`.
- A matched directory counts **only if it contains a `package.json`**.
- **The root package is not a member** (`npm ls --workspaces` lists only members).
- `private: true` on the root is a *publishing* concern, irrelevant to us (E).

### 2.2 Yarn
| Version | Shape | Extra |
|---|---|---|
| Yarn 1 (Classic) | `string[]` **or** `{ "packages": [...], "nohoist": [...] }` | `nohoist` = hoisting exceptions |
| Yarn ≥2 (Berry) | `string[]` only | `nohoist` retired |

An object-form `workspaces` is a **real, documented** shape that a strictly npm-shaped parser would
reject. Rule: **object → read `.packages`, ignore `.nohoist`.**

### 2.3 pnpm: `pnpm-workspace.yaml`
```yaml
packages:
  - "apps/*"              # one level
  - "packages/**"         # any depth
  - "!packages/**/fixtures/**"   # exclusion
catalog:                  # dependency versions — does NOT define packages
  react: ^19.0.0
```
- Patterns are **relative to the workspace root** (the YAML's directory).
- `*` = exactly one segment; `**` = one or more segments (pnpm states `packages/**` matches
  `packages/a` and `packages/group/b`, while `packages/*` matches only one level).
- `!` = exclusion, applied to the accumulated set; **order matters** (a later positive pattern can
  re-add a path a `!` removed — E, standard glob-list semantics).
- Only `packages` defines the set; `catalog`, `catalogs`, build-approval settings do not.

**Precedence rule to implement (correct under every pnpm generation):**
```
if pnpm-workspace.yaml exists AND packages: is non-empty   -> use the YAML (authoritative)
else if package.json.workspaces exists                      -> use that field
else                                                        -> single package (the root)
```
**Never union the two** — that invents packages neither pnpm nor npm installs. If both exist and
differ, pnpm itself reads the YAML and warns; mirror that (YAML wins, no merge).

### 2.4 Glob semantics shared by npm / Yarn / pnpm (E, library-level)
The docs specify *that* globs work, not the dialect; the managers delegate to JS glob libraries
(`@npmcli/map-workspaces` → `glob`/`minimatch`; pnpm → picomatch/fast-glob family). For Swift:

- `*` = exactly one path segment; `**` = zero or more segments; `?` = one character; `[abc]` = class.
- `{a,b}` brace expansion is **library-dependent** — leave it unsupported (safe: it only appears in
  hand-written exotic configs).
- Patterns name **directories**, and a match counts only if the manifest exists there.
- Normalise before matching: strip leading `./`, trailing `/`, collapse duplicate separators.
- **Always prune** `node_modules`, `.git`, `target`, `.build`, `vendor`, `dist` when walking
  (mandatory in practice: `packages/**` would otherwise match every dependency).
- Resolve symlinks (`realpath`) and de-dupe — pnpm's `link:`/`file:` layouts otherwise yield the
  same package twice.

---

## 3. Rust / Cargo — detail

```toml
# /Cargo.toml  (virtual manifest: no [package] => root is NOT a package)
[workspace]
resolver = "2"
members = ["crates/*", "apps/cli"]
default-members = ["crates/core"]
exclude = ["crates/experimental-scratch"]
```

### 3.1 Membership algorithm (matches Cargo's documented model)
1. Find the **workspace root**: nearest ancestor `Cargo.toml` containing `[workspace]`
   (or the one pinned by `[package] workspace = "…"`).
2. Expand each `members` entry as a glob relative to that `Cargo.toml`; keep dirs with a `Cargo.toml`.
3. Remove every directory matching an `exclude` entry (glob-match; see §3.2).
4. If the root `Cargo.toml` also has `[package]`, **add the root itself**.
5. `default-members` — read it, but **do not use it as the set** (§0.2).

### 3.2 `exclude` semantics, honestly
Documented: paths that prevent inclusion, explicitly motivated by *"using a glob pattern and you
want to remove a directory"*. Not documented: whether `exclude` entries accept wildcards. Cargo
issue #11405 ("Make workspace member inclusion/exclusion more useful, consistent, and intuitive")
shows the interaction is genuinely subtle (e.g. excluding a parent path while including children
beneath it). **Implementation:** treat `exclude` as glob patterns; for literal entries the result is
identical either way, and a wildcard entry then behaves the way users expect.

### 3.3 Virtual vs root-package vs nested
| Root `Cargo.toml` | Name | Is the root a package? |
|---|---|---|
| `[workspace]` only | **virtual manifest** | **No** |
| `[workspace]` + `[package]` | root-package workspace | **Yes** |
| nested `Cargo.toml` with `[workspace]` | its own workspace root | depends on its own tables; **not** part of the outer workspace |

*(iii) is E: it follows from "root = a `Cargo.toml` with `[workspace]`", but the retrieval did not
surface a verbatim sentence. A downward scan must re-root rather than merge.*

---

## 4. Go — detail

```go
go 1.23.0                 // required, at most once

toolchain go1.24.2        // optional, at most once

use ./service             // single-value form
use (                     // block form
    ./lib
    ../another-module
)

replace example.com/dep => ../local-fork   // go.mod semantics
godebug default=go1.21                     // go 1.23+
```

- Directive set: `go`, `toolchain`, `godebug`, `use`, `replace`. **Only `use` contributes packages.**
- Each `use` argument = a directory containing a `go.mod`; the go tool errors on a directory that is
  not a module. Nested modules are **not** implied.
- **No wildcards.** `go work use -r <dir>` is the recursive discovery mechanism — implement it if you
  want "auto-add nested modules": walk down for `go.mod`, prune `vendor`, `testdata`, dot-dirs.
- Locating the file: walk up from the cwd, or `GOWORK` env var (`GOWORK=off` disables workspaces;
  `go env GOWORK` prints the active path). *(E for the resolver, D for the variable.)*
- Parse with a tiny line parser (it is neither YAML nor TOML): strip `//` comments, handle the
  parenthesised block, ignore everything that is not `use`.

---

## 5. Decision axes for Port Menu (the parent's (a)/(b)/(c))

### (a) Does `apps/*` need filesystem expansion, or can it be matched as a path prefix?
**Neither "expansion" nor "prefix" — it needs a *single-path glob match*, and that is the cheap
option you actually want.**

- **Plain string-prefix is wrong.** With `workspaces: ["apps/*"]`, the cwd
  `/repo/apps/web/sub` has prefix `apps/` but is **not** a workspace package; and `crates/*` would
  wrongly claim `crates/a/b`. `*` matches **exactly one segment**.
- **Full filesystem expansion is unnecessary at display time.** You already know the process cwd.
  Instead of enumerating the tree, test the **cwd's path relative to the workspace root against the
  pattern list**. Cost: O(#patterns), no directory walking, no permission stalls.

```
matches(relPath, pattern):
  split both on "/"
  match segments left-to-right:
    "*"  -> consume exactly one segment
    "**" -> consume zero or more segments (backtracking or DP)
    else -> literal compare (case-sensitive; macOS volumes may be case-insensitive — compare
            with .caseInsensitive on APFS-default volumes and note it, E)
  success only if all segments consumed on both sides
```
Then, for one cwd:
```
claimed = any pattern p in workspacePatterns where matches(rel(cwd, root), p)
          and p is not excluded (pnpm "!" entries, Cargo exclude) and manifest exists in cwd
```
- You **do** need expansion for the *inventory* view ("list all packages in this project"). Keep the
  glob expander, but bound it with the prune list and a depth cap derived from the pattern
  (a pattern with no `**` never needs to descend more than `#segments` deep — **this is the single
  biggest performance win**).
- Cargo and pnpm have identical `*` / `**` semantics for the patterns in practice, so one matcher
  serves all three ecosystems; Go never reaches the matcher (§0.3).

### (b) What is the package's canonical relative path — the declared string or the expanded directory?
**The expanded directory, resolved to a real path, relative to the workspace root.** Concretely:

- Never key on the declared pattern (`"packages/*"` is a *selector*, not a package).
- `canonicalPath = realpath(matchedDir)` then `relativize(against: realpath(workspaceRoot))`.
- De-duplicate on `canonicalPath` (symlinked pnpm/npm links otherwise collide).
- A directory that contains **no** manifest is **not** a package, even if a pattern matched it.
- **Display string ≠ canonical path.** Build it as:
  1. manifest `name` — npm `package.json.name`, Cargo `[package].name`, Go `module` path from
     `go.mod`; else
  2. the canonical path relative to the **git root** (shorter and more familiar than relative to the
     workspace root when the workspace root is nested); else
  3. the directory basename.
- Keep **both** on the model: `displayName` (for the menu bar) and `canonicalPath` (for identity,
  matching a running process, and de-dup). Never re-derive one from the other.

### (c) Precedence between competing manifests in one repo
Resolve in two layers:

**Layer 1 — inside one ecosystem** (already settled above):
1. pnpm: `pnpm-workspace.yaml` **>** `package.json.workspaces` (§2.3).
2. Cargo: the **nearest ancestor** `Cargo.toml` with `[workspace]` wins; a nested `[workspace]`
   starts a new root; `[package] workspace = "…"` overrides the upward search.
3. Go: the **nearest ancestor** `go.work` wins; if none, the nearest `go.mod` (and if several
   `go.mod` exist with no `go.work`, treat each as its own package — §0.3 git-ignore impact).

**Layer 2 — across ecosystems** (a repo with `package.json` and `Cargo.toml`):
- Do **not** pick a global winner. Resolve each ecosystem independently, then choose the **claim
  nearest to the cwd** for the display string.
- Deterministic tie-break when two manifests claim the exact same directory (rare, e.g. a
  `packages/x` that is both npm and Rust): `pnpm-workspace.yaml` > `package.json` > `Cargo.toml` >
  `go.work` (most-specific-declared-first), and record the others as secondary ecosystems so the UI
  can show a badge instead of silently dropping them.
- **Union** the inventories (de-duped by `canonicalPath`), but note: unioning is for *listing*; for
  *identity of one running server* the nearest claim is the answer.
- If **nothing** claims the cwd (a plain repo, or a workspace pattern that excludes it): fall back to
  the **git root** + directory basename. That fallback must be explicit, not accidental.

---

## 6. Reference implementation sketch

```swift
struct PackageRef {                // what the menu bar row needs
    let canonicalPath: URL         // realpath, absolute
    let workspaceRoot: URL
    let relPath: String            // relative to workspaceRoot, "/"-separated
    let displayName: String        // manifest name ?? basename
    let ecosystems: Set<Ecosystem> // node-npm | node-pnpm | node-yarn | cargo | go
}

func resolvePackage(forCwd cwd: URL, gitRoot: URL) -> PackageRef? {
    // 1. nearest claiming manifest, walking up from cwd
    //    pnpm-workspace.yaml (packages non-empty)  -> highest priority
    //    package.json workspaces (array | .packages)
    //    Cargo.toml with [workspace] (members-minus-exclude, or the member's own up-walk)
    //    go.work (literal use dirs), else go.mod
    // 2. per-ecosystem match test: does rel(cwd, root) match any pattern?  (§5a)
    // 3. build PackageRef (§5b), de-dupe on realpath
    // 4. fallback: gitRoot + basename
}
```

Failure modes to handle explicitly: malformed YAML/TOML/JSON (skip that ecosystem, keep others),
pattern pointing outside the root (`../sibling` is legal in Go), empty `packages:` (pnpm = root
only), symlinked packages, nested workspace roots (stop & re-root), missing `go.work` on a fresh
clone (§0.3).

---

## 7. Documented vs only-empirical (issue #2's explicit ask)

| Claim | Status |
|---|---|
| npm `workspaces` = array of dir paths/globs in the root `package.json` | **Documented** |
| Yarn 1 also allows `{packages, nohoist}`; `nohoist` ≠ exclusion; Berry = array only | **Documented** |
| npm supports `!` exclusions | **Not documented → treat as NO** (E) |
| pnpm `packages:` = globs, `!` = exclusion, relative to the YAML dir | **Documented** |
| pnpm `packages/**` matches ≥1 segment, `packages/*` matches exactly 1 | **Documented** (pnpm wording) |
| pnpm YAML authoritative; `package.json.workspaces` only a generator/fallback | **Documented, version-sensitive (≥12.7) — medium** |
| `catalog:`/`catalogs:` do not affect the package set | **Documented (purpose) + E (the negative)** |
| Nested workspace-in-workspace counts only if a pattern matches | **Documented (glob semantics) + E (no implicit recursion)** |
| Cargo `members` accepts globs | **Documented** |
| Cargo `exclude` removes dirs from `members` | **Documented** |
| Cargo `exclude` entries may themselves be globs | **Ambiguous** (cargo#11405) — E |
| Cargo `default-members` is a command default, not the package set | **Documented** |
| Cargo virtual manifest root is not a package; `[package]`+`[workspace]` root is | **Documented** |
| Nested `[workspace]` re-roots instead of joining the outer workspace | **E** |
| Go `use` = literal dirs only, no wildcards | **Documented** + corroborated by `go work use -r` |
| `go.work` commonly uncommitted; `go.work.sum` = workspace checksums | **Documented** (commit-is-the-exception framing) |
| "no `go.work` ⇒ single module" is safe | **FALSE** — E, must be guarded (§0.3) |
| Glob dialect details (`{}`, dotfiles), symlink handling, ignore lists | **Undocumented everywhere — empirical** |

---

## 8. Failure modes / edge cases the resolver must survive

1. Malformed YAML / TOML / JSON → skip that ecosystem, keep the rest, surface a diagnostic.
2. Pattern matches a directory with no manifest → not a package.
3. Pattern escaping the root (`../another-module`) → legal (Go); normalise, allow, de-dupe.
4. Symlinked packages → duplicate rows unless `realpath`.
5. Nested workspace roots → stop the walk, re-root.
6. Empty `packages:` in YAML → pnpm = root only; don't crash.
7. Multiple `go.mod`, no `go.work` (fresh clone) → several packages, not one.
8. Both `pnpm-workspace.yaml` and `package.json.workspaces` differing → YAML only, no merge.

---

## 9. Unsettled

1. **npm `!` negation** — retrievals disagreed; verify with
   `{"workspaces":["packages/*","!packages/b"]}` + `npm ls --workspaces`.
2. **Exact pnpm version** introducing the `package.json.workspaces` → YAML generation (reported
   ≥12.7; release pages returned only titles).
3. **Cargo `exclude` glob support** — glob or literal path?
4. **Whether npm/Yarn prune `node_modules` inside `**` expansion** — undocumented; prune anyway.
5. **Nested `[workspace]` behaviour** — E only; verify with a two-root fixture.
6. **Bun** workspaces (`package.json.workspaces` + catalog) — out of scope, unverified.
7. Case sensitivity on APFS default volumes — E; decide per-volume with
   `URLResourceValues.volumeSupportsCaseSensitiveNames`.

---

## 10. Sources

**Kept (primary)**
- npm — Workspaces: <https://docs.npmjs.com/cli/using-npm/workspaces/>
- npm — package.json fields: <https://docs.npmjs.com/cli/v9/configuring-npm/package-json/>
- `@npmcli/map-workspaces` (npm's own expander): <https://www.npmjs.com/package/@npmcli/map-workspaces>
- Yarn 1 — Workspaces (`packages` + `nohoist`): <https://classic.yarnpkg.com/lang/en/docs/workspaces/>
- Yarn modern — Workspaces: <https://yarnpkg.com/features/workspaces>
- pnpm — Workspaces: <https://pnpm.io/workspaces/>
- pnpm — docs source for that page: <https://github.com/pnpm/pnpm/blob/main/pnpm/docs/workspaces.md>
- pnpm — Catalogs: <https://pnpm.io/catalogs>
- pnpm — settings reference: <https://github.com/pnpm/pnpm/blob/main/pnpm/docs/settings.md>
- pnpm — release notes index: <https://pnpm.io/blog?type=releases>
- Cargo Book — Workspaces: <https://doc.rust-lang.org/cargo/reference/workspaces.html>
- Cargo Book — Manifest: <https://doc.rust-lang.org/cargo/reference/manifest.html>
- rust-lang/cargo #11405 (member inclusion/exclusion): <https://github.com/rust-lang/cargo/issues/11405>
- Go Modules Reference — `go.work`: <https://go.dev/ref/mod#go-work-file>
- Go — `go work use` implementation: <https://go.dev/src/cmd/go/internal/workcmd/use.go>
- Go blog — Get familiar with workspaces: <https://go.dev/blog/get-familiar-with-workspaces>
- Go tutorial — Workspaces: <https://go.dev/doc/tutorial/workspaces>
- Go — Toolchain (`toolchain` directive): <https://go.dev/doc/toolchain>

**Rejected / deprioritized**
- Third-party "monorepo tooling" blogs and AI-generated comparison pages — secondary, partly
  synthesised; agree with the primary docs but add nothing citable.
- `rustwiki.org`, `golang.google.cn`, `pnpm.cn` mirrors — cite the canonical host instead.
- `dev-doc.rust-lang.org` beta/nightly renderings — same content as stable, version noise.

---

## 11. 中文要点（给维护者速览）

- **npm**：根 `package.json` 的 `workspaces`，字符串数组，元素是目录 glob（`*` 恰好一层，`**`
  多层）；**没有** `!` 排除的官方文档，别依赖；根目录本身不是包；嵌套是否算包**只看模式是否命中**，
  不由嵌套关系自动决定。
- **Yarn**：同一字段；Yarn 1 还允许对象形式 `{packages, nohoist}`（`nohoist` 是提升例外，不是
  排除），Yarn 2+ 只接受数组。
- **pnpm**：`pnpm-workspace.yaml` 的 `packages:`，支持 `!` 排除，路径相对 YAML 所在目录；
  `catalog:` 等字段只管依赖版本，**不影响包集合**；**有 YAML 就以 YAML 为准**，两者冲突只读 YAML
  并告警，无 YAML 时新版 pnpm（约 ≥12.7）会用 `package.json.workspaces` 生成 YAML。
  只有 `package.json` 没有 `workspaces` + 有 YAML → 以 YAML 为准。
- **Cargo**：`[workspace] members` 支持 glob；`exclude` 从 `members` 结果里挖洞（它自己是否支持
  glob 文档含糊）；`default-members` 只是根目录下 cargo 命令的默认子集，**不是**包集合；虚拟清单
  （只有 `[workspace]`）的根不是包，`[package]`+`[workspace]` 的根是包；嵌套 `[workspace]` 自成
  一套，不并入外层。
- **Go**：`go.work` 的 `use` 支持单值与块形式、相对（相对 `go.work` 所在目录）与绝对路径，
  **不支持任何通配**（官方）；递归靠 `go work use -r`。`go.work` 常被 gitignore，所以**新克隆
  可能没有 `go.work` 却有多个 `go.mod`**——不能据此判定"单模块"。
- **跨生态**：不是一个"谁赢"的问题；各生态各管自己。**清单只用来判断"谁声明了当前 cwd"**，
  显示串取**距离 cwd 最近的声明**；库存层面取并集并按 `realpath` 去重，保留生态标签。
- **三条决策重点**：(a) `apps/*` 不能用字符串前缀匹配（会误吃 `apps/web/sub`），也不需要全盘
  扫描——用"路径对模式"的单条 glob 匹配；只有做"列出全部包"时才需要展开，且可据模式深度设上限。
  (b) 规范路径 = **展开后目录的 realpath 相对 workspace root**，不是声明的模式串；显示串优先用
  清单里的 `name`（Go 用 `module` 路径），其次相对 git root 的路径，最后 basename；两者都要存。
  (c) 优先级：同生态内 pnpm YAML > JSON、Cargo/Go 取最近祖先；跨生态取最近声明，同目录冲突按
  pnpm > npm > Cargo > Go 兜底。
