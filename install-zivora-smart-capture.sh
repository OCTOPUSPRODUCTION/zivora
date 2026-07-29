#!/bin/bash
set -euo pipefail

cd ~/Desktop/zivora || exit 1

echo "Installing Zivora professional capture improvements..."

mkdir -p extension
mkdir -p src/app/api/ai/enhance-step
mkdir -p src/app/capture/import

cat > extension/manifest.json <<'EOF'
{
  "manifest_version": 3,
  "name": "Zivora Workflow Capture",
  "version": "2.0.0",
  "description": "Record polished browser workflows with focused screenshots and privacy protection.",
  "permissions": [
    "activeTab",
    "tabs",
    "storage",
    "downloads"
  ],
  "host_permissions": ["<all_urls>"],
  "background": {
    "service_worker": "background.js"
  },
  "action": {
    "default_popup": "popup.html",
    "default_title": "Zivora Capture"
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ]
}
EOF

cat > extension/content.js <<'EOF'
function safeEscape(value) {
  if (window.CSS && typeof window.CSS.escape === "function") {
    return window.CSS.escape(value);
  }
  return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
}

function getSelector(element) {
  if (!(element instanceof Element)) return "";

  if (element.id) {
    return `#${safeEscape(element.id)}`;
  }

  const parts = [];
  let current = element;

  while (
    current &&
    current !== document.body &&
    parts.length < 5
  ) {
    let part = current.tagName.toLowerCase();

    if (current.classList.length > 0) {
      part +=
        "." +
        Array.from(current.classList)
          .slice(0, 2)
          .map(safeEscape)
          .join(".");
    }

    const parent = current.parentElement;

    if (parent) {
      const siblings = Array.from(parent.children).filter(
        (child) => child.tagName === current.tagName
      );

      if (siblings.length > 1) {
        part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
      }
    }

    parts.unshift(part);
    current = current.parentElement;
  }

  return parts.join(" > ");
}

function cleanText(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 220);
}

function getElementLabel(element) {
  return cleanText(
    element.getAttribute("aria-label") ||
      element.getAttribute("title") ||
      element.getAttribute("placeholder") ||
      element.innerText ||
      element.textContent ||
      element.getAttribute("name") ||
      element.tagName.toLowerCase()
  );
}

function getElementRole(element) {
  const explicitRole = element.getAttribute("role");
  if (explicitRole) return explicitRole;

  const tag = element.tagName.toLowerCase();
  const type = element.getAttribute("type");

  if (tag === "a") return "link";
  if (tag === "button") return "button";
  if (tag === "input" && type === "search") return "search box";
  if (tag === "input") return "input";
  if (tag === "select") return "dropdown";
  if (tag === "textarea") return "text area";

  return tag;
}

function rectToPlain(rect) {
  return {
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height
  };
}

function isSensitiveElement(element) {
  if (!(element instanceof Element)) return false;

  const text = [
    element.getAttribute("name"),
    element.getAttribute("id"),
    element.getAttribute("autocomplete"),
    element.getAttribute("aria-label"),
    element.getAttribute("placeholder"),
    element.getAttribute("type")
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return (
    element instanceof HTMLInputElement &&
    element.type === "password"
  ) || /password|passwd|secret|token|api[-_ ]?key|access[-_ ]?key|auth|credit|card|cvv|cvc|account[-_ ]?id|email/.test(text);
}

function findSensitiveRects() {
  const candidates = Array.from(
    document.querySelectorAll(
      "input, textarea, [contenteditable='true'], [data-token], [data-secret]"
    )
  );

  return candidates
    .filter(isSensitiveElement)
    .map((element) => rectToPlain(element.getBoundingClientRect()))
    .filter(
      (rect) =>
        rect.width > 0 &&
        rect.height > 0 &&
        rect.x < window.innerWidth &&
        rect.y < window.innerHeight &&
        rect.x + rect.width > 0 &&
        rect.y + rect.height > 0
    );
}

function detectSensitiveTextRects() {
  const emailPattern =
    /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i;

  const tokenPattern =
    /\b(?:sk-|sb_|ghp_|github_pat_|AIza|eyJ)[A-Za-z0-9_\-.]{8,}\b/;

  const rects = [];

  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_TEXT
  );

  let node;

  while ((node = walker.nextNode())) {
    const text = cleanText(node.textContent);
    if (!text || (!emailPattern.test(text) && !tokenPattern.test(text))) {
      continue;
    }

    const parent = node.parentElement;
    if (!parent) continue;

    const rect = parent.getBoundingClientRect();

    if (
      rect.width > 0 &&
      rect.height > 0 &&
      rect.x < window.innerWidth &&
      rect.y < window.innerHeight
    ) {
      rects.push(rectToPlain(rect));
    }

    if (rects.length >= 20) break;
  }

  return rects;
}

