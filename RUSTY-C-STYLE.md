# Rusty C

A portable extract of how Rusty Russell writes C, taken from Core
Lightning: the written style guide, the `check-source` regulation,
the headers that encode ownership and typesafety, the tutorial
`/*~` comments, and the full author history on `master`
(`Rusty Russell <rusty@rustcorp.com.au>`, 9,248 commits,
2015-05-26 through 2026-02).

This file is meant to travel.  Drop it in another tree.  It is not a
CLN tour and it is not a style sampler.  It is the regulation.

Exceptions exist.  Particularly if they are funny.

---

## 0. The one-line rule

If you do not know the right thing, do the simplest thing.

Unused code is buggy code.  Do not overdesign.  Start with a brute
force list.  Rewrite simple code later.  Leave `/* FIXME: ... */`
for the compromise you shipped.

We communicate with each other via code.  Polish each others' code.
Give nuanced feedback.

---

## 1. Mechanical form

The C is Linux-like.

| Rule | Regulation |
| --- | --- |
| Indent | Tab characters.  Visual width 8. |
| Line length | Prefer 80 columns.  Stop somewhere. |
| Line break | Align parameters and arguments under the first. |
| Names | As short as still descriptive.  `num_foos` not `number_of_foos`.  `i` not `counter`.  `bool found` not `bool ret`. |
| Statements | Prefer simple statements.  Do not combine unrelated tests.  Early `continue` / early return instead of deep indent. |
| Static / const | Everything static and const by default.  `tal_free()` accepts const and returns `NULL`. |
| Headers | `config.h` first.  Include guard `LIGHTNING_<PATH>_H` in CLN; in another tree, one unique path-based guard. |
| Locale | Call `setup_locale()` from `main` (and test mains).  Do not assume C locale. |
| Spelling (CLN) | `lightning` not `lightening`.  `CLTV` not `CLTV_expiry` inventions.  Check the project word list. |

When a line must wrap:

```c
static void subtract_received_htlcs(const struct channel *channel,
				    struct amount_msat *amount)
```

When a loop grows teeth, extract a function or use the continue-ladder:

```c
	for (i = start; i != end; i++) {
		if (i->something)
			continue;
		if (!i->something_else)
			continue;
		do_something(i);
	}
```

Combine conditionals only when they are one idea:

```c
	if (i->something != NULL && *i->something < 100)
```

`.clang-format` in CLN is:

```
BasedOnStyle: llvm
IndentWidth: 8
UseTab: Always
BreakBeforeBraces: Linux
AllowShortIfStatementsOnASingleLine: false
IndentCaseLabels: false
```

That is the floor, not the style.  The style is the rest of this
document.

---

## 2. Variables: late, once, typed

Do not double-initialize.  Declare, then set on every path when the
value is known.  The compiler then warns about a path you forgot.

```c
	bool is_foo;

	if (bar == foo)
		is_foo = true;
	else
		is_foo = false;
```

Wrong: `bool is_foo = false;` then maybe set it.  A later edit that
misses a path compiles and is wrong.

Same idea for memory.  Prefer `tal` / `tal_arr` to `talz` /
`tal_arrz`.  Valgrind should see uninitialized memory if you branch
on a field you never set.  Initialize only the fields you will use.
Use `memcheck(mem, len)` when handing a buffer to a queue so
valgrind fires at the producer, not the consumer.

Typesafety is worth pain.  Changing a type and compiling is how this
code is refactored.

- Wrap scalars that must not be mixed (`struct amount_msat`,
  `struct amount_sat`, `struct short_channel_id`, …).
- Use `structeq` generated comparators, not `memcmp` on structs.
- Use `ARRAY_SIZE(arr)` so a pointer will not compile.
- Use `typesafe_cb` so a callback's argument type is checked.
- Use `u8 u16 u32 u64 s8 …` from `ccan/short_types`.
- Use `streq` / `strstarts` / `memeq` / `memeqzero`, not ad-hoc
  `strcmp` / `memcmp` soup.
- Annotate printf-like functions with `PRINTF_FMT` / `PRINTFUNC`.
- Mark deliberately unused parameters `UNUSED`.

Do not cast away the wrapper to get a cheaper API.

---

