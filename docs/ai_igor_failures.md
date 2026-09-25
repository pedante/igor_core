# Igor AI — Observed Runtime Failures and UX Issues

This document records AI/session failures and behavioral problems observed during manual use of Igor.

These failures are **not output from Astra and should not be attributed to Astra**.

Astra previously performed an AI architecture review and implementation pass documented in `aireport.md`. The observations below came from subsequent manual Igor sessions and are useful as regression evidence against the current implementation.

This file is intentionally an **evidence/behavior document**, not the authoritative architecture specification.

For intended AI architecture and historical implementation decisions, see:

* `aireport.md`
* `AGENTS.md`

---

## Purpose

Use these observations to:

* reproduce real AI/session failures,
* create deterministic regression tests,
* verify architecture contracts under actual interaction,
* prevent fixes from addressing only synthetic unit-test scenarios,
* preserve examples without repeatedly pasting large terminal transcripts into Codex sessions.

When a problem is fixed, keep the observation here as regression history and mark its status rather than deleting the evidence.

---

# 1. Provider tool transaction failure

## Observed behavior

Provider:

```text
OpenRouter
```

Model:

```text
anthropic/claude-sonnet-4-6
```

During an AI investigation, the model requested tools and Igor executed them.

The following provider error then occurred:

```text
HTTP 400
tool_use ids were found without tool_result blocks immediately after
```

This occurred more than once.

One observed sequence was:

```text
assistant requests multiple tools
    ↓
Igor executes tool calls
    ↓
Igor enters continuation flow
    ↓
next provider request
    ↓
HTTP 400 because tool_use IDs do not have the required tool_result structure
```

Igor displayed:

```text
Igor listed 2 actions — running the first now; rest follow as continuation steps.
```

The provider subsequently rejected the reconstructed conversation.

## Important implication

A single assistant turn containing multiple tool calls must remain a coherent provider transaction.

Sequential internal execution must not split or reorder the provider-level relationship between:

```text
assistant tool_use A
assistant tool_use B
```

and:

```text
tool_result A
tool_result B
```

A failed, denied, truncated, or otherwise unsuccessful tool invocation must still resolve the corresponding tool transaction.

## Regression requirement

Test at least:

* one successful tool call,
* one failed tool call,
* multiple tool calls in one assistant turn,
* first of multiple tools failing,
* user-denied tool,
* policy-denied tool,
* truncated result,
* provider failure after execution,
* history persistence/resume.

---

# 2. Provider failure incorrectly reported as normal completion

## Observed behavior

After a provider/protocol failure, Igor continued and later displayed output equivalent to:

```text
Steps completed: 1
Last action: no action
Status: no further actions needed
```

This is misleading.

A provider request failure is not equivalent to:

```text
no action needed
```

## Expected behavior

The session state must distinguish at least:

```text
completed successfully
provider failed
tool failed
user declined
user stopped
continuation limit reached
no further action requested
```

A provider failure must remain visible as a provider/session failure and must not silently collapse into successful completion.

---

# 3. Read-only commands classified as modifying the system

## Observed behavior

Several clearly read-only commands were presented as:

```text
NEEDS APPROVAL (modifies system)
```

Examples included:

```bash
journalctl -b 0 -p warning --no-pager | tail -50
checkupdates 2>/dev/null | wc -l
checkupdates 2>/dev/null | head -40
checkupdates 2>/dev/null | tail -30
pacman -Qi vlc
pacman -Qi vlc 2>&1 | grep -E "..."
vlc --version 2>/dev/null | head -2
```

These commands observe system state and do not modify it.

## Expected behavior

Read-only pipelines should remain READ when every component is read-only.

Examples:

```text
READ | READ = READ
```

Stderr redirection such as:

```bash
2>/dev/null
```

must not cause a command to become CHANGE.

Read-only filters such as:

```text
grep
head
tail
wc
```

must not upgrade an otherwise read-only command.

Mutating commands must still be classified appropriately.

Examples:

```bash
systemctl restart ...
pacman -S ...
pacman -Syu
rm ...
docker stop ...
```

---

# 4. Normal package installation classified as destructive/data-loss operation

## Observed behavior

The command:

```bash
sudo pacman -S --noconfirm vlc
```

was presented as:

```text
DESTRUCTIVE — DATA LOSS POSSIBLE
```

Normal package installation modifies the system but is not inherently a destructive/data-loss operation.

## Expected behavior

The safety model should distinguish meaningfully between:

```text
READ
CHANGE
DESTROY
```

For example:

### READ

```text
inspection
status queries
logs
package information
```

### CHANGE

```text
package installation
package upgrade
service restart
configuration modification
service enable/disable
```

### DESTROY

```text
explicit file/data deletion
filesystem formatting
destructive database operations
high-risk package removal
irreversible destructive operations
```

A CHANGE may still require approval according to configured policy.

---

# 5. Failed tool calls must still produce structured results

## Observed behavior

A tool intended to read Igor's terminal log failed with:

```text
tail: cannot open '.../data/runtime/terminal.log' for reading:
No such file or directory

exit code: 1
```