document.addEventListener(
  "click",
  async (event) => {
    const rawTarget =
      event.target instanceof Element ? event.target : null;

    if (!rawTarget) return;

    const target =
      rawTarget.closest(
        "button, a, input, select, textarea, [role='button'], [role='link'], [tabindex]"
      ) || rawTarget;

    const rect = target.getBoundingClientRect();

    if (rect.width <= 0 || rect.height <= 0) return;

    try {
      await chrome.runtime.sendMessage({
        type: "CAPTURE_CLICK",
        payload: {
          pageUrl: window.location.href,
          pageTitle: document.title,
          hostname: window.location.hostname,
          elementText: getElementLabel(target),
          elementRole: getElementRole(target),
          tagName: target.tagName.toLowerCase(),
          selector: getSelector(target),
          ariaLabel: target.getAttribute("aria-label") || "",
          placeholder: target.getAttribute("placeholder") || "",
          rect: rectToPlain(rect),
          viewport: {
            width: window.innerWidth,
            height: window.innerHeight,
            devicePixelRatio: window.devicePixelRatio || 1
          },
          sensitiveRects: [
            ...findSensitiveRects(),
            ...detectSensitiveTextRects()
          ]
        }
      });
    } catch {
      // Extension reloads can temporarily invalidate the channel.
    }
  },
  true
);
EOF

cat > extension/background.js <<'EOF'
let recording = false;
let steps = [];
let recordingTitle = "Captured workflow";
let startedAt = null;

async function loadState() {
  const state = await chrome.storage.local.get([
    "recording",
    "steps",
    "recordingTitle",
    "startedAt"
  ]);

  recording = Boolean(state.recording);
  steps = Array.isArray(state.steps) ? state.steps : [];
  recordingTitle =
    state.recordingTitle || "Captured workflow";
  startedAt = state.startedAt || null;
}

async function saveState() {
  await chrome.storage.local.set({
    recording,
    steps,
    recordingTitle,
    startedAt
  });
}

function normaliseLabel(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .replace(/[|•·]+/g, " ")
    .trim()
    .slice(0, 90);
}

function titleCase(value) {
  return value.replace(/\b\w/g, (letter) =>
    letter.toUpperCase()
  );
}

function cleanSiteName(hostname) {
  return String(hostname || "")
    .replace(/^www\./, "")
    .split(".")[0]
    .replace(/[-_]/g, " ");
}

function createSmartTitle(payload) {
  const label = normaliseLabel(
    payload.elementText ||
      payload.ariaLabel ||
      payload.placeholder
  );

  const role = String(payload.elementRole || "").toLowerCase();
  const site = titleCase(cleanSiteName(payload.hostname));

  if (
    role === "link" &&
    /sign in|log in/i.test(label)
  ) {
    return "Open Sign In";
  }

  if (
    role === "link" &&
    /sign up|register|create account/i.test(label)
  ) {
    return "Open Sign Up";
  }

  if (
    /search/i.test(role) ||
    /search/i.test(label)
  ) {
    return label
      ? `Search using ${label.slice(0, 55)}`
      : "Use Search";
  }

  if (/create.*issue|new issue/i.test(label)) {
    return "Create Issue";
  }

  if (/new repository|create repository/i.test(label)) {
    return "Create Repository";
  }

  if (
    role === "link" &&
    label &&
    label.length <= 55
  ) {
    return `Open ${label}`;
  }

  if (
    role === "button" &&
    label &&
    label.length <= 55
  ) {
    return `Click ${label}`;
  }

  if (label) {
    return `Select ${label.slice(0, 55)}`;
  }

  if (site) {
    return `Continue on ${site}`;
  }

  return "Continue to the next step";
}