## 3. Ownership: tal, take, STEALS, tmpctx

Memory is a tree.  `tal` allocates a child of a parent.  Freeing
the parent frees the children.  That is the whole model.

### 3.1 Parents

- Pass the real owner as the parent.
- If you are allocating only to hand off with `take()`, parent is
  `NULL`.
- Do not hang temporaries off a convenient long-lived object.
  That is the old habit.  Use `tmpctx`.

### 3.2 `tmpctx`

A process-global throwaway parent, wiped regularly (end of a
command, end of an io callback, etc.).

- Use it for anything that must not outlive the current turn.
- **Never `tal_free(tmpctx)`.**  The checker is literal:
  `Don't free tmpctx!`
- Do not call `setup_tmpctx()` twice.

### 3.3 `take()` / `TAKES`

`TAKES` on a formal parameter is documentation: this argument may
be passed as `take(ptr)`.

`take(ptr)` marks the pointer.  The callee calls `taken(ptr)`
**once**.  If true, it now owns the pointer and must free or
reparent it.  If false, it must copy if it wants to keep it.

- `take(NULL)` is legal (error pass-through).
- Only pass `take()` to a `TAKES` parameter.  Otherwise you leak.
- Generated marshalling (`towire_*` consumers that are not marked)
  does **not** take.
- `taken()` un-takes.  `is_taken()` peeks.  `taken_any()` is for
  leak checks.

```c
	msg = towire_shutdown(NULL, &peer->channel_id,
			      peer->final_scriptpubkey);
	enqueue_peer_msg(peer, take(msg));
```

### 3.4 `STEALS`

`STEALS` on a formal means the function **always** takes ownership
of that tal pointer, whether or not the caller used `take()`.
Different from `TAKES`.

### 3.5 Helpers that come with the model

- `tal_count(p)` / `tal_bytelen(p)` — both define `NULL` as 0.
- `tal_dup` / `tal_dup_arr` / `tal_dup_talarr` for copies.
- `notleak(p)` when something is deliberately immortal and the
  leak scanner must ignore it.
- `tal_add_destructor` when an object must detach from a list or
  close an fd on free.

If a function can fail after stealing, either steal only on the
success path or document the failure cleanup.  There are commits
whose entire point is "remove take() leak if foo() fails."

---

## 4. Amounts

`struct amount_msat` and `struct amount_sat` exist so you cannot
add sats to msats, overflow silently, or print the wrong unit.

Regulation, enforced by `check-amount-access`:

- Do not read or write `.satoshis` / `.millisatoshis` except next
  to `/* Raw: */`, and almost never outside `common/amount.[ch]`,
  tests, and fuzzers.
- Do not cast to `struct amount_msat` / `struct amount_sat` except
  `sizeof`.
- Build runtime values with the ops (`amount_msat_add`,
  `amount_msat_sub`, `amount_msat_eq`, `amount_msat_greater`,
  `amount_msat_add_sat`, …).  Those are `WARN_UNUSED_RESULT`
  because they can overflow: **check the bool**.
- Build constants with `AMOUNT_MSAT(n)` / `AMOUNT_SAT(n)` (n must
  be a compile-time constant) or `AMOUNT_MSAT_INIT` /
  `AMOUNT_SAT_INIT` for static initializers.
- Format with `fmt_amount_msat` / `fmt_amount_sat` (and the `_hex`
  variants).  Do not `%llu` a member.

An amount in a wire or JSON field is not an invitation to invent a
second `u64`.  Keep it wrapped until the edge that must serialize.

---

## 5. Control flow that matches the type

### 5.1 Enum switches

If you `switch` on an enum, name every enumerator.  **No
`default:`.**  A new enumerator then fails the build.  This is
mandatory for values generated from the spec.

`default:` appears in the tree for non-enums (characters, integers,
or a documented "this protocol version cannot see more cases"
situation).  That is the exception, not the style.

### 5.2 `goto`

Allowed for shared cleanup, matching Linux.  Not a religion either
way.  Prefer the cleanup label over a six-level indent.

### 5.3 Must-return result types

Several APIs return a type you must not ignore:

- `struct command_result *` — every JSON command path returns one.
  `command_fail`, `command_success`, `command_check_done` are
  `WARN_UNUSED_RESULT`.