The surrounding continuation/provider behavior did not correctly preserve the failed tool transaction.

## Expected behavior

A failed execution is still a result.

The canonical result representation should be capable of preserving:

```text
request ID
tool-call ID
tool/action
owner
classification
approval state
execution status
exit code
stdout
stderr
error type
truncation metadata
```

A non-zero exit code must not make the provider-level tool result disappear.

---

# 6. Wrong tool semantics for system logs

## Observed behavior

For the request:

```text
check warnings in boot logs
```

Igor later attempted to use a tool associated with Igor's own terminal/session log.

That tool looked for:

```text
data/runtime/terminal.log
```

This is different from the system boot journal.

## Expected behavior

AI tool metadata should clearly distinguish:

```text
Igor session/terminal logs
system journal
service logs
bounded file reading
host diagnostic commands
module-specific actions
```

The model should not need keyword shortcuts to distinguish these concepts.

Tool names/descriptions and schemas should make their semantics clear.

---

# 7. Session resume must not restore malformed provider transactions

## Observed behavior

AI sessions can start with:

```text
Resuming investigation state from last session
```

This raises a correctness requirement when a prior session ended in the middle of a tool transaction.

## Required behavior

Investigation/WIP state and provider conversation state must not be treated as identical.

Test interruption at least:

```text
after assistant tool request but before execution
after first of several tool calls
after execution but before continuation request
while waiting for approval
after provider failure
```

A resumed session must either:

* restore a coherent pending transaction,
* safely resolve/close it,
* or start a clean provider conversation while retaining only provider-neutral investigation state.

Malformed partial provider history must never be replayed as valid conversation state.

---

# 8. Hostname discovery portability failure

## Observed behavior

Startup/system scanning produced:

```text
hostname: invalid option -- 'I'
```

## Expected behavior

Igor must not assume:

```bash
hostname -I
```

exists on every supported environment.

Address detection should:

* detect support,
* use a portable fallback when necessary,
* avoid simply suppressing the error,
* be covered by deterministic tests.

---

# 9. Contradictory scrub/privacy status

## Observed behavior

Igor displayed:

```text
WARNING: Potential sensitive content remaining after scrubbing
DEBUG: Scrubbing validation detected potential issues
```

and then output equivalent to:

```text
✔ Server state captured and scrubbed.
Sensitive values replaced before API call.
```

Later sessions similarly showed:

```text
WARNING: Potential sensitive content remaining after scrubbing
DEBUG: Scrubbing validation detected potential issues
✔ Context refreshed.
```

The messages describe different states but are presented in a way that can imply successful privacy validation.

## Expected behavior

Distinguish:

```text
context collection succeeded
redaction completed
redaction validation passed
redaction validation warned
provider transmission allowed
provider transmission blocked
```

Successful context collection must not imply that privacy validation passed.

Do not weaken final request-boundary redaction.

---

# 10. Context reporting inconsistency

## Observed behavior

One session reported:

```text
Sections: 0 context blocks
```

immediately after system/context collection.

Later sessions reported:

```text
Sections: 2 context blocks
```

and otherwise behaved more correctly.

## Required verification

Trace:

```text
context collection
    -> reference representation
    -> request boundary
    -> final redaction
    -> provider payload
```

Tests should verify actual provider payload contents rather than relying solely on the UI counter.

At minimum cover:

```text
IGOR_AI_CONTEXT=standard
IGOR_AI_CONTEXT=minimal
```

---

# 11. Built-in command/help output is misaligned

## Observed behavior

Session help displayed command/description mappings similar to:

```text
── Session

[exit]
[refresh]  exit / quit
[stats]    re-scan context
[solved]   context size + cost

── Control

[exec on/off]     clear investigation
[quiet on/off]    TIER 2 auto-run
[verbose on/off]  hide READ steps
[stop]            show reasoning
[continue]        /stop pause loop
```

Descriptions appear offset from the commands they describe.

Similar misalignment occurs in other sections.

## Expected behavior

Built-in commands should have one authoritative definition containing, as appropriate:

```text
canonical command
aliases
syntax
description
handler
```

Help output should be generated from that definition rather than independently maintained parallel lists.

Built-in commands should be intercepted deterministically before ordinary input reaches the LLM.

---

# 12. `/cmd` behaved as an AI request instead of a deterministic session command

## Observed behavior

Entering:

```text
/cmd
```

caused Igor to start investigating repository/log files instead of deterministically handling the built-in command.

## Expected behavior

Session commands must be parsed before ordinary model input.

The LLM should not infer the semantics of Igor's internal command language.

Unknown or incomplete command syntax should produce a deterministic local response.

---

# 13. Prompt-ready controls were duplicated

## Observed behavior

The prompt-ready UI displayed:

```text
[Enter] start  [v] view  [e] edit  [q] cancel
```

twice.

## Expected behavior

Prompt preparation should render one control prompt.

The issue should be fixed at the rendering/control-flow source rather than by suppressing duplicate strings after output generation.

---