function createLocalAction(payload) {
  const label = normaliseLabel(
    payload.elementText ||
      payload.ariaLabel ||
      payload.placeholder
  );

  const role = String(payload.elementRole || "element");
  const site = titleCase(cleanSiteName(payload.hostname));

  if (label) {
    return `Click the ${role} labelled “${label}”${
      site ? ` on ${site}` : ""
    }.`;
  }

  return `Click the highlighted ${role}${
    site ? ` on ${site}` : ""
  }.`;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function dataUrlToBlob(dataUrl) {
  const [header, encoded] = dataUrl.split(",");
  const mime =
    header.match(/data:(.*?);base64/)?.[1] ||
    "image/jpeg";

  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return new Blob([bytes], { type: mime });
}

async function canvasToDataUrl(canvas, quality = 0.84) {
  const blob = await canvas.convertToBlob({
    type: "image/jpeg",
    quality
  });

  const buffer = await blob.arrayBuffer();
  const bytes = new Uint8Array(buffer);

  let binary = "";
  const chunkSize = 0x8000;

  for (
    let index = 0;
    index < bytes.length;
    index += chunkSize
  ) {
    binary += String.fromCharCode(
      ...bytes.subarray(index, index + chunkSize)
    );
  }

  return `data:image/jpeg;base64,${btoa(binary)}`;
}

async function processScreenshot(
  screenshotDataUrl,
  payload
) {
  const screenshotBlob = dataUrlToBlob(screenshotDataUrl);
  const bitmap = await createImageBitmap(screenshotBlob);

  const viewportWidth =
    payload.viewport?.width || bitmap.width;
  const viewportHeight =
    payload.viewport?.height || bitmap.height;

  const scaleX = bitmap.width / viewportWidth;
  const scaleY = bitmap.height / viewportHeight;

  const target = payload.rect || {
    x: 0,
    y: 0,
    width: viewportWidth,
    height: viewportHeight
  };

  const paddingX = Math.max(target.width * 1.8, 260);
  const paddingY = Math.max(target.height * 2.2, 180);

  const cropXCss = clamp(
    target.x - paddingX,
    0,
    viewportWidth
  );

  const cropYCss = clamp(
    target.y - paddingY,
    0,
    viewportHeight
  );

  const cropRightCss = clamp(
    target.x + target.width + paddingX,
    0,
    viewportWidth
  );

  const cropBottomCss = clamp(
    target.y + target.height + paddingY,
    0,
    viewportHeight
  );

  const cropX = Math.round(cropXCss * scaleX);
  const cropY = Math.round(cropYCss * scaleY);
  const cropWidth = Math.max(
    1,
    Math.round((cropRightCss - cropXCss) * scaleX)
  );
  const cropHeight = Math.max(
    1,
    Math.round((cropBottomCss - cropYCss) * scaleY)
  );

  const canvas = new OffscreenCanvas(
    cropWidth,
    cropHeight
  );

  const context = canvas.getContext("2d");

  context.drawImage(
    bitmap,
    cropX,
    cropY,
    cropWidth,
    cropHeight,
    0,
    0,
    cropWidth,
    cropHeight
  );

  const sensitiveRects = Array.isArray(
    payload.sensitiveRects
  )
    ? payload.sensitiveRects
    : [];

  for (const sensitive of sensitiveRects) {
    const x =
      (sensitive.x - cropXCss) * scaleX;
    const y =
      (sensitive.y - cropYCss) * scaleY;
    const width = sensitive.width * scaleX;
    const height = sensitive.height * scaleY;

    if (
      x + width < 0 ||
      y + height < 0 ||
      x > cropWidth ||
      y > cropHeight
    ) {
      continue;
    }

    const safeX = clamp(x, 0, cropWidth);
    const safeY = clamp(y, 0, cropHeight);
    const safeWidth = clamp(
      width,
      1,
      cropWidth - safeX
    );
    const safeHeight = clamp(
      height,
      1,
      cropHeight - safeY
    );

    context.save();
    context.filter = "blur(14px)";

    context.drawImage(
      canvas,
      safeX,
      safeY,
      safeWidth,
      safeHeight,
      safeX,
      safeY,
      safeWidth,
      safeHeight
    );

    context.restore();

    context.fillStyle = "rgba(25, 25, 30, 0.28)";
    context.fillRect(
      safeX,
      safeY,
      safeWidth,
      safeHeight
    );
  }

  const highlightX =
    (target.x - cropXCss) * scaleX;
  const highlightY =
    (target.y - cropYCss) * scaleY;
  const highlightWidth = target.width * scaleX;
  const highlightHeight = target.height * scaleY;

  const centerX =
    highlightX + highlightWidth / 2;
  const centerY =
    highlightY + highlightHeight / 2;

  const radius = Math.max(
    24,
    Math.min(
      58,
      Math.max(highlightWidth, highlightHeight) * 0.65
    )
  );

  context.save();

  context.beginPath();
  context.arc(centerX, centerY, radius, 0, Math.PI * 2);
  context.fillStyle = "rgba(239, 68, 68, 0.16)";
  context.fill();

  context.lineWidth = Math.max(4, radius * 0.11);
  context.strokeStyle = "rgba(239, 68, 68, 0.95)";
  context.stroke();

  context.beginPath();
  context.arc(
    centerX,
    centerY,
    Math.max(5, radius * 0.16),
    0,
    Math.PI * 2
  );
  context.fillStyle = "rgba(239, 68, 68, 0.98)";
  context.fill();

  context.restore();

  bitmap.close();

  return {
    screenshot: await canvasToDataUrl(canvas),
    crop: {
      x: cropXCss,
      y: cropYCss,
      width: cropRightCss - cropXCss,
      height: cropBottomCss - cropYCss
    },
    highlight: {
      x: centerX / cropWidth,
      y: centerY / cropHeight
    }
  };
}

async function captureVisible(sender, payload) {
  if (!sender.tab || sender.tab.windowId === undefined) {
    return {
      screenshot: null,
      crop: null,
      highlight: null
    };
  }

  const screenshotDataUrl =
    await chrome.tabs.captureVisibleTab(
      sender.tab.windowId,
      {
        format: "jpeg",
        quality: 88
      }
    );

  return processScreenshot(
    screenshotDataUrl,
    payload
  );
}

chrome.runtime.onInstalled.addListener(async () => {
  await loadState();
  await saveState();
});

chrome.runtime.onStartup.addListener(loadState);

chrome.runtime.onMessage.addListener(
  (message, sender, sendResponse) => {
    (async () => {
      await loadState();

      if (message.type === "GET_STATE") {
        sendResponse({
          success: true,
          recording,
          steps,
          recordingTitle,
          startedAt
        });
        return;
      }

      if (message.type === "START_RECORDING") {
        recording = true;
        steps = [];
        recordingTitle =
          String(message.title || "").trim() ||
          "Captured workflow";
        startedAt = new Date().toISOString();

        await saveState();

        sendResponse({
          success: true,
          recording,
          steps,
          recordingTitle,
          startedAt
        });
        return;
      }

      if (message.type === "STOP_RECORDING") {
        recording = false;
        await saveState();

        sendResponse({
          success: true,
          recording,
          steps,
          recordingTitle,
          startedAt
        });
        return;
      }

      if (message.type === "CLEAR_RECORDING") {
        recording = false;
        steps = [];
        recordingTitle = "Captured workflow";
        startedAt = null;

        await saveState();

        sendResponse({
          success: true,
          recording,
          steps,
          recordingTitle,
          startedAt
        });
        return;
      }

      if (
        message.type === "CAPTURE_CLICK" &&
        recording
      ) {
        const payload = message.payload || {};

        let processed = {
          screenshot: null,
          crop: null,
          highlight: null
        };

        try {
          processed = await captureVisible(
            sender,
            payload
          );
        } catch (error) {
          console.warn(
            "Screenshot processing failed:",
            error
          );
        }

        const step = {
          id: crypto.randomUUID(),
          position: steps.length,
          title: createSmartTitle(payload),
          action: createLocalAction(payload),
          website:
            payload.hostname || "Unknown website",
          element:
            normaliseLabel(payload.elementText) ||
            payload.elementRole ||
            payload.tagName ||
            "Highlighted element",
          pageUrl: payload.pageUrl || "",
          pageTitle: payload.pageTitle || "",
          selector: payload.selector || "",
          elementRole: payload.elementRole || "",
          screenshot: processed.screenshot,
          crop: processed.crop,
          highlight: processed.highlight,
          createdAt: new Date().toISOString()
        };

        steps.push(step);
        await saveState();

        sendResponse({
          success: true,
          stepCount: steps.length
        });
        return;
      }

      if (message.type === "EXPORT_RECORDING") {
        const exportData = {
          version: 2,
          source: "zivora-chrome-extension",
          title: recordingTitle,
          description: `Workflow captured with Zivora on ${
            startedAt
              ? new Date(startedAt).toLocaleString()
              : "an unknown date"
          }.`,
          startedAt,
          exportedAt: new Date().toISOString(),
          steps
        };

        const dataUrl =
          "data:application/json;charset=utf-8," +
          encodeURIComponent(
            JSON.stringify(exportData, null, 2)
          );

        await chrome.downloads.download({
          url: dataUrl,
          filename: `zivora-${Date.now()}.json`,
          saveAs: true
        });

        sendResponse({
          success: true,
          stepCount: steps.length
        });
        return;
      }

      sendResponse({
        success: false,
        error: "Unknown message type"
      });
    })().catch((error) => {
      console.error(error);

      sendResponse({
        success: false,
        error:
          error instanceof Error
            ? error.message
            : "Unexpected extension error"
      });
    });

    return true;
  }
);
EOF

cat > extension/popup.html <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1"
    />
    <title>Zivora Capture</title>
    <link rel="stylesheet" href="popup.css" />
  </head>

  <body>
    <main>
      <div class="brand">
        <div class="logo">Z</div>

        <div>
          <h1>Zivora Capture</h1>
          <p>Focused, private workflow recording.</p>
        </div>
      </div>

      <label for="title">Guide title</label>

      <input
        id="title"
        type="text"
        placeholder="Example: Create a GitHub issue"
      />

      <div id="status" class="status">
        Not recording
      </div>

      <div id="counter" class="counter">
        0 steps captured
      </div>

      <button id="start" class="primary">
        Start recording
      </button>

      <button id="stop" class="danger" disabled>
        Stop recording
      </button>

      <button id="export" class="secondary" disabled>
        Export recording
      </button>

      <button id="openImport" class="secondary">
        Open Zivora importer
      </button>

      <button id="clear" class="textButton">
        Clear recording
      </button>

      <div class="privacy">
        <strong>Privacy protection</strong>
        <span>
          Passwords, emails, tokens and API-key fields are blurred automatically.
        </span>
      </div>
    </main>

    <script src="popup.js"></script>
  </body>
</html>
EOF

cat > extension/popup.css <<'EOF'
* {
  box-sizing: border-box;
}

body {
  width: 360px;
  margin: 0;
  background: #f7f7fb;
  color: #17171c;
  font-family:
    Inter,
    ui-sans-serif,
    system-ui,
    -apple-system,
    BlinkMacSystemFont,
    "Segoe UI",
    sans-serif;
}

main {
  padding: 18px;
}

.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  margin-bottom: 20px;
}