- Amount ops — see above.
- Anything marked `WARN_UNUSED_RESULT`.

A command handler looks like this, every time:

```c
	if (!param(cmd, buffer, params,
		   p_req("thing", param_…, &thing),
		   p_opt("maybe", param_…, &maybe),
		   NULL))
		return command_param_failed();

	if (command_check_only(cmd))
		return command_check_done(cmd);

	if (bad)
		return command_fail(cmd, CODE, "human sentence");

	return command_success(cmd, json);
```

`param_check` is the variant that parses without side effects.
`command_usage_only` is the `--help` path.  Do not write to the db
or the network before you have finished parameter checks.

Fail messages are sentences a human can grep.  Quote the bad value.
Do not invent a parallel error string for the same check: put the
check where the value is consumed and let that error speak.

### 5.4 Assertions vs fatals vs broken

| Call | When |
| --- | --- |
| `assert` | Internal invariant.  Can vanish under `NDEBUG`.  Not for peer input. |
| `abort` | Same, when you must die even if asserts are off.  Rare. |
| `fatal` / `status_failed` | Daemon cannot continue.  Operator-visible. |
| `status_broken` / `log_broken` | We are surprised.  We can continue.  This is a bug we should hear about. |
| `status_unusual` / `log_unusual` | Peer or environment is weird, not necessarily us. |
| `status_debug` / `log_debug` | Development noise. |

Do not `assert` that a peer sent a valid message.  Fail the
connection or the command.

---

## 6. Functions the checkers ban

`check-discouraged-functions` rejects these in project `*.c` / `*.h`
(not `ccan/`, not `contrib/`) unless the call site has
`/* discouraged: */` and a reason:

- `fgets` `fputs` `gets` `scanf`
- `sprintf` (use `tal_fmt`, `snprintf`, or a bounded helper)
- `randombytes_buf` (use the project RNG wrapper)
- `time_now` (use `clock_time()` so tests can override; tracing
  is the documented exception)

Also banned:

- `tal_free(tmpctx)`
- printf conversion `%*.s` (`check-bad-sprintf`)
- direct amount member access without `/* Raw: */`

Whitespace, include order, BOLT quotation, and `setup_locale` are
the same class of rule: the tree must pass `make check-source`
without compiling.

---

## 7. Comments

### 7.1 `FIXME`

Two legal uses:

1. An optimization that is not yet clearly worth it.
2. An ugly corner you are shipping anyway, maybe fixed in the next
   patch.

`FIXME` is grep-fodder.  It is a warning sign when a bug lands
nearby.  It is not a TODO pile and it is not a personal bookmark.

Other authors write `TODO(name)`.  Rusty writes `FIXME`.  The
tutorial in `hsmd` says so explicitly.

### 7.2 `/*~` tutorial comments

A handful of daemons are written as a guided tour
(`lightningd/lightningd.c`, `hsmd/hsmd.c`, `connectd/connectd.c`,
`openingd`, `channeld` in places).  Those comments start `/*~` and
teach the next reader why the file exists and how the pieces lock.

Do not sprinkle `/*~` through ordinary code.  Write them when you
are introducing a subsystem that someone will read top to bottom.

### 7.3 What not to comment

Do not narrate the next line.  Do not leave commented-out code.
The commit message holds the why that does not belong in the file.

BOLT citations are a special case.  Quote the spec next to the
implementation.  `check-source-bolt` wants those quotes to match
the BOLT text at a pinned revision.

---

## 8. JSON, RPC, and wire

- Every JSON-RPC result is a **top-level object**.  Never a bare
  array or a bare scalar.  Objects let you add `warning_*` and
  other optional fields later.
- Reuse JSON field names already in the project, or names from the
  BOLTs.  Do not invent a synonym.
- New fields are additive.  Removing or changing meaning goes
  through deprecation (`deprecated_apis`, start/end version,
  `command_deprecated_in_ok` / `command_deprecated_out_ok`).
- Schemas are the API.  If the command is user-facing, the schema
  and the examples are part of the patch.
- Wire structs are generated.  Do not hand-edit `*_wiregen.*`.
  Change the CSV / template and regenerate.