# 14. Unsafe predictable prompt temporary file

## Observed behavior

A session produced:

```text
core/ai/core.sh: line ...: /tmp/igor_prompt_last.txt: Permission denied
```

A predictable global temporary filename can collide with:

* old root-owned files,
* another user,
* another Igor process,
* stale state,
* unsafe symlinks.

## Expected behavior

Sensitive prompt/runtime storage should use Igor-owned/session-owned secure storage.

Requirements include:

```text
user ownership
mode 0600 where sensitive
safe temporary creation
no predictable global collision
parallel-session safety
appropriate cleanup
symlink safety
```

---

# 15. Action success and verification success were conflated

## Observed behavior

The user requested:

```text
install vlc
```

The package-manager operation completed successfully with:

```text
exit 0
```

Igor then attempted independent verification with commands such as:

```bash
vlc --version
pacman -Qi vlc
```

The verification commands were declined.

Igor eventually reported approximately:

```text
RESULT: STATUS=BLOCKED
```

and:

```text
Cannot confirm the change without a tool result.
```

However, there was already a tool result for the installation action itself.

## Expected behavior

Distinguish:

```text
action result
verification result
```

For this case the semantics should be equivalent to:

```text
installation: succeeded
independent verification: not performed / user declined
```

not:

```text
installation blocked
```

Do not fabricate verification, but do not discard valid action evidence either.

---

# 16. Repeated verification attempts after user denial

## Observed behavior

After the user declined one verification command, Igor queried the model again and proposed a materially equivalent verification.

After another denial, another continuation occurred.

## Expected behavior

A user denial should be represented to the model, but the coordinator should prevent pointless repeated attempts at the same or materially equivalent operation during the same task.

The user should not have to repeatedly reject equivalent verification commands.

---

# 17. `/stop` control semantics are unclear

## Observed behavior

During an approval prompt, the user attempted:

```text
/stop
```

Igor treated it as if the proposed command had simply been declined and continued the investigation.

## Expected behavior

At a supported control point:

```text
n
```

means:

```text
decline this action
```

while:

```text
/stop
```

means:

```text
cancel pending action
stop continuation
return to normal Igor input
```

These are separate state transitions.

No additional provider query should occur after a successful session stop.

---

# 18. It is unclear when session commands can be entered

## Observed behavior

The continuation UI advertised:

```text
/stop to pause
```

while Igor was actively producing output.

The user began typing:

```text
/stop
```

because there was no obvious dedicated input location.

The user's keystrokes visually interleaved with Igor output, producing fragments such as:

```text
/sLet me verify...
t    step 3/5 ...
```

These fragments are **not primarily random terminal corruption**.

They are evidence of an unclear terminal input/control model.

## Expected behavior

The current line UI must clearly define:

* when the user owns the input line,
* when Igor owns terminal rendering,
* where `/stop` is accepted,
* whether commands can be entered while the model is querying,
* what happens to normal text entered during continuation.

Do not advertise:

```text
/stop to pause
```

during a state in which `/stop` cannot safely be consumed.

A future full-screen TUI may provide permanent input ownership, but the current line UI still needs deterministic behavior.

---

# 19. Update-status investigation performed redundant reads

## Observed behavior

For:

```text
is the system up to date?
```

Igor executed:

```bash
checkupdates | wc -l
checkupdates | head -40
checkupdates | tail -30
checkupdates | head -39
```

The final read substantially duplicated information already obtained.

## Expected behavior

Structured tool results should provide enough truncation metadata for efficient continuation where practical.

Useful metadata may include:

```text
truncated
returned lines
original line count
omitted lines
output byte count
```

The model should not need to guess which part of output was omitted.

Do not implement application-specific package logic in the generic continuation loop merely to solve this example.

---

# 20. Current positive behavior that must not regress

Later manual testing showed significant improvement.

The following behaviors were observed working and should be preserved:

* context blocks were present,
* multi-step provider/tool interaction completed without the previous HTTP 400,
* tool results survived continuation,
* user-denied actions were represented,
* history summarization did not corrupt the provider transaction,
* an authorized package installation executed successfully,
* the AI produced final responses after multi-step investigations.

Regression work must preserve these improvements while fixing the remaining issues.

---

# Status tracking

Use the following values when updating an issue:

```text
OPEN
IN PROGRESS
FIXED — NEEDS MANUAL VERIFICATION
VERIFIED
REGRESSION
```

Current status should be determined from the working tree and tests rather than assumed from this document.

This document intentionally records historical observations even after fixes are implemented.

---

# Relationship to the AI roadmap

The planned AI/UI evolution is:

```text
1. Finish current AI correction pass
2. Canonical command/action registry and command-palette foundation
3. Yes / No / Explain approval workflow
4. Guide / Assist / Executive interaction modes
5. Structured frontend event stream
6. Basic lightweight full-screen TUI
7. Richer palette/history/search/activity UX
```

Issues in this document primarily provide evidence for Step 1.

Future UI work should not begin by hiding unresolved backend state, execution, authorization, provider, or persistence problems behind a new interface.