.logo {
  display: grid;
  width: 42px;
  height: 42px;
  place-items: center;
  border-radius: 12px;
  background: linear-gradient(135deg, #5b3df5, #7c4dff);
  color: white;
  font-size: 21px;
  font-weight: 800;
}

h1 {
  margin: 0;
  font-size: 17px;
}

.brand p {
  margin: 3px 0 0;
  color: #71717a;
  font-size: 12px;
}

label {
  display: block;
  margin-bottom: 7px;
  font-size: 12px;
  font-weight: 700;
}

input {
  width: 100%;
  padding: 11px 12px;
  border: 1px solid #dedee8;
  border-radius: 9px;
  background: white;
  font-size: 13px;
  outline: none;
}

input:focus {
  border-color: #6847f5;
  box-shadow: 0 0 0 3px rgba(104, 71, 245, 0.12);
}

.status {
  margin-top: 14px;
  padding: 10px 12px;
  border-radius: 9px;
  background: #ececf3;
  font-size: 13px;
  font-weight: 700;
}

.status.recording {
  background: #feecec;
  color: #b42318;
}

.counter {
  margin: 9px 0 14px;
  color: #71717a;
  font-size: 12px;
}

button {
  width: 100%;
  margin-top: 8px;
  padding: 11px 13px;
  border: 0;
  border-radius: 9px;
  cursor: pointer;
  font-size: 13px;
  font-weight: 700;
}

button:disabled {
  cursor: not-allowed;
  opacity: 0.45;
}

.primary {
  background: #6847f5;
  color: white;
}

.danger {
  background: #dc2626;
  color: white;
}

.secondary {
  border: 1px solid #dedee8;
  background: white;
  color: #27272a;
}

.textButton {
  background: transparent;
  color: #71717a;
}

.privacy {
  margin-top: 14px;
  padding: 12px;
  display: grid;
  gap: 4px;
  border-radius: 10px;
  background: #ecfdf3;
  color: #166534;
  font-size: 11px;
  line-height: 1.45;
}
EOF

cat > extension/popup.js <<'EOF'
const titleInput = document.getElementById("title");
const statusElement = document.getElementById("status");
const counterElement = document.getElementById("counter");

const startButton = document.getElementById("start");
const stopButton = document.getElementById("stop");
const exportButton = document.getElementById("export");
const openImportButton =
  document.getElementById("openImport");
const clearButton = document.getElementById("clear");

async function sendMessage(message) {
  return chrome.runtime.sendMessage(message);
}

function render(state) {
  const active = Boolean(state.recording);
  const count = Array.isArray(state.steps)
    ? state.steps.length
    : 0;

  if (state.recordingTitle) {
    titleInput.value = state.recordingTitle;
  }

  statusElement.textContent = active
    ? "Recording in progress"
    : "Not recording";

  statusElement.classList.toggle(
    "recording",
    active
  );

  counterElement.textContent =
    `${count} step${count === 1 ? "" : "s"} captured`;

  startButton.disabled = active;
  stopButton.disabled = !active;
  exportButton.disabled = count === 0;
  titleInput.disabled = active;
}

startButton.addEventListener("click", async () => {
  const state = await sendMessage({
    type: "START_RECORDING",
    title: titleInput.value
  });

  render(state);
  window.close();
});

stopButton.addEventListener("click", async () => {
  render(
    await sendMessage({
      type: "STOP_RECORDING"
    })
  );
});

exportButton.addEventListener("click", async () => {
  const response = await sendMessage({
    type: "EXPORT_RECORDING"
  });

  if (!response.success) {
    alert(
      response.error ||
        "Could not export the recording."
    );
  }
});

openImportButton.addEventListener(
  "click",
  async () => {
    await chrome.tabs.create({
      url: "http://localhost:3000/capture/import"
    });
  }
);

clearButton.addEventListener("click", async () => {
  const confirmed = confirm(
    "Delete the current captured workflow?"
  );

  if (!confirmed) return;

  titleInput.value = "";

  render(
    await sendMessage({
      type: "CLEAR_RECORDING"
    })
  );
});

sendMessage({
  type: "GET_STATE"
})
  .then(render)
  .catch((error) => {
    console.error(error);
    statusElement.textContent = "Extension error";
  });
EOF

cat > src/app/api/ai/enhance-step/route.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";

type EnhanceRequest = {
  title?: string;
  action?: string;
  website?: string;
  element?: string;
  elementRole?: string;
  pageTitle?: string;
  pageUrl?: string;
};

type EnhancedStep = {
  title: string;
  action: string;
  element: string;
};

function clean(value: unknown, maximum = 180) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maximum);
}

