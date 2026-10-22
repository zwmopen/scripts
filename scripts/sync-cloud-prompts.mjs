#!/usr/bin/env node
/**
 * 云端提示词库同步器
 *
 * 唯一真源是各技能仓库里的 md 文件；本脚本把它们拼成
 * chatgpt-cloud-prompts.json 里的条目，油猴脚本据此同步。
 * 以后改提示词只改技能 md，跑本脚本，别手改 JSON。
 *
 * 用法：
 *   node scripts/sync-cloud-prompts.mjs            # 写入
 *   node scripts/sync-cloud-prompts.mjs --dry-run  # 只报告差异，不写
 *   node scripts/sync-cloud-prompts.mjs --check    # 有差异则退出码 1（给 CI 用）
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const CONFIG_PATH = path.join(__dirname, "cloud-prompts.sources.json");

const args = new Set(process.argv.slice(2));
const DRY = args.has("--dry-run") || args.has("--check");
const CHECK = args.has("--check");

function readText(file) {
  return fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
}

/** 去掉 YAML frontmatter（技能 SKILL.md 的 name/description 块） */
function stripFrontmatter(text) {
  return text.replace(/^---\n[\s\S]*?\n---\n/, "");
}

/** 去掉导出残留头：仅剥离形如 "文案(20260904-080343).txt" / "文档" 这类下载器杂质，标题行不动 */
function stripExportNoise(text) {
  const lines = text.split("\n");
  let i = 0;
  while (i < 3 && lines[i] !== undefined) {
    const line = lines[i].trim();
    if (!/\.(txt|md|docx?)$/i.test(line) && line !== "文档") break;
    i++;
  }
  return lines.slice(i).join("\n");
}

function resolveSource(p) {
  return path.isAbsolute(p) ? p : path.resolve(REPO_ROOT, p);
}

function buildContent(entry) {
  const blocks = [];
  for (const src of entry.sources) {
    const file = resolveSource(src.file);
    if (!fs.existsSync(file)) throw new Error(`缺少源文件：${src.file}`);
    let text = readText(file);
    if (src.stripFrontmatter !== false && /(^|\/)SKILL\.md$/i.test(src.file)) text = stripFrontmatter(text);
    if (src.stripExportNoise !== false) text = stripExportNoise(text);
    text = text.trim();
    if (src.heading) blocks.push(`${src.heading}\n\n${text}`);
    else blocks.push(text);
  }
  return blocks.join("\n\n---\n\n").trim() + "\n";
}

/** 版本号：YYYY.MM.DD.N；同一天重复执行时 N 自增 */
function nextVersion(currentVersion, now, changedCount) {
  if (changedCount === 0) return currentVersion;
  const stamp = `${now.getFullYear()}.${String(now.getMonth() + 1).padStart(2, "0")}.${String(now.getDate()).padStart(2, "0")}`;
  const m = /^(\d{4}\.\d{2}\.\d{2})\.(\d+)$/.exec(String(currentVersion || ""));
  if (m && m[1] === stamp) return `${stamp}.${Number(m[2]) + 1}`;
  return `${stamp}.1`;
}

function main() {
  if (!fs.existsSync(CONFIG_PATH)) throw new Error(`缺少配置：${CONFIG_PATH}`);
  const config = JSON.parse(readText(CONFIG_PATH));
  const targetFile = resolveSource(config.targetFile);
  if (!fs.existsSync(targetFile)) throw new Error(`缺少云端库文件：${config.targetFile}`);

  const library = JSON.parse(readText(targetFile));
  if (!Array.isArray(library.prompts)) throw new Error("云端库结构异常：缺少 prompts 数组");

  const now = new Date();
  const stampMs = now.getTime();
  const report = [];
  let changed = 0;

  for (const entry of config.entries) {
    if (!entry.id || !entry.title || !Array.isArray(entry.sources)) {
      throw new Error(`配置条目缺少 id/title/sources：${JSON.stringify(entry).slice(0, 120)}`);
    }
    const content = buildContent(entry);
    const skill = entry.skill && entry.skill.repo ? entry.skill : null;
    const hit = library.prompts.find((p) => p.id === entry.id);
    if (!hit) {
      const created = { id: entry.id, title: entry.title, content };
      if (skill) created.skill = skill;
      created.createdAt = stampMs;
      created.updatedAt = stampMs;
      library.prompts.unshift(created);
      changed++;
      report.push(`+ 新增 ${entry.id}｜${entry.title}｜${content.length} 字${skill ? `（技能直连 ${skill.repo}）` : ""}`);
      continue;
    }
    const contentChanged = hit.content !== content;
    const titleChanged = hit.title !== entry.title;
    const skillChanged = JSON.stringify(hit.skill || null) !== JSON.stringify(skill || null);
    if (contentChanged || titleChanged || skillChanged) {
      hit.title = entry.title;
      hit.content = content;
      if (skill) hit.skill = skill;
      else delete hit.skill;
      hit.updatedAt = stampMs;
      changed++;
      const notes = [];
      if (titleChanged) notes.push("标题变更");
      if (skillChanged) notes.push(skill ? "技能引用更新" : "移除技能引用");
      if (!contentChanged && !titleChanged) notes.push("仅技能引用");
      report.push(
        `~ 更新 ${entry.id}｜${entry.title}｜${hit.content.length} 字`
        + (notes.length ? `（${notes.join("、")}）` : "")
      );
    } else {
      report.push(`= 无变化 ${entry.id}｜${entry.title}｜${content.length} 字`);
    }
  }

  // 配置里声明 required=false 的条目允许缺席；这里只提示"库里存在但配置没管"的条目
  const managed = new Set(config.entries.map((e) => e.id));
  const unmanaged = library.prompts.filter((p) => !managed.has(p.id)).map((p) => p.id);

  const nextVer = nextVersion(library.version, now, changed);
  if (changed > 0) {
    library.version = nextVer;
    library.updatedAt = stampMs;
  }

  const serialized = JSON.stringify(library, null, 2) + "\n";
  const maxBytes = Number(config.maxBytes) || 2 * 1024 * 1024;
  if (Buffer.byteLength(serialized, "utf8") > maxBytes) {
    throw new Error(`生成结果超过脚本上限 ${maxBytes} 字节，已中止`);
  }

  console.log(report.join("\n"));
  console.log(`\n管理条目：${managed.size}｜库内总条目：${library.prompts.length}｜变动：${changed}`);
  if (unmanaged.length) console.log(`未纳管条目（保留不动）：${unmanaged.length} 条 → ${unmanaged.slice(0, 6).join(", ")}${unmanaged.length > 6 ? " …" : ""}`);
  console.log(`版本：${library.version}｜目标文件：${path.relative(REPO_ROOT, targetFile)}`);

  if (CHECK && changed > 0) {
    console.error("\n[check] 云端库与技能源不一致，需要同步。");
    process.exit(1);
  }
  if (DRY) {
    console.log("\n[dry-run] 未写入。");
    return;
  }
  if (changed === 0) {
    console.log("\n无变化，未写入。");
    return;
  }
  fs.writeFileSync(targetFile, serialized, "utf8");
  console.log("\n已写入。");
}

try {
  main();
} catch (error) {
  console.error(`同步失败：${error.message}`);
  process.exit(1);
}
