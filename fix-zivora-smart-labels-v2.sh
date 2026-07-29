#!/bin/bash

set -e

cd ~/Desktop/zivora || exit 1

echo "Fixing Zivora smart titles and descriptions..."

python3 <<'PY'
from pathlib import Path
import re
import shutil

background_path = Path("extension/background.js")
content_path = Path("extension/content.js")

if not background_path.exists():
    raise SystemExit("❌ extension/background.js was not found.")

if not content_path.exists():
    raise SystemExit("❌ extension/content.js was not found.")

# Create fresh backups before changing anything.
shutil.copy2(
    background_path,
    Path("extension/background.js.smart-labels-backup")
)

shutil.copy2(
    content_path,
    Path("extension/content.js.smart-labels-backup")
)

background = background_path.read_text(encoding="utf-8")
content = content_path.read_text(encoding="utf-8")

new_normalise = r'''
function normaliseLabel(value) {
  let text = String(value || "")
    .replace(/\s+/g, " ")
    .replace(/[|•·]+/g, " ")
    .trim();

  if (!text) {
    return "";
  }

  text = text
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/\bwww\.\S+/gi, " ")
    .replace(
      /\b[a-z0-9-]+\.(?:com|co\.uk|org|net|io|dev|ai)(?:\s*[›>\/]\s*\S*)?/gi,
      " "
    )
    .replace(
      /\s*[›>]\s*[a-z0-9/_?=&.-]+/gi,
      " "
    );

  text = text
    .replace(/\bCached\b/gi, " ")
    .replace(/\bTranslate this result\b/gi, " ")
    .replace(/\bMore results from\b.*$/gi, " ");

  const words = text
    .replace(/\s+/g, " ")
    .trim()
    .split(" ");

  const cleanedWords = [];

  for (const word of words) {
    const previous =
      cleanedWords[cleanedWords.length - 1];

    if (
      !previous ||
      previous.toLowerCase() !==
        word.toLowerCase()
    ) {
      cleanedWords.push(word);
    }
  }

  text = cleanedWords.join(" ").trim();

  const sentenceParts = text
    .split(/\s{2,}| - | — | \| /)
    .map((part) => part.trim())
    .filter(Boolean);

  if (sentenceParts.length > 0) {
    text = sentenceParts[0];
  }

  return text
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
}
'''.strip()

background, count = re.subn(
    r'function normaliseLabel\(value\) \{.*?\n\}',
    lambda match: new_normalise,
    background,
    count=1,
    flags=re.S
)

if count != 1:
    raise SystemExit(
        "❌ Could not replace normaliseLabel in background.js"
    )

helper_code = r'''
function classifyElement(payload, label) {
  const role = String(
    payload.elementRole || ""
  ).toLowerCase();

  const hostname = String(
    payload.hostname || ""
  ).toLowerCase();

  if (
    hostname.includes("google.") &&
    role === "link"
  ) {
    return "search result";
  }

  if (
    role.includes("search") ||
    /search/i.test(label)
  ) {
    return "search box";
  }

  if (/sign in|log in/i.test(label)) {
    return "sign-in link";
  }

  if (
    /sign up|register|create account/i.test(label)
  ) {
    return "sign-up link";
  }

  if (role === "button") {
    return "button";
  }

  if (role === "link") {
    return "link";
  }

  if (role === "input") {
    return "input field";
  }

  if (role === "dropdown") {
    return "dropdown";
  }

  return role || "element";
}

function removeRepeatedSiteWords(value) {
  const words = normaliseLabel(value)
    .split(" ")
    .filter(Boolean);

  const result = [];

  for (const word of words) {
    const previous = result[result.length - 1];

    if (
      !previous ||
      previous.toLowerCase() !==
        word.toLowerCase()
    ) {
      result.push(word);
    }
  }

  return result.join(" ").trim();
}

function cleanCapturedLabel(payload) {
  let label = removeRepeatedSiteWords(
    payload.elementText ||
      payload.ariaLabel ||
      payload.placeholder ||
      ""
  );

  label = label
    .replace(
      /\bhttps?\b.*$/i,
      ""
    )
    .replace(
      /\bwww\b.*$/i,
      ""
    )
    .replace(
      /\s+(?:Google|GitHub|YouTube)\s*$/i,
      ""
    )
    .trim();

  return label.slice(0, 70);
}
'''.strip()

marker = "function createSmartTitle(payload) {"

if "function classifyElement(payload, label)" not in background:
    if marker not in background:
        raise SystemExit(
            "❌ Could not find createSmartTitle in background.js"
        )

    background = background.replace(
        marker,
        helper_code + "\n\n" + marker,
        1
    )