- Enumerations that come off the wire are switched without
  `default:` so a new type is a compile failure.

---

## 9. Tests

- A failing test first, then the fix, when you are hunting a bug.
  `xfail` / expected-fail is legitimate scaffolding; do not leave
  it once the fix landed.
- Unit tests in C often `#include` the `.c` under test
  (`common/test/run-amount.c` includes `../amount.c`) so they can
  reach statics.  That is deliberate.
- Pytest is for daemon interaction.  Do not sleep to win a race.
  Wait on the condition.
- Valgrind and asan are first-class.  Uninitialized reads are
  style bugs, not just memory bugs.
- Flakes are fixed or deleted.  A test that "usually" passes is
  not a test.
- Do not put exploit payloads in the tree.  Reproduce with
  honest inputs and an assertion about the invariant.

---

## 10. Commits: the regulation in the history

Measured on `master`, author `Rusty Russell <rusty@rustcorp.com.au>`,
9,248 commits (2015-05-26 … 2026-02).

### 10.1 Subject

```
subsystem: imperative sentence
```

- 96% of subjects have a `subsystem:` prefix
  (`lightningd`, `pytest`, `gossipd`, `channeld`, `common`,
  `connectd`, `wallet`, `doc`, `Makefile`, `askrene`, `libplugin`,
  `onchaind`, `db`, `ccan`, `hsmd`, `offers`, `pay`, `CI`, …).
- After the prefix the first letter is **lowercase** (8,860 vs 387).
- Imperative, not past tense (fix / add / don't / remove / use /
  make / update / test / allow / handle / move / rename /
  simplify).  `don't` is a first-class verb.
- Average length 52 characters.  90th percentile 73.  Stay near
  72.  The subject is the intent, not the diffstat.
- One logical change.  Reviewable.  Bisectable.  If the test and
  the fix are clearer as two commits, they are two commits.
- Reverts are `Revert "original subject".`

Subjects that do not fit `foo:` are rare and specific: `Revert`,
`BOLT update:`, `BOLT catchup:`, a release-note commit, or a
multi-subsystem `foo, bar:`.

### 10.2 Body

- 25% of commits are subject + trailers only.  That is allowed
  when the subject is the whole story.
- The other 75% explain **why**, not what `git show` already
  shows.  Median body ~124 characters.  Write until the reviewer
  does not have to guess.
- Quote the bad string, the log line, or the spec sentence when
  the commit is a bugfix.  Future grep depends on it.
- Do not apologize.  Do not advertise.  Do not add a cover letter
  for a one-line change.

### 10.3 Trailers (almost every commit)

| Trailer | Role |
| --- | --- |
| `Signed-off-by: Rusty Russell <rusty@rustcorp.com.au>` | Required.  DCO.  9,116 of 9,248. |
| `Changelog-Added:` | User-visible new thing. |
| `Changelog-Changed:` | User-visible behavior change. |
| `Changelog-Fixed:` | User-visible bug. |
| `Changelog-Removed:` | User-visible removal. |
| `Changelog-Deprecated:` | Start of a removal clock. |
| `Changelog-EXPERIMENTAL:` | Behind an experimental flag. |
| `Changelog-None:` | Explicitly not user-visible.  Use when a reviewer would wonder. |
| `Fixes:` | Issue or bug id. |
| `Closes:` | Issue closed by this. |
| `Reported-by:` | Credit.  Common. |
| `Suggested-by:` | Credit. |
| `See-also:` | Related commit or issue. |

If user-visible behavior changes and there is no `Changelog-*`
trailer, the commit is unfinished.

Internal cleanups usually have no changelog trailer (or
`Changelog-None`).  Do not slap `Changelog-Fixed` on a comment
typo.

### 10.4 Patch series

- Rebase, do not merge.
- Each commit compiles and passes the tests it claims to.
- Do not mix a refactor with a behavior change.
- Draft PRs are for CI and conversation, not review pressure.
- Review notes go into the next revision of the commits, not a
  pile of "fixup after review" commits on master.

---

## 11. How he actually changes a program

This is the part the written guide does not say and the 9,248
commits do.

1. **Keep the check next to the use.**  Do not invent a second
   field to remember that you already checked.  If `xpay_core`
   already refuses a mismatched amount, fill in the amount you
   authorized and let that check fire.  A parallel
   `authorized_msat` is the non-Rusty patch.
