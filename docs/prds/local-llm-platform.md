# PRD: Local LLM Platform

## Outcome

Deploy a repeatable private two-GB10 coding platform: Qwen3.8 Flash-Next through vLLM, LiteLLM as the supported client gateway, metadata-only Langfuse traces, and Prometheus/Grafana operations visibility.

## Requirements

- Generate all runtime credentials locally in ignored mode-0600 `private/` files.
- Keep Qwen serving, LiteLLM, Langfuse, Prometheus, and Grafana private by default.
- Use `qwen3.8-flash-next` as the default local model alias.
- Forward Claude Code Max OAuth only for `anthropic-claude`; each client completes its own browser login.
- Disable prompt and completion retention by default.
- Provide repeatable bootstrap, health, backup, rotation, and named-only rollback runbooks.

## Acceptance

A fresh server pair can bootstrap from tracked templates plus protected runtime input; all services are healthy; and a completed Claude Code request yields safe usage metadata without retaining OAuth tokens or content.
