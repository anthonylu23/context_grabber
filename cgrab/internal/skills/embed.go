// Package skills provides embedded skill files for the agent skill installer fallback.
//
// The canonical source of truth for skill content is packages/agent-skills/skill/.
// These files are synced copies — CI should verify they match the canonical source
// to prevent drift.
package skills

import "embed"

// SkillFiles embeds the full skill directory (SKILL.md + references/).
//
//go:embed SKILL.md references
var SkillFiles embed.FS

// SkillFileList is the list of files that should be installed.
var SkillFileList = []string{
	"SKILL.md",
	"references/cli-reference.md",
	"references/output-schema.md",
	"references/workflows.md",
}