new_title = r'''
function createSmartTitle(payload) {
  const label = cleanCapturedLabel(payload);

  const type = classifyElement(
    payload,
    label
  );

  const site = titleCase(
    cleanSiteName(payload.hostname)
  );

  if (type === "sign-in link") {
    return "Open Sign In";
  }

  if (type === "sign-up link") {
    return "Open Sign Up";
  }

  if (
    /create issue|new issue/i.test(label)
  ) {
    return "Create Issue";
  }

  if (
    /create repository|new repository/i.test(
      label
    )
  ) {
    return "Create Repository";
  }

  if (type === "search box") {
    return "Use Search";
  }

  if (type === "search result") {
    return label
      ? `Open ${label.slice(0, 52)}`
      : "Open Search Result";
  }

  if (type === "button") {
    return label
      ? `Click ${label.slice(0, 52)}`
      : "Click Button";
  }

  if (type === "link") {
    return label
      ? `Open ${label.slice(0, 52)}`
      : "Open Link";
  }

  if (label) {
    return `Select ${label.slice(0, 52)}`;
  }

  if (site) {
    return `Continue on ${site}`;
  }

  return "Continue to Next Step";
}
'''.strip()

background, count = re.subn(
    r'function createSmartTitle\(payload\) \{.*?\n\}',
    lambda match: new_title,
    background,
    count=1,
    flags=re.S
)

if count != 1:
    raise SystemExit(
        "❌ Could not replace createSmartTitle in background.js"
    )

new_action = r'''
function createLocalAction(payload) {
  const label = cleanCapturedLabel(payload);

  const type = classifyElement(
    payload,
    label
  );

  const site = titleCase(
    cleanSiteName(payload.hostname)
  );

  if (type === "search result") {
    return label
      ? `Click the ${label} search result.`
      : "Click the highlighted search result.";
  }

  if (type === "search box") {
    return "Click the search box and enter your search.";
  }

  if (type === "sign-in link") {
    return "Click the Sign In link.";
  }

  if (type === "sign-up link") {
    return "Click the Sign Up link.";
  }

  if (type === "button") {
    return label
      ? `Click the ${label} button.`
      : "Click the highlighted button.";
  }

  if (type === "link") {
    return label
      ? `Click the ${label} link.`
      : "Click the highlighted link.";
  }

  if (label) {
    return `Select ${label}${
      site ? ` on ${site}` : ""
    }.`;
  }

  return `Select the highlighted ${type}${
    site ? ` on ${site}` : ""
  }.`;
}
'''.strip()

background, count = re.subn(
    r'function createLocalAction\(payload\) \{.*?\n\}',
    lambda match: new_action,
    background,
    count=1,
    flags=re.S
)

if count != 1:
    raise SystemExit(
        "❌ Could not replace createLocalAction in background.js"
    )

new_get_label = r'''
function getElementLabel(element) {
  const ariaLabel =
    element.getAttribute("aria-label");

  const title =
    element.getAttribute("title");

  const placeholder =
    element.getAttribute("placeholder");

  if (ariaLabel) {
    return cleanText(ariaLabel);
  }

  if (title) {
    return cleanText(title);
  }

  if (placeholder) {
    return cleanText(placeholder);
  }

  const heading = element.querySelector(
    "h1, h2, h3, h4, [role='heading']"
  );

  if (heading?.textContent) {
    return cleanText(heading.textContent);
  }

  const headingParent = element.closest(
    "div, article, section"
  )?.querySelector(
    "h1, h2, h3, h4, [role='heading']"
  );

  if (headingParent?.textContent) {
    return cleanText(
      headingParent.textContent
    );
  }

  const directText = Array.from(
    element.childNodes
  )
    .filter(
      (node) =>
        node.nodeType === Node.TEXT_NODE
    )
    .map((node) =>
      cleanText(node.textContent)
    )
    .filter(Boolean);

  if (directText.length > 0) {
    return directText[0];
  }

  return cleanText(
    element.innerText ||
      element.textContent ||
      element.getAttribute("name") ||
      element.tagName.toLowerCase()
  );
}
'''.strip()

content, count = re.subn(
    r'function getElementLabel\(element\) \{.*?\n\}',
    lambda match: new_get_label,
    content,
    count=1,
    flags=re.S
)

if count != 1:
    raise SystemExit(
        "❌ Could not replace getElementLabel in content.js"
    )

background_path.write_text(
    background,
    encoding="utf-8"
)

content_path.write_text(
    content,
    encoding="utf-8"
)

print("✅ Smart label cleaning installed")
print("✅ Search-result recognition installed")
print("✅ Shorter titles installed")
print("✅ Natural action descriptions installed")
PY

echo ""
echo "Checking extension files..."

node --check extension/background.js
node --check extension/content.js

echo ""
echo "Building Zivora..."

rm -rf .next
npm run build

echo ""
echo "Stopping old Next.js servers..."

pkill -f "next dev" 2>/dev/null || true

echo ""
echo "Starting Zivora..."

npm run dev
