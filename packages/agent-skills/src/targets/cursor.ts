import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { InstallResult, InstallScope } from "../types.js";
import { resolveTargetDir, skillSourceDir } from "../utils.js";

/** Cursor .mdc file name for the context-grabber skill. */
const CURSOR_MDC_FILENAME = "context-grabber.mdc";

/**
 * Convert SKILL.md (with YAML frontmatter) to Cursor .mdc format.
 *
 * Cursor rules use a similar frontmatter-plus-markdown format, but with
 * a slightly different frontmatter schema:
 * - `description` (from SKILL.md)
 * - `globs` (empty — this is a general-purpose skill, not file-scoped)
 * - `alwaysApply: false` (agent-requested, not auto-applied)
 */
export function convertToMdc(skillMdContent: string): string {
  // Extract description from YAML frontmatter.
  const frontmatterMatch = skillMdContent.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!frontmatterMatch) {
    throw new Error("SKILL.md missing YAML frontmatter");
  }

  const frontmatter = frontmatterMatch[1] ?? "";
  const body = frontmatterMatch[2] ?? "";

  // Extract the description value from frontmatter.
  const descMatch = frontmatter.match(/description:\s*>\s*\n([\s\S]*?)(?:\n---|\n\w|$)/);
  let description = "";
  if (descMatch?.[1]) {
    description = descMatch[1]
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .join(" ");
  } else {
    const simpleDesc = frontmatter.match(/description:\s*(.+)/);
    if (simpleDesc?.[1]) {
      description = simpleDesc[1].trim();
    }
  }

  const mdcFrontmatter = [
    "---",
    `description: ${description}`,
    "globs:",
    "alwaysApply: false",
    "---",
  ].join("\n");

  return `${mdcFrontmatter}\n${body}`;
}

/**
 * Install skill for Cursor.
 *
 * Cursor uses .mdc files in .cursor/rules/ (project) or ~/.cursor/rules/ (global).
 * We convert SKILL.md to .mdc format and write a single file (no references dir —
 * Cursor doesn't support multi-file skills, so we inline the core instructions).
 */
export function installCursor(scope: InstallScope, cwd: string): InstallResult {
  const sourceDir = skillSourceDir();
  const skillMdPath = join(sourceDir, "SKILL.md");

  if (!existsSync(skillMdPath)) {
    throw new Error(`Skill source file not found: ${skillMdPath}`);
  }

  const skillMdContent = readFileSync(skillMdPath, "utf-8");
  const mdcContent = convertToMdc(skillMdContent);

  const targetDir = resolveTargetDir("cursor", scope, cwd);
  const mdcPath = join(targetDir, CURSOR_MDC_FILENAME);

  mkdirSync(dirname(mdcPath), { recursive: true });
  writeFileSync(mdcPath, mdcContent, "utf-8");

  return {
    agent: "cursor",
    scope,
    paths: [mdcPath],
    symlinks: [],
  };
}

/**
 * Uninstall skill for Cursor.
 */
export function uninstallCursor(scope: InstallScope, cwd: string): InstallResult {
  const targetDir = resolveTargetDir("cursor", scope, cwd);
  const mdcPath = join(targetDir, CURSOR_MDC_FILENAME);
  const removed: string[] = [];

  if (existsSync(mdcPath)) {
    rmSync(mdcPath);
    removed.push(mdcPath);
  }

  return {
    agent: "cursor",
    scope,
    paths: removed,
    symlinks: [],
  };
}
