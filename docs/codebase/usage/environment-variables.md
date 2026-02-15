# Environment Variables

## Host Runtime
- `CONTEXT_GRABBER_REPO_ROOT`: repo path for host bridge resolution.
- `CONTEXT_GRABBER_BUN_BIN`: explicit Bun binary path for app-launch environments.
- `CONTEXT_GRABBER_BROWSER_TARGET`: force browser routing (`safari` or `chrome`).

## Companion CLI
- `CONTEXT_GRABBER_REPO_ROOT`: repo path override for bridge package lookup.
- `CONTEXT_GRABBER_BUN_BIN`: explicit Bun binary for extension bridge execution.
- `CONTEXT_GRABBER_BROWSER_TARGET`: force capture target for `capture --focused` (`safari` or `chrome`).
- `CONTEXT_GRABBER_OSASCRIPT_BIN`: override AppleScript binary path for `list tabs` / `list apps`.

## Safari Bridge
- `CONTEXT_GRABBER_SAFARI_SOURCE`: `runtime`, `live`, `fixture`, or `auto` (`runtime -> live`; fixture is explicit).
- `CONTEXT_GRABBER_SAFARI_FIXTURE_PATH`: fixture override path.
- `CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD`: inline runtime JSON payload.
- `CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD_PATH`: runtime JSON payload file path.
- `CONTEXT_GRABBER_SAFARI_OSASCRIPT_BIN`: AppleScript executable override.

## Chrome Bridge
- `CONTEXT_GRABBER_CHROME_SOURCE`: `runtime`, `live`, `fixture`, or `auto` (`runtime -> live`; fixture is explicit).
- `CONTEXT_GRABBER_CHROME_OSASCRIPT_BIN`: AppleScript executable override.
- `CONTEXT_GRABBER_CHROME_FIXTURE_PATH`: fixture override path.
- `CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD`: inline runtime JSON payload.
- `CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD_PATH`: runtime JSON payload file path.

## Desktop Testing Overrides
- `CONTEXT_GRABBER_DESKTOP_AX_TEXT`: force AX text for host-side testing.
- `CONTEXT_GRABBER_DESKTOP_OCR_TEXT`: force OCR text for host-side testing.

## LLM Summarization
- `OPENAI_API_KEY`: OpenAI API key for LLM summarization.
- `OPENAI_BASE_URL`: custom OpenAI-compatible endpoint URL (default: `https://api.openai.com`).
- `ANTHROPIC_API_KEY`: Anthropic API key for LLM summarization.
- `ANTHROPIC_BASE_URL`: custom Anthropic-compatible endpoint URL (default: `https://api.anthropic.com`).
- `GEMINI_API_KEY` / `GOOGLE_API_KEY`: Google Gemini API key for LLM summarization (either variable is accepted).
- `GEMINI_BASE_URL`: custom Gemini-compatible endpoint URL (default: `https://generativelanguage.googleapis.com`).
- `OLLAMA_BASE_URL`: Ollama local server endpoint URL (default: `http://localhost:11434`).
