# Three coding agents on one local model, 2026-09-07

The same small task (TASK.md: add an `--ignore-punctuation` flag to a tiny word-counting CLI, add a test, make pytest pass, do not commit) given to three coding agents, each driving the same local server: Qwen3.8-27B W4A16 with the DFlash2 head on one RTX 4090 under WSL2, the syv-ai fork's vLLM 0.28 launcher at its shipped defaults (container `qwen-prod`, port 18020 on localhost). Each agent worked in its own clean copy of the sandbox repository. Times are wall clock from the agent's start to its exit.

| agent | how it reached the model | outcome | time | tokens |
|---|---|---|---|---|
| Codex CLI 0.153.4, clean home, sandbox bypassed, reasoning effort medium (run 4) | `/v1/responses` with function tools, `[model_providers.vllm]` in codex-home-config.toml | done: flag, library change, three tests, 5 passed, smoke-tested, uncommitted | 110 s | 32,599 |
| Codex CLI, the seats' home (their AGENTS.md pointer), effort low (run 1) | same | half done: the library change only, then ended its turn narrating | 176 s | 107,453 |
| Claude Code 2.1.226 headless, `--model qwen3.8-27b`, bearer via `ANTHROPIC_AUTH_TOKEN` | `/v1/messages` (the fork's server speaks the Anthropic Messages API) | done: three files, two tests, 4 passed, CLI verified, plus a note on `string.punctuation` edge cases | 87 s | not printed in text mode |
| garrison (main @ 31f8e7d), `GARRISON_CHAT_BASE_URL` at the server, all four roles the same model, `--allow-exec` | `/v1/chat/completions` | the Python edits are right (5 passed, CLI verified) but the harness reported BLOCKED: its verifier ran `go build` and `go test`, and it wrote a stub go.mod and tally.go to satisfy them | 262 s | 42,279 |

## What the plumbing needed (the failures before the results)

- Codex: `--approve-for-me` routes approvals to a reviewer model it looks for at the same provider (`codex-auto-review`), so on a local provider every command is rejected; a project under a temp directory is untrusted and the sandbox drops to read-only. The run that worked used `--dangerously-bypass-approvals-and-sandbox` in a scratch repository, the way the seats run; a trusted-project entry in the home config would be the tidier fix. Codex also asks the provider for a model list in its own shape and logs a harmless error when vLLM answers in OpenAI's. `wire_api` must be `responses`; the fork's server serves it, tools included.
- Claude Code: refuses to start nested inside another Claude Code session (unset the `CLAUDE_*` variables); sends the key Anthropic-style (`x-api-key`) when `ANTHROPIC_API_KEY` is set, which vLLM's guard does not read (401), so use `ANTHROPIC_AUTH_TOKEN` for a bearer; warns that it does not recognise the model name and assumes a 200k window (the server's is 65,536).
- garrison: its oracle suite is Go-only today (the roadmap's "then multi-language"); on a Python project the model's correct work is judged by the wrong verifier.
- All three: `git clone` from Git Bash with path conversion disabled hands Windows git a `/c/...` path it cannot open; two agent runs were lost to that before the runs recorded here.

Files: `codex-run1.*`, `codex-run4.*`, `claude-local.log` + `claude-run1.diff`, `garrison-local.log` + `garrison-run1.diff`, `TASK.md`, `codex-home-config.toml`.