function localFallback(
  body: EnhanceRequest
): EnhancedStep {
  const element =
    clean(body.element, 100) ||
    clean(body.elementRole, 60) ||
    "highlighted element";

  const website =
    clean(body.website, 80) || "this website";

  return {
    title:
      clean(body.title, 80) ||
      `Click ${element.slice(0, 55)}`,
    action:
      clean(body.action, 220) ||
      `Click the highlighted ${element} on ${website}.`,
    element
  };
}

function parseJsonText(text: string) {
  const cleaned = text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  return JSON.parse(cleaned) as EnhancedStep;
}

export async function POST(request: NextRequest) {
  let body: EnhanceRequest;

  try {
    body = (await request.json()) as EnhanceRequest;
  } catch {
    return NextResponse.json(
      { error: "Invalid request body." },
      { status: 400 }
    );
  }

  const fallback = localFallback(body);
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    return NextResponse.json({
      enhanced: fallback,
      source: "local"
    });
  }

  const model =
    process.env.OPENAI_MODEL || "gpt-5-mini";

  const prompt = {
    task:
      "Rewrite one browser workflow step as concise professional documentation.",
    requirements: [
      "Return only valid JSON.",
      "Use imperative language.",
      "Title must be 2 to 7 words.",
      "Action must be one clear sentence.",
      "Do not include CSS selectors, full URLs, query strings, IDs, tokens, or technical metadata.",
      "Do not invent actions not supported by the input.",
      "Keep element under 80 characters."
    ],
    output_schema: {
      title: "string",
      action: "string",
      element: "string"
    },
    input: {
      current_title: clean(body.title, 120),
      current_action: clean(body.action, 260),
      website: clean(body.website, 100),
      element: clean(body.element, 160),
      role: clean(body.elementRole, 80),
      page_title: clean(body.pageTitle, 160),
      page_url_without_query: clean(
        String(body.pageUrl || "").split("?")[0],
        180
      )
    }
  };

  try {
    const response = await fetch(
      "https://api.openai.com/v1/responses",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model,
          input: JSON.stringify(prompt),
          max_output_tokens: 220
        })
      }
    );

    if (!response.ok) {
      const details = await response.text();
      console.error(
        "OpenAI step enhancement failed:",
        response.status,
        details
      );

      return NextResponse.json({
        enhanced: fallback,
        source: "local"
      });
    }

    const data = await response.json();

    const outputText =
      data.output_text ||
      data.output
        ?.flatMap(
          (item: {
            content?: Array<{
              type?: string;
              text?: string;
            }>;
          }) => item.content || []
        )
        ?.find(
          (item: {
            type?: string;
            text?: string;
          }) => item.type === "output_text"
        )?.text;

    if (!outputText) {
      throw new Error("The model returned no text.");
    }

    const parsed = parseJsonText(outputText);

    const enhanced: EnhancedStep = {
      title:
        clean(parsed.title, 80) ||
        fallback.title,
      action:
        clean(parsed.action, 240) ||
        fallback.action,
      element:
        clean(parsed.element, 100) ||
        fallback.element
    };

    return NextResponse.json({
      enhanced,
      source: "openai"
    });
  } catch (error) {
    console.error(error);

    return NextResponse.json({
      enhanced: fallback,
      source: "local"
    });
  }
}
EOF

