# Diagnostics and Troubleshooting

## Host Diagnostics Surface
`Run Diagnostics` reports:
- frontmost app routing target
- Safari transport status
- Chrome transport status
- desktop permission readiness (AX + Screen Recording)
- last capture timestamp/error/latency
- storage writability (verified by probe file write/remove in the active history directory)

The menu `Diagnostics Status` submenu mirrors the latest diagnostics snapshot with inline labels and a `Refresh Diagnostics` action.

## Common Failures
1. `ERR_EXTENSION_UNAVAILABLE`
- Browser runtime/AppleScript not reachable.
- Missing developer setting or automation permission.

2. `ERR_TIMEOUT`
- Bridge did not return within request timeout.
- Host falls back to metadata-only payload.

3. Desktop metadata-only fallback
- AX below threshold and OCR unavailable.
- Check Accessibility and Screen Recording permissions.
- Metadata-only captures now include a non-empty diagnostic excerpt in markdown `Raw Excerpt` to avoid blank files.
- Host UI now also shows a warning popup on desktop metadata-only and OCR fallback captures with quick links to Accessibility and Screen Recording settings.
- Popup copy now reflects the actual fallback path (`metadata_only` vs `ocr`) to avoid misleading troubleshooting guidance.

4. Captures paused placeholder
- Capture trigger intentionally no-ops while pause placeholder is enabled in `Settings`.
- Disable `Pause Captures` to resume normal capture behavior.

## Quick Remediation Path
1. Run diagnostics from menu.
2. Use `Open Accessibility Settings` and `Open Screen Recording Settings` actions.
3. Re-run capture and verify transport status and warning count.
4. For paused-state confusion, check `Settings` and ensure captures are resumed.

## Output Tuning
1. Output is too long for paste destination
- Set `Settings -> Output Format -> Brief`.

2. Need richer context for downstream prompts
- Set `Settings -> Output Format -> Full` to include content chunks and raw excerpt.
- Keep `Settings -> Product Context Line -> On` to add a one-line tool description for downstream model context.

3. Want LLM-assisted summarization
- Open `Settings -> Advanced Settings... -> Summarizing -> Mode -> LLM`.
- Select `Settings -> Advanced Settings... -> Summarizing -> LLM Provider`.
- Optionally set model and summary budget.

4. LLM mode selected but output still looks heuristic
- Check provider credentials in environment variables:
  - `OPENAI_API_KEY`
  - `ANTHROPIC_API_KEY`
  - `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
  - `OLLAMA_BASE_URL` for local Ollama endpoint
- If provider call fails, host falls back to heuristic summarization and records `LLM summary fallback: ...` in output warnings.

## Safari Container Local-Install Issues
1. `Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier`
- In Xcode, ensure extension bundle id is `<app_bundle_id>.Extension`.

2. Signing/provisioning failures for app or extension target
- Set the same Apple Development team on both targets.
- Use automatic signing for local development.

3. Extension not visible in Safari settings
- Re-run the app target after successful signed build.
- Open Safari -> Settings -> Extensions and verify `ContextGrabberSafari Extension`.
