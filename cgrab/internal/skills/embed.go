// Package skills provides embedded skill files for the agent skill installer fallback.
//
// The canonical source of truth for skill content is packages/agent-skills/skill/.
// These files are synced copies — CI should verify they match the canonical source
// to prevent drift.
package skills

import (
	"embed"
	"fmt"
	"io/fs"
	"sort"
)

// SkillFiles embeds the full skill directory (SKILL.md + references/).
//
//go:embed SKILL.md references
var SkillFiles embed.FS

// SkillFileList is the list of embedded files that should be installed.
// It is derived from the embedded tree at startup to avoid stale hardcoded lists.
var SkillFileList = mustSkillFileList()

func mustSkillFileList() []string {
	paths, err := loadSkillFileList()
	if err != nil {
		panic(fmt.Sprintf("load embedded skill file list: %v", err))
	}
	return paths
}

func loadSkillFileList() ([]string, error) {
	var paths []string
	err := fs.WalkDir(SkillFiles, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if path == "." || d.IsDir() {
			return nil
		}
		paths = append(paths, path)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(paths)
	return paths, nil
}
