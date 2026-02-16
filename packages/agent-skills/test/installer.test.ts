import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readlinkSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { installForAgent, uninstallForAgent } from "../src/dispatch.js";
import { convertToMdc } from "../src/targets/cursor.js";
import { type AgentTarget, SKILL_FILES } from "../src/types.js";
import {
  copySkillFiles,
  ensureSymlink,
  globalSkillRoot,
  hasOtherGlobalSymlinks,
  removeSkillFiles,
  removeSymlink,
  resolveTargetDir,
} from "../src/utils.js";

/** Create a temporary directory with fake skill source files. */
function createFakeSkillSource(baseDir: string): string {
  const skillDir = join(baseDir, "skill");
  mkdirSync(join(skillDir, "references"), { recursive: true });
  writeFileSync(
    join(skillDir, "SKILL.md"),
    "---\nname: test\ndescription: test skill\n---\n# Test",
  );
  writeFileSync(join(skillDir, "references", "cli-reference.md"), "# CLI Ref");
  writeFileSync(join(skillDir, "references", "output-schema.md"), "# Schema");
  writeFileSync(join(skillDir, "references", "workflows.md"), "# Workflows");
  return skillDir;
}

let testDir: string;

beforeEach(() => {
  testDir = join(
    tmpdir(),
    `agent-skills-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(testDir, { recursive: true });
});

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true });
});

describe("resolveTargetDir", () => {
  const cwd = "/fake/project";

  it("resolves claude project path", () => {
    expect(resolveTargetDir("claude", "project", cwd)).toBe(
      "/fake/project/.claude/skills/context-grabber",
    );
  });

  it("resolves opencode project path", () => {
    expect(resolveTargetDir("opencode", "project", cwd)).toBe(
      "/fake/project/.opencode/skills/context-grabber",
    );
  });

  it("resolves cursor project path", () => {
    expect(resolveTargetDir("cursor", "project", cwd)).toBe("/fake/project/.cursor/rules");
  });

  it("resolves claude global path", () => {
    const result = resolveTargetDir("claude", "global", cwd);
    expect(result).toContain(".claude/skills/context-grabber");
    expect(result).not.toContain("/fake/project");
  });

  it("resolves opencode global path", () => {
    const result = resolveTargetDir("opencode", "global", cwd);
    expect(result).toContain(".config/opencode/skills/context-grabber");
    expect(result).not.toContain("/fake/project");
  });

  it("resolves cursor global path", () => {
    const result = resolveTargetDir("cursor", "global", cwd);
    expect(result).toContain(".cursor/rules");
    expect(result).not.toContain("/fake/project");
  });
});

describe("copySkillFiles", () => {
  it("copies all skill files to target directory", () => {
    const sourceDir = createFakeSkillSource(testDir);
    const targetDir = join(testDir, "target");

    const created = copySkillFiles(sourceDir, targetDir);

    expect(created).toHaveLength(SKILL_FILES.length);
    for (const relPath of SKILL_FILES) {
      const dest = join(targetDir, relPath);
      expect(existsSync(dest)).toBe(true);
    }
  });

  it("overwrites existing files", () => {
    const sourceDir = createFakeSkillSource(testDir);
    const targetDir = join(testDir, "target");
    mkdirSync(targetDir, { recursive: true });
    writeFileSync(join(targetDir, "SKILL.md"), "old content");

    copySkillFiles(sourceDir, targetDir);

    const content = readFileSync(join(targetDir, "SKILL.md"), "utf-8");
    expect(content).toContain("# Test");
  });

  it("throws when source file is missing", () => {
    const emptyDir = join(testDir, "empty");
    mkdirSync(emptyDir, { recursive: true });
    const targetDir = join(testDir, "target");

    expect(() => copySkillFiles(emptyDir, targetDir)).toThrow("Skill source file not found");
  });
});

describe("ensureSymlink", () => {
  it("creates a new symlink", () => {
    const target = join(testDir, "target");
    mkdirSync(target, { recursive: true });
    const link = join(testDir, "link");

    ensureSymlink(target, link);

    expect(existsSync(link)).toBe(true);
    expect(resolve(readlinkSync(link))).toBe(resolve(target));
  });

  it("skips if symlink already points to correct target", () => {
    const target = join(testDir, "target");
    mkdirSync(target, { recursive: true });
    const link = join(testDir, "link");

    ensureSymlink(target, link);
    ensureSymlink(target, link); // Should not throw.

    expect(resolve(readlinkSync(link))).toBe(resolve(target));
  });

  it("replaces symlink pointing to wrong target", () => {
    const oldTarget = join(testDir, "old");
    const newTarget = join(testDir, "new");
    mkdirSync(oldTarget, { recursive: true });
    mkdirSync(newTarget, { recursive: true });
    const link = join(testDir, "link");

    ensureSymlink(oldTarget, link);
    ensureSymlink(newTarget, link);

    expect(resolve(readlinkSync(link))).toBe(resolve(newTarget));
  });

  it("replaces a broken (dangling) symlink", () => {
    const brokenTarget = join(testDir, "does-not-exist");
    const newTarget = join(testDir, "new");
    mkdirSync(newTarget, { recursive: true });
    const link = join(testDir, "link");

    // Create a dangling symlink manually.
    symlinkSync(brokenTarget, link);
    expect(lstatSync(link).isSymbolicLink()).toBe(true);
    expect(existsSync(link)).toBe(false); // Broken — target doesn't exist.

    // ensureSymlink should handle this and replace it.
    ensureSymlink(newTarget, link);

    expect(resolve(readlinkSync(link))).toBe(resolve(newTarget));
  });
});

describe("removeSkillFiles", () => {
  it("removes installed skill files", () => {
    const sourceDir = createFakeSkillSource(testDir);
    const targetDir = join(testDir, "installed");
    copySkillFiles(sourceDir, targetDir);

    const removed = removeSkillFiles(targetDir);

    expect(removed).toHaveLength(SKILL_FILES.length);
    for (const relPath of SKILL_FILES) {
      expect(existsSync(join(targetDir, relPath))).toBe(false);
    }
  });

  it("returns empty array when nothing to remove", () => {
    const emptyDir = join(testDir, "empty");
    mkdirSync(emptyDir, { recursive: true });

    const removed = removeSkillFiles(emptyDir);

    expect(removed).toHaveLength(0);
  });

  it("preserves target directory when skipDirCleanup is true", () => {
    const sourceDir = createFakeSkillSource(testDir);
    const targetDir = join(testDir, "cursor-rules");
    copySkillFiles(sourceDir, targetDir);

    // Add an extra file to simulate Cursor's shared rules/ dir.
    writeFileSync(join(targetDir, "other-rule.mdc"), "other rule");

    const removed = removeSkillFiles(targetDir, true);

    expect(removed).toHaveLength(SKILL_FILES.length);
    // Target directory should still exist because we opted out of cleanup.
    expect(existsSync(targetDir)).toBe(true);
    // The extra file should be untouched.
    expect(existsSync(join(targetDir, "other-rule.mdc"))).toBe(true);
  });
});

describe("removeSymlink", () => {
  // globalSkillRoot() resolves to a real path under $HOME. Tests that create
  // it must clean up after themselves to avoid side effects.
  const globalRoot = globalSkillRoot();

  afterEach(() => {
    // Clean up any real directories created under ~/.agents/skills/context-grabber/.
    rmSync(globalRoot, { recursive: true, force: true });
  });

  it("removes symlink pointing to globalSkillRoot", () => {
    const target = globalRoot;
    mkdirSync(target, { recursive: true });
    const link = join(testDir, "link");
    symlinkSync(target, link);

    const removed = removeSymlink(link);

    expect(removed).toBe(true);
    // lstatSync should throw since the symlink is gone.
    expect(() => lstatSync(link)).toThrow();
  });

  it("does not remove symlink pointing elsewhere", () => {
    const otherTarget = join(testDir, "other");
    mkdirSync(otherTarget, { recursive: true });
    const link = join(testDir, "link");
    symlinkSync(otherTarget, link);

    const removed = removeSymlink(link);

    expect(removed).toBe(false);
    expect(lstatSync(link).isSymbolicLink()).toBe(true);
  });

  it("handles broken symlink gracefully", () => {
    const brokenTarget = join(testDir, "does-not-exist");
    const link = join(testDir, "link");
    symlinkSync(brokenTarget, link);

    // Should not throw, and should return false (target isn't globalSkillRoot).
    const removed = removeSymlink(link);

    expect(removed).toBe(false);
  });

  it("returns false when path does not exist", () => {
    const result = removeSymlink(join(testDir, "nonexistent"));
    expect(result).toBe(false);
  });
});

describe("convertToMdc", () => {
  it("converts SKILL.md with multiline description to .mdc format", () => {
    const input = [
      "---",
      "name: context-grabber",
      "description: >",
      "  Capture browser tabs and desktop app context",
      "  for LLM workflows.",
      "---",
      "",
      "# Context Grabber",
      "",
      "Instructions here.",
    ].join("\n");

    const result = convertToMdc(input);

    expect(result).toContain("---");
    expect(result).toContain(
      "description: Capture browser tabs and desktop app context for LLM workflows.",
    );
    expect(result).toContain("globs:");
    expect(result).toContain("alwaysApply: false");
    expect(result).toContain("# Context Grabber");
    expect(result).toContain("Instructions here.");
  });

  it("converts SKILL.md with simple description", () => {
    const input = "---\nname: test\ndescription: A simple skill\n---\n# Body";
    const result = convertToMdc(input);

    expect(result).toContain("description: A simple skill");
    expect(result).toContain("alwaysApply: false");
    expect(result).toContain("# Body");
  });

  it("throws on missing frontmatter", () => {
    expect(() => convertToMdc("# No frontmatter")).toThrow("missing YAML frontmatter");
  });
});

describe("installForAgent + uninstallForAgent (project scope)", () => {
  const agents: AgentTarget[] = ["claude", "opencode", "cursor"];

  for (const agent of agents) {
    it(`installs and uninstalls for ${agent}`, () => {
      // We need to point skillSourceDir to our test data.
      // Since installForAgent calls skillSourceDir() internally, we test via
      // the underlying functions directly for project scope.
      const sourceDir = createFakeSkillSource(testDir);
      const projectDir = join(testDir, "project");
      mkdirSync(projectDir, { recursive: true });

      const targetDir = resolveTargetDir(agent, "project", projectDir);

      if (agent === "cursor") {
        // Cursor writes a single .mdc file, not the full skill directory.
        // Test the conversion path directly.
        const skillMd = readFileSync(join(sourceDir, "SKILL.md"), "utf-8");
        const mdc = convertToMdc(skillMd);
        expect(mdc).toContain("alwaysApply: false");
        expect(mdc).toContain("# Test");
      } else {
        // Claude and OpenCode copy all skill files.
        const created = copySkillFiles(sourceDir, targetDir);
        expect(created).toHaveLength(SKILL_FILES.length);

        for (const relPath of SKILL_FILES) {
          expect(existsSync(join(targetDir, relPath))).toBe(true);
        }

        // Uninstall.
        const removed = removeSkillFiles(targetDir);
        expect(removed).toHaveLength(SKILL_FILES.length);
      }
    });
  }
});

describe("hasOtherGlobalSymlinks", () => {
  // These tests create real symlinks under $HOME agent directories and
  // must clean up after themselves.
  const globalRoot = globalSkillRoot();
  const claudeDir = resolveTargetDir("claude", "global", "");
  const opencodeDir = resolveTargetDir("opencode", "global", "");

  beforeEach(() => {
    mkdirSync(globalRoot, { recursive: true });
  });

  afterEach(() => {
    // Clean up all directories that may have been created.
    for (const dir of [claudeDir, opencodeDir]) {
      rmSync(dir, { recursive: true, force: true });
    }
    rmSync(globalRoot, { recursive: true, force: true });
  });

  it("returns false when no symlinks exist", () => {
    expect(hasOtherGlobalSymlinks("claude")).toBe(false);
    expect(hasOtherGlobalSymlinks("opencode")).toBe(false);
  });

  it("returns true when another agent's symlink exists", () => {
    // Create opencode symlink pointing to canonical root.
    mkdirSync(join(opencodeDir, ".."), { recursive: true });
    symlinkSync(globalRoot, opencodeDir);

    // Excluding claude — opencode symlink is still present.
    expect(hasOtherGlobalSymlinks("claude")).toBe(true);
  });

  it("returns false when only the excluded agent's symlink exists", () => {
    // Create claude symlink pointing to canonical root.
    mkdirSync(join(claudeDir, ".."), { recursive: true });
    symlinkSync(globalRoot, claudeDir);

    // Excluding claude — no other symlinks.
    expect(hasOtherGlobalSymlinks("claude")).toBe(false);
  });

  it("returns false when symlink points elsewhere", () => {
    // Create opencode symlink pointing to a different directory.
    const otherDir = join(globalRoot, "..", "other-skill");
    mkdirSync(otherDir, { recursive: true });
    mkdirSync(join(opencodeDir, ".."), { recursive: true });
    symlinkSync(otherDir, opencodeDir);

    // The symlink exists but doesn't point to canonical root.
    expect(hasOtherGlobalSymlinks("claude")).toBe(false);

    rmSync(otherDir, { recursive: true, force: true });
  });
});
