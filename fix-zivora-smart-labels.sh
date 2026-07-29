#!/bin/bash

set -e

cd ~/Desktop/zivora || exit 1

echo "Improving captured titles and descriptions..."

cp extension/background.js extension/background.js.backup
cp extension/content.js extension/content.js.backup

python3 <<'PY'
from pathlib import Path
import re

background_path = Path("extension/background.js")
content_path = Path("extension/content.js")

background = background_path.read_text()
content = content_path.read_text()

# -------------------------------------------------------------------
# Replace label-cleaning logic in background.js
# -------------------------------------------------------------------

new_normalise = r'''
function normaliseLabel(value) {
  let text = String(value || "")
    .replace(/\s+/g, " ")
    .replace(/[|•·]+/g, " ")
    .trim();

  if (!text) {
    return "";
  }

  // Remove visible URLs and domain breadcrumbs.
  text = text
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/\bwww\.\S+/gi, " ")
    .replace(/\b[a-z0-9-]+\.(?:com|co\.uk|org|net|io|dev|ai)(?:\s*[›>\/]\s*\S*)?/gi, " ")
    .replace(/\s*[›>]\s*[a-z0-9/_?=&.-]+/gi, " ");

  // Remove common Google-result metadata.
  text = text
    .replace(/\bCached\b/gi, " ")
    .replace(/\bTranslate this result\b/gi, " ")
    .replace(/\bMore results from\b.*$/gi, " ");

  // Remove repeated adjacent words.
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
      previous.toLowerCase() !== word.toLowerCase()
    ) {
      cleanedWords.push(word);
    }
  }

  text = cleanedWords.join(" ").trim();

  // If a long search result was captured, keep its clearest first part.
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
'''

background, count = re.subn(
    r'function normaliseLabel\(value\) \{.*?\n\}',
    new_normalise.strip(),
    background,
    count=1,
    flags=re.S,
)

if count != 1:
    raise SystemExit(
        "Could not replace normaliseLabel in background.js"
    )

# -------------------------------------------------------------------
# Add intelligent element classification
# -------------------------------------------------------------------

helper_code = r'''
function cleanPageName(payload) {
  const pageTitle = normaliseLabel(payload.pageTitle);

  if (!pageTitle) {
    return "";
  }

  return pageTitle
    .replace(/\s*[-|·]\s*(Google Search|Google|GitHub|YouTube).*$/i, "")
    .trim();
}

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
    /search/i.test(role) ||
    /search/i.test(label)
  ) {
    return "search box";
  }

  if (
    /sign in|log in/i.test(label)
  ) {
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

function removeSiteSuffix(label, payload) {
  let result = normaliseLabel(label);

  const siteName = cleanSiteName(
    payload.hostname
  );

  if (siteName) {
    const escaped = siteName.replace(
      /[.*+?^${}()|[\]\\]/g,
      "\\$&"
    );

    result = result.replace(
      new RegExp(
        `\\s+${escaped}$`,
        "i"
      ),
      ""
    );
  }

  return result.trim();
}
'''

marker = "function createSmartTitle(payload) {"

if helper_code.strip() not in background:
    background = background.replace(
        marker,
        helper_code.strip() + "\n\n" + marker,
        1,
    )

# -------------------------------------------------------------------
# Replace title generator
# -------------------------------------------------------------------

new_title = r'''
function createSmartTitle(payload) {
  const rawLabel =
    payload.elementText ||
    payload.ariaLabel ||
    payload.placeholder ||
    "";

  const label =
    removeSiteSuffix(rawLabel, payload);

  const type =
    classifyElement(payload, label);

  const site = titleCase(
    cleanSiteName(payload.hostname)
  );

  if (/sign-in/i.test(type)) {
    return "Open Sign In";
  }

  if (/sign-up/i.test(type)) {
    return "Open Sign Up";
  }

  if (/create.*issue|new issue/i.test(label)) {
    return "Create Issue";
  }

  if (
    /new repository|create repository/i.test(label)
  ) {
    return "Create Repository";
  }

  if (type === "search box") {
    return "Use Search";
  }

  if (type === "search result") {
    return label
      ? `Open ${label.slice(0, 55)}`
      : "Open Search Result";
  }

  if (type === "button") {
    return label
      ? `Click ${label.slice(0, 55)}`
      : "Click Button";
  }

  if (type === "link") {
    return label
      ? `Open ${label.slice(0, 55)}`
      : "Open Link";
  }

  if (label) {
    return `Select ${label.slice(0, 55)}`;
  }

  if (site) {
    return `Continue on ${site}`;
  }

  return "Continue to Next Step";
}
'''

background, count = re.subn(
    r'function createSmartTitle\(payload\) \{.*?\n\}',
    new_title.strip(),
    background,
    count=1,
    flags=re.S,
)

if count != 1:
    raise SystemExit(
        "Could not replace createSmartTitle in background.js"
    )

# -------------------------------------------------------------------
# Replace action-description generator
# -------------------------------------------------------------------

new_action = r'''
function createLocalAction(payload) {
  const rawLabel =
    payload.elementText ||
    payload.ariaLabel ||
    payload.placeholder ||
    "";

  const label =
    removeSiteSuffix(rawLabel, payload);

  const type =
    classifyElement(payload, label);

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
'''

background, count = re.subn(
    r'function createLocalAction\(payload\) \{.*?\n\}',
    new_action.strip(),
    background,
    count=1,
    flags=re.S,
)

if count != 1:
    raise SystemExit(
        "Could not replace createLocalAction in background.js"
    )

# -------------------------------------------------------------------
# Improve text extraction in content.js
# -------------------------------------------------------------------

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

  // Prefer heading text inside search-result links.
  const heading = element.querySelector(
    "h1, h2, h3, h4, [role='heading']"
  );

  if (heading?.textContent) {
    return cleanText(heading.textContent);
  }

  // Prefer a short direct text fragment.
  const textNodes = Array.from(
    element.childNodes
  )
    .filter(
      (node) => node.nodeType === Node.TEXT_NODE
    )
    .map((node) => cleanText(node.textContent))
    .filter(Boolean);

  if (textNodes.length > 0) {
    return cleanText(textNodes[0]);
  }

  return cleanText(
    element.innerText ||
      element.textContent ||
      element.getAttribute("name") ||
      element.tagName.toLowerCase()
  );
}
'''

content, count = re.subn(
    r'function getElementLabel\(element\) \{.*?\n\}',
    new_get_label.strip(),
    content,
    count=1,
    flags=re.S,
)

if count != 1:
    raise SystemExit(
        "Could not replace getElementLabel in content.js"
    )

background_path.write_text(background)
content_path.write_text(content)

print("✅ Smart titles updated")
print("✅ Element text cleanup updated")
print("✅ Search-result detection added")
print("✅ Natural action descriptions added")
PY

echo ""
echo "Checking extension JavaScript..."

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