cat > src/app/capture/import/page.tsx <<'EOF'
"use client";

import Link from "next/link";
import {
  ChangeEvent,
  DragEvent,
  useMemo,
  useState
} from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";

type CapturedStep = {
  id?: string;
  position?: number;
  title: string;
  action?: string;
  website?: string;
  element?: string;
  elementRole?: string;
  pageUrl?: string;
  pageTitle?: string;
  selector?: string;
  screenshot?: string | null;
  createdAt?: string;
};

type CapturedWorkflow = {
  version?: number;
  source?: string;
  title: string;
  description?: string;
  startedAt?: string | null;
  exportedAt?: string;
  steps: CapturedStep[];
};

type EnhancedStep = {
  title: string;
  action: string;
  element: string;
};

function isCapturedWorkflow(
  value: unknown
): value is CapturedWorkflow {
  if (!value || typeof value !== "object") {
    return false;
  }

  const workflow =
    value as Partial<CapturedWorkflow>;

  return (
    typeof workflow.title === "string" &&
    Array.isArray(workflow.steps) &&
    workflow.steps.every(
      (step) =>
        step &&
        typeof step === "object" &&
        typeof (step as CapturedStep).title ===
          "string"
    )
  );
}

function dataUrlToBlob(dataUrl: string): Blob {
  const [metadata, encoded] =
    dataUrl.split(",");

  if (!metadata || !encoded) {
    throw new Error(
      "Invalid screenshot format."
    );
  }

  const mime =
    metadata.match(/data:(.*?);base64/)?.[1] ||
    "image/jpeg";

  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);

  for (
    let index = 0;
    index < binary.length;
    index += 1
  ) {
    bytes[index] = binary.charCodeAt(index);
  }

  return new Blob([bytes], {
    type: mime
  });
}

function cleanHostname(value?: string) {
  if (!value) return "Unknown website";

  try {
    return new URL(
      value.startsWith("http")
        ? value
        : `https://${value}`
    ).hostname.replace(/^www\./, "");
  } catch {
    return value.replace(/^www\./, "");
  }
}

function structuredDescription(
  stepNumber: number,
  step: CapturedStep,
  enhanced: EnhancedStep
) {
  const website =
    cleanHostname(
      step.website || step.pageUrl
    );

  return [
    `📍 Website`,
    website,
    "",
    `🎯 Element`,
    enhanced.element ||
      step.element ||
      step.elementRole ||
      "Highlighted element",
    "",
    `📝 Action`,
    enhanced.action ||
      step.action ||
      `Complete step ${stepNumber}.`
  ].join("\n");
}

