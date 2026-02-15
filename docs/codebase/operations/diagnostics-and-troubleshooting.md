# Diagnostics and Troubleshooting

## Host Diagnostics Surface
`Run Diagnostics` reports:
- frontmost app routing target
- Safari transport status
- Chrome transport status
- desktop permission readiness (AX + Screen Recording)
- last capture timestamp/error/latency
- storage writability

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

## Quick Remediation Path
1. Run diagnostics from menu.
2. Use `Open Accessibility Settings` and `Open Screen Recording Settings` actions.
3. Re-run capture and verify transport status and warning count.