2. **Delete the unused thing in the same breath.**  Subjects of
   the form `foo: remove unused bar` are a drumbeat.  Dead
   parameters, dead flags, dead type fields, dead helpers after
   the last caller died.
3. **`don't` is a design.**  A huge fraction of subjects are
   "don't crash", "don't assume", "don't loop all commands",
   "don't start a transaction unless we need one".  The patch
   removes a special case or a hidden cost, it does not add a
   framework.
4. **Make the common path boring.**  Slow, rare, or ugly work is
   pushed off the hot path (compaction not on startup, no INFO log
   for a known peer bug, no db transaction for a read-only RPC).
5. **Name the subsystem, then the intent.**  If you cannot name
   the subsystem, the patch is too big or in the wrong file.
6. **Prefer a smaller API to a smarter one.**  `minflow()` becomes
   `static`.  A flag that is always the same value disappears.
   A helper used once is inlined or the caller is moved next to
   it.
7. **Types over convenience.**  A new `u64` that happens to be
   millisatoshis is a bug you have not written yet.
8. **Fail closed on money and on state.**  Overflow returns
   false.  A missing enum case does not compile.  A peer you do
   not understand is disconnected, not guessed.
9. **Logs are for operators and for future you.**  `broken` means
   we have a bug.  `unusual` means they do.  Do not log every
   rejected gossip message at info.
10. **Rewrite beats configure.**  When the right shape appears,
    the old function is deleted, not parameterized into a maze.

---

## 12. A checklist before you send the patch

Mechanical:

- [ ] Tabs, width 8, ~80 columns, Linux braces
- [ ] `config.h` first, path include guard
- [ ] `setup_locale()` if you added a `main`
- [ ] No `sprintf` / `time_now` / `fgets` / `tal_free(tmpctx)`
- [ ] No `.millisatoshis` without `/* Raw: */`
- [ ] Enum `switch` names every case
- [ ] New variables not pre-initialized "just in case"
- [ ] `take()` only into `TAKES`; `NULL` parent if allocated to take
- [ ] Temporaries on `tmpctx`
- [ ] `WARN_UNUSED_RESULT` honoured
- [ ] JSON result is an object
- [ ] Schema / BOLT quote / changelog trailer if user-visible

Judgement:

- [ ] This is the simplest thing that is correct
- [ ] No unused helper, parameter, or field left behind
- [ ] The check lives at the use, not in a shadow variable
- [ ] Subject is `subsystem: lowercase imperative`
- [ ] Body says why, or is honestly empty
- [ ] `Signed-off-by` and the right `Changelog-*`
- [ ] One idea per commit, bisectable

---

## 13. Porting this to another tree

Take the rules, not the filenames.

| CLN mechanism | What to reproduce |
| --- | --- |
| `tal` + `tmpctx` | Hierarchical allocator, one turn-scoped ctx you never free |
| `take` / `TAKES` / `STEALS` | Documented ownership in the signature |
| `struct amount_*` | Wrapper types for any unit you must not mix |
| `typesafe_cb`, `ARRAY_SIZE`, `structeq` | Make the compiler do the review |
| `check-source` recipes | Grep-level bans: tmpctx free, sprintf, raw amount, include order |
| `FIXME` | Grep-fodder for shipped compromises |
| `subsystem: intent` + DCO + Changelog trailers | History that a human can read ten years later |
| No `default:` on spec enums | New protocol values fail the build |
| JSON always an object | Additive API |

Do not take the jokes out.  Do not add a linter for taste.  Lint
what a computer can prove; leave "simplest thing" to review.

---

## 14. What this is not

- Not a copy of the Linux kernel guide.  Linux is the baseline
  for whitespace and bracing.  Ownership, amounts, commands, and
  commits are Rusty.
- Not a complete CCAN manual.  Import the modules you need
  (`tal`, `take`, `list`, `str`, `short_types`, `typesafe_cb`,
  `structeq`, `mem`, `time`, `io`) and keep their headers.
- Not permission to write a framework.  If the guide and the
  code disagree, the recent code on `master` by this author wins,
  then the checker, then this file.