async function enhanceStep(
  step: CapturedStep
): Promise<EnhancedStep> {
  try {
    const response = await fetch(
      "/api/ai/enhance-step",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(step)
      }
    );

    if (!response.ok) {
      throw new Error(
        "Step enhancement request failed."
      );
    }

    const result = await response.json();

    return result.enhanced as EnhancedStep;
  } catch {
    return {
      title: step.title,
      action:
        step.action ||
        `Click the highlighted ${
          step.elementRole || "element"
        }.`,
      element:
        step.element ||
        step.elementRole ||
        "Highlighted element"
    };
  }
}

export default function CaptureImportPage() {
  const router = useRouter();

  const [workflow, setWorkflow] =
    useState<CapturedWorkflow | null>(null);

  const [fileName, setFileName] =
    useState("");

  const [dragging, setDragging] =
    useState(false);

  const [importing, setImporting] =
    useState(false);

  const [error, setError] =
    useState("");

  const [progress, setProgress] =
    useState("");

  const previewSteps = useMemo(
    () => workflow?.steps.slice(0, 5) ?? [],
    [workflow]
  );

  async function readFile(file: File) {
    setError("");
    setWorkflow(null);

    if (
      !file.name.toLowerCase().endsWith(".json")
    ) {
      setError(
        "Please choose a Zivora JSON recording."
      );
      return;
    }

    try {
      const parsed: unknown = JSON.parse(
        await file.text()
      );

      if (!isCapturedWorkflow(parsed)) {
        throw new Error(
          "This is not a valid Zivora workflow recording."
        );
      }

      if (parsed.steps.length === 0) {
        throw new Error(
          "The recording contains no captured steps."
        );
      }

      setFileName(file.name);
      setWorkflow(parsed);
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not read the selected file."
      );
    }
  }

  async function handleFileChange(
    event: ChangeEvent<HTMLInputElement>
  ) {
    const file = event.target.files?.[0];

    if (file) {
      await readFile(file);
    }
  }

  async function handleDrop(
    event: DragEvent<HTMLDivElement>
  ) {
    event.preventDefault();
    setDragging(false);

    const file =
      event.dataTransfer.files?.[0];

    if (file) {
      await readFile(file);
    }
  }

  async function uploadScreenshot(
    screenshot: string,
    userId: string,
    guideId: string,
    position: number
  ) {
    const supabase = createClient();
    const blob = dataUrlToBlob(screenshot);

    const extension = blob.type.includes("png")
      ? "png"
      : "jpg";

    const path =
      `${userId}/${guideId}/capture-${position}-${crypto.randomUUID()}.${extension}`;

    const { error: uploadError } =
      await supabase.storage
        .from("guide-images")
        .upload(path, blob, {
          contentType: blob.type,
          upsert: false
        });

    if (uploadError) {
      throw uploadError;
    }

    return supabase.storage
      .from("guide-images")
      .getPublicUrl(path).data.publicUrl;
  }

  async function importWorkflow() {
    if (!workflow || importing) return;

    setImporting(true);
    setError("");
    setProgress("Checking your account...");

    const supabase = createClient();

    try {
      const {
        data: { user },
        error: userError
      } = await supabase.auth.getUser();

      if (userError || !user) {
        throw new Error(
          "You must sign in before importing a recording."
        );
      }

      setProgress("Creating your guide...");

      const { data: guide, error: guideError } =
        await supabase
          .from("guides")
          .insert({
            user_id: user.id,
            title:
              workflow.title.trim() ||
              "Captured workflow",
            description:
              workflow.description?.trim() ||
              "Workflow captured using Zivora.",
            status: "draft",
            is_public: false
          })
          .select("id")
          .single();

      if (guideError || !guide) {
        throw (
          guideError ||
          new Error("Could not create guide.")
        );
      }

      try {
        for (
          let index = 0;
          index < workflow.steps.length;
          index += 1
        ) {
          const step = workflow.steps[index];

          setProgress(
            `Improving step ${index + 1} of ${workflow.steps.length}...`
          );

          const enhanced =
            await enhanceStep(step);

          let imageUrl: string | null = null;

          if (
            step.screenshot?.startsWith(
              "data:image/"
            )
          ) {
            setProgress(
              `Uploading screenshot ${index + 1} of ${workflow.steps.length}...`
            );

            imageUrl = await uploadScreenshot(
              step.screenshot,
              user.id,
              guide.id,
              index
            );
          }

          const { error: stepError } =
            await supabase
              .from("steps")
              .insert({
                guide_id: guide.id,
                position: index,
                title:
                  enhanced.title ||
                  `Step ${index + 1}`,
                description:
                  structuredDescription(
                    index + 1,
                    step,
                    enhanced
                  ),
                image_url: imageUrl
              });

          if (stepError) {
            throw stepError;
          }
        }
      } catch (stepError) {
        await supabase
          .from("guides")
          .delete()
          .eq("id", guide.id);

        throw stepError;
      }

      setProgress(
        "Import complete. Opening the editor..."
      );

      router.push(
        `/guides/${guide.id}/edit`
      );
    } catch (caughtError) {
      console.error(caughtError);

      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not import workflow."
      );

      setProgress("");
      setImporting(false);
    }
  }

  return (
    <main className="min-h-screen bg-[#f7f7fb] px-5 py-10 text-zinc-950">
      <div className="mx-auto max-w-4xl">
        <header className="mb-8 flex items-center justify-between gap-4">
          <div>
            <p className="mb-2 text-xs font-bold uppercase tracking-[0.18em] text-violet-600">
              Smart workflow capture
            </p>

            <h1 className="text-3xl font-bold tracking-tight">
              Import a polished workflow
            </h1>

            <p className="mt-2 text-sm text-zinc-500">
              Zivora improves titles, creates natural instructions,
              highlights clicks, crops screenshots and protects sensitive data.
            </p>
          </div>

          <Link
            href="/dashboard"
            className="rounded-xl border border-zinc-200 bg-white px-4 py-2.5 text-sm font-semibold shadow-sm"
          >
            Dashboard
          </Link>
        </header>

        <section className="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div
            onDragEnter={(event) => {
              event.preventDefault();
              setDragging(true);
            }}
            onDragOver={(event) => {
              event.preventDefault();
              setDragging(true);
            }}
            onDragLeave={() =>
              setDragging(false)
            }
            onDrop={handleDrop}
            className={[
              "rounded-2xl border-2 border-dashed px-6 py-14 text-center transition",
              dragging
                ? "border-violet-500 bg-violet-50"
                : "border-zinc-200 bg-zinc-50"
            ].join(" ")}
          >
            <div className="mx-auto mb-4 grid h-14 w-14 place-items-center rounded-2xl bg-violet-100 text-2xl text-violet-700">
              ↑
            </div>

            <h2 className="text-lg font-bold">
              Drop your recording here
            </h2>

            <p className="mt-2 text-sm text-zinc-500">
              Select the JSON file exported by the updated extension.
            </p>

            <label className="mt-6 inline-flex cursor-pointer rounded-xl bg-violet-600 px-5 py-3 text-sm font-bold text-white">
              Select recording

              <input
                type="file"
                accept="application/json,.json"
                onChange={handleFileChange}
                className="hidden"
              />
            </label>
          </div>

          {error ? (
            <div className="mt-5 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-medium text-red-700">
              {error}
            </div>
          ) : null}

          {progress ? (
            <div className="mt-5 rounded-xl bg-violet-50 px-4 py-3 text-sm font-semibold text-violet-700">
              {progress}
            </div>
          ) : null}

          {workflow ? (
            <div className="mt-6">
              <div className="flex flex-col justify-between gap-4 rounded-2xl border border-zinc-200 p-5 sm:flex-row sm:items-center">
                <div>
                  <p className="text-xs font-semibold text-zinc-400">
                    {fileName}
                  </p>

                  <h2 className="mt-1 text-xl font-bold">
                    {workflow.title}
                  </h2>

                  <p className="mt-2 text-sm text-zinc-500">
                    {workflow.steps.length} captured steps
                  </p>
                </div>

                <button
                  type="button"
                  onClick={importWorkflow}
                  disabled={importing}
                  className="rounded-xl bg-violet-600 px-5 py-3 text-sm font-bold text-white disabled:opacity-60"
                >
                  {importing
                    ? "Creating guide..."
                    : "Create polished guide"}
                </button>
              </div>

              <div className="mt-6 space-y-3">
                {previewSteps.map(
                  (step, index) => (
                    <div
                      key={
                        step.id ||
                        `${step.title}-${index}`
                      }
                      className="flex gap-4 rounded-xl border border-zinc-200 p-4"
                    >
                      <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-violet-100 text-sm font-bold text-violet-700">
                        {index + 1}
                      </div>

                      <div className="min-w-0">
                        <p className="font-semibold">
                          {step.title}
                        </p>

                        <p className="mt-1 text-sm text-zinc-500">
                          {step.action}
                        </p>
                      </div>
                    </div>
                  )
                )}
              </div>
            </div>
          ) : null}
        </section>
      </div>
    </main>
  );
}
EOF

cat >> src/app/globals.css <<'EOF'

/* Structured captured-step descriptions */
.phaseEditorStepDescription,
.phasePreviewStep p {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  word-break: break-word;
}

/* Focused captured screenshots */
.phaseEditorImageBox,
.phasePreviewStep img {
  overflow: hidden;
  border: 1px solid #e5e1ea;
  border-radius: 16px;
  background: #f3f2f7;
}

.phaseEditorImageBox img,
.phasePreviewStep img {
  display: block;
  width: 100%;
  max-width: 100%;
  height: auto;
  max-height: 680px;
  margin-inline: auto;
  object-fit: contain;
  object-position: center;
}
EOF

if ! grep -q '^OPENAI_API_KEY=' .env.local 2>/dev/null; then
  cat >> .env.local <<'EOF'

# Optional: add a server-side OpenAI API key to enable LLM-written step titles.
# Never use NEXT_PUBLIC_ for this secret.
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5-mini
EOF
fi

echo ""
echo "Files installed."
echo "Building the application..."

rm -rf .next
npm run build

echo ""
echo "Stopping old Next.js servers..."
pkill -f "next dev" 2>/dev/null || true

echo ""
echo "Starting Zivora..."
npm run dev
