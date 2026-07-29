#!/bin/bash

set -e

echo "Creating Zivora Phase 2 workflow capture..."

mkdir -p extension/icons
mkdir -p src/app/capture/import

###############################################################################
# CHROME EXTENSION MANIFEST
###############################################################################

cat > extension/manifest.json <<'EOF'
{
  "manifest_version": 3,
  "name": "Zivora Workflow Capture",
  "version": "1.0.0",
  "description": "Record browser workflows and turn them into Zivora guides.",
  "permissions": [
    "activeTab",
    "tabs",
    "storage",
    "scripting",
    "downloads"
  ],
  "host_permissions": [
    "<all_urls>"
  ],
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

###############################################################################
# EXTENSION BACKGROUND
###############################################################################

cat > extension/background.js <<'EOF'
let recording = false;
let steps = [];
let recordingTitle = "Captured workflow";
let startedAt = null;

async function saveState() {
  await chrome.storage.local.set({
    recording,
    steps,
    recordingTitle,
    startedAt
  });
}

async function loadState() {
  const state = await chrome.storage.local.get([
    "recording",
    "steps",
    "recordingTitle",
    "startedAt"
  ]);

  recording = Boolean(state.recording);
  steps = Array.isArray(state.steps) ? state.steps : [];
  recordingTitle = state.recordingTitle || "Captured workflow";
  startedAt = state.startedAt || null;
}

function makeStepTitle(payload) {
  const text = String(payload.text || "").trim();
  const tag = String(payload.tagName || "element").toLowerCase();

  if (text) {
    return `Click "${text.slice(0, 80)}"`;
  }

  if (payload.ariaLabel) {
    return `Click "${payload.ariaLabel.slice(0, 80)}"`;
  }

  if (payload.placeholder) {
    return `Select ${payload.placeholder.slice(0, 80)}`;
  }

  return `Click the ${tag}`;
}

async function captureScreenshot(sender) {
  try {
    if (!sender.tab || typeof sender.tab.windowId !== "number") {
      return null;
    }

    return await chrome.tabs.captureVisibleTab(sender.tab.windowId, {
      format: "jpeg",
      quality: 75
    });
  } catch (error) {
    console.warn("Screenshot capture failed:", error);
    return null;
  }
}

chrome.runtime.onInstalled.addListener(async () => {
  await loadState();
  await saveState();
});

chrome.runtime.onStartup.addListener(loadState);

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
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
        String(message.title || "").trim() || "Captured workflow";
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

    if (message.type === "CAPTURE_CLICK") {
      if (!recording) {
        sendResponse({ success: false, ignored: true });
        return;
      }

      const payload = message.payload || {};
      const screenshot = await captureScreenshot(sender);

      const step = {
        id: crypto.randomUUID(),
        position: steps.length,
        title: makeStepTitle(payload),
        description: [
          payload.url ? `Page: ${payload.url}` : "",
          payload.selector ? `Element: ${payload.selector}` : ""
        ]
          .filter(Boolean)
          .join("\n"),
        url: payload.url || "",
        selector: payload.selector || "",
        elementText: payload.text || "",
        tagName: payload.tagName || "",
        screenshot,
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
        version: 1,
        source: "zivora-chrome-extension",
        title: recordingTitle,
        description: `Workflow captured with Zivora on ${
          startedAt ? new Date(startedAt).toLocaleString() : "an unknown date"
        }.`,
        startedAt,
        exportedAt: new Date().toISOString(),
        steps
      };

      const dataUrl =
        "data:application/json;charset=utf-8," +
        encodeURIComponent(JSON.stringify(exportData, null, 2));

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
      error: error instanceof Error ? error.message : "Unexpected error"
    });
  });

  return true;
});
EOF

###############################################################################
# EXTENSION CONTENT SCRIPT
###############################################################################

cat > extension/content.js <<'EOF'
function cssEscape(value) {
  if (window.CSS && typeof window.CSS.escape === "function") {
    return window.CSS.escape(value);
  }

  return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
}

function getSelector(element) {
  if (!(element instanceof Element)) {
    return "";
  }

  if (element.id) {
    return `#${cssEscape(element.id)}`;
  }

  const parts = [];
  let current = element;

  while (
    current &&
    current.nodeType === Node.ELEMENT_NODE &&
    current !== document.body
  ) {
    let selector = current.tagName.toLowerCase();

    if (current.classList.length > 0) {
      selector +=
        "." +
        Array.from(current.classList)
          .slice(0, 2)
          .map(cssEscape)
          .join(".");
    }

    const parent = current.parentElement;

    if (parent) {
      const sameTagChildren = Array.from(parent.children).filter(
        (child) => child.tagName === current.tagName
      );

      if (sameTagChildren.length > 1) {
        selector += `:nth-of-type(${
          sameTagChildren.indexOf(current) + 1
        })`;
      }
    }

    parts.unshift(selector);
    current = current.parentElement;

    if (parts.length >= 5) {
      break;
    }
  }

  return parts.join(" > ");
}

function getUsefulText(element) {
  const directText =
    element.innerText ||
    element.textContent ||
    element.getAttribute("aria-label") ||
    element.getAttribute("title") ||
    element.getAttribute("placeholder") ||
    "";

  return String(directText).replace(/\s+/g, " ").trim().slice(0, 200);
}

document.addEventListener(
  "click",
  async (event) => {
    const target = event.target instanceof Element
      ? event.target.closest(
          "button, a, input, select, textarea, [role='button'], [role='link'], [tabindex]"
        ) || event.target
      : null;

    if (!(target instanceof Element)) {
      return;
    }

    try {
      await chrome.runtime.sendMessage({
        type: "CAPTURE_CLICK",
        payload: {
          url: window.location.href,
          title: document.title,
          selector: getSelector(target),
          text: getUsefulText(target),
          tagName: target.tagName,
          ariaLabel: target.getAttribute("aria-label") || "",
          placeholder: target.getAttribute("placeholder") || ""
        }
      });
    } catch {
      // Extension reloads can temporarily invalidate the message channel.
    }
  },
  true
);
EOF

###############################################################################
# EXTENSION POPUP
###############################################################################

cat > extension/popup.html <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1.0"
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
          <p>Record a workflow automatically.</p>
        </div>
      </div>

      <label for="title">Guide title</label>

      <input
        id="title"
        type="text"
        placeholder="Example: Create a new customer"
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

      <button id="clear" class="text-button">
        Clear recording
      </button>

      <p class="help">
        Export the workflow, then import the downloaded JSON file into Zivora.
      </p>
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
  width: 350px;
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
  width: 40px;
  height: 40px;
  place-items: center;
  border-radius: 11px;
  background: linear-gradient(135deg, #5b3df5, #7c4dff);
  color: white;
  font-size: 20px;
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

.text-button {
  background: transparent;
  color: #71717a;
}

.help {
  margin: 15px 0 0;
  color: #71717a;
  font-size: 11px;
  line-height: 1.5;
}
EOF

cat > extension/popup.js <<'EOF'
const titleInput = document.getElementById("title");
const statusElement = document.getElementById("status");
const counterElement = document.getElementById("counter");

const startButton = document.getElementById("start");
const stopButton = document.getElementById("stop");
const exportButton = document.getElementById("export");
const openImportButton = document.getElementById("openImport");
const clearButton = document.getElementById("clear");

async function sendMessage(message) {
  return chrome.runtime.sendMessage(message);
}

function render(state) {
  const recording = Boolean(state.recording);
  const count = Array.isArray(state.steps) ? state.steps.length : 0;

  if (state.recordingTitle && !titleInput.value) {
    titleInput.value = state.recordingTitle;
  }

  statusElement.textContent = recording
    ? "Recording in progress"
    : "Not recording";

  statusElement.classList.toggle("recording", recording);

  counterElement.textContent =
    `${count} step${count === 1 ? "" : "s"} captured`;

  startButton.disabled = recording;
  stopButton.disabled = !recording;
  exportButton.disabled = count === 0;
  titleInput.disabled = recording;
}

async function refresh() {
  const state = await sendMessage({
    type: "GET_STATE"
  });

  render(state);
}

startButton.addEventListener("click", async () => {
  const response = await sendMessage({
    type: "START_RECORDING",
    title: titleInput.value
  });

  render(response);
  window.close();
});

stopButton.addEventListener("click", async () => {
  const response = await sendMessage({
    type: "STOP_RECORDING"
  });

  render(response);
});

exportButton.addEventListener("click", async () => {
  const response = await sendMessage({
    type: "EXPORT_RECORDING"
  });

  if (!response.success) {
    alert(response.error || "Could not export recording.");
  }
});

openImportButton.addEventListener("click", async () => {
  await chrome.tabs.create({
    url: "http://localhost:3000/capture/import"
  });
});

clearButton.addEventListener("click", async () => {
  const confirmed = confirm(
    "Delete all currently captured steps?"
  );

  if (!confirmed) {
    return;
  }

  const response = await sendMessage({
    type: "CLEAR_RECORDING"
  });

  titleInput.value = "";
  render(response);
});

refresh().catch((error) => {
  console.error(error);
  statusElement.textContent = "Extension error";
});
EOF

###############################################################################
# ZIVORA IMPORT PAGE
###############################################################################

cat > src/app/capture/import/page.tsx <<'EOF'
"use client";

import Link from "next/link";
import { ChangeEvent, DragEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";

type CapturedStep = {
  id?: string;
  position?: number;
  title: string;
  description?: string;
  url?: string;
  selector?: string;
  elementText?: string;
  tagName?: string;
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

function isCapturedWorkflow(value: unknown): value is CapturedWorkflow {
  if (!value || typeof value !== "object") {
    return false;
  }

  const workflow = value as Partial<CapturedWorkflow>;

  return (
    typeof workflow.title === "string" &&
    Array.isArray(workflow.steps) &&
    workflow.steps.every(
      (step) =>
        step &&
        typeof step === "object" &&
        typeof (step as CapturedStep).title === "string"
    )
  );
}

function dataUrlToBlob(dataUrl: string): Blob {
  const parts = dataUrl.split(",");

  if (parts.length !== 2) {
    throw new Error("Invalid screenshot format.");
  }

  const metadata = parts[0];
  const base64 = parts[1];

  const mimeMatch = metadata.match(/data:(.*?);base64/);
  const mimeType = mimeMatch?.[1] || "image/jpeg";

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return new Blob([bytes], {
    type: mimeType
  });
}

export default function CaptureImportPage() {
  const router = useRouter();

  const [workflow, setWorkflow] =
    useState<CapturedWorkflow | null>(null);

  const [fileName, setFileName] = useState("");
  const [dragging, setDragging] = useState(false);
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState("");
  const [progress, setProgress] = useState("");

  const stepCount = workflow?.steps.length ?? 0;

  const previewSteps = useMemo(
    () => workflow?.steps.slice(0, 5) ?? [],
    [workflow]
  );

  async function readFile(file: File) {
    setError("");
    setWorkflow(null);

    if (!file.name.toLowerCase().endsWith(".json")) {
      setError("Please select a Zivora JSON recording.");
      return;
    }

    try {
      const raw = await file.text();
      const parsed: unknown = JSON.parse(raw);

      if (!isCapturedWorkflow(parsed)) {
        throw new Error(
          "This file is not a valid Zivora workflow recording."
        );
      }

      if (parsed.steps.length === 0) {
        throw new Error(
          "The recording does not contain any captured steps."
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

  async function handleDrop(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    setDragging(false);

    const file = event.dataTransfer.files?.[0];

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

    const { error: uploadError } = await supabase.storage
      .from("guide-images")
      .upload(path, blob, {
        contentType: blob.type,
        upsert: false
      });

    if (uploadError) {
      throw uploadError;
    }

    const { data } = supabase.storage
      .from("guide-images")
      .getPublicUrl(path);

    return data.publicUrl;
  }

  async function importWorkflow() {
    if (!workflow || importing) {
      return;
    }

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
          "You must sign in to Zivora before importing a recording."
        );
      }

      setProgress("Creating guide...");

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
              "Workflow captured using the Zivora Chrome extension.",
            status: "draft",
            is_public: false
          })
          .select("id")
          .single();

      if (guideError || !guide) {
        throw guideError || new Error("Could not create guide.");
      }

      const insertedStepIds: string[] = [];

      try {
        for (
          let index = 0;
          index < workflow.steps.length;
          index += 1
        ) {
          const step = workflow.steps[index];

          setProgress(
            `Importing step ${index + 1} of ${workflow.steps.length}...`
          );

          let imageUrl: string | null = null;

          if (
            step.screenshot &&
            step.screenshot.startsWith("data:image/")
          ) {
            imageUrl = await uploadScreenshot(
              step.screenshot,
              user.id,
              guide.id,
              index
            );
          }

          const details = [
            step.description?.trim(),
            step.url ? `Captured page: ${step.url}` : ""
          ]
            .filter(Boolean)
            .join("\n\n");

          const { data: insertedStep, error: stepError } =
            await supabase
              .from("steps")
              .insert({
                guide_id: guide.id,
                position: index,
                title:
                  step.title.trim() ||
                  `Step ${index + 1}`,
                description: details,
                image_url: imageUrl
              })
              .select("id")
              .single();

          if (stepError || !insertedStep) {
            throw stepError || new Error(
              `Could not import step ${index + 1}.`
            );
          }

          insertedStepIds.push(insertedStep.id);
        }
      } catch (stepImportError) {
        await supabase
          .from("guides")
          .delete()
          .eq("id", guide.id);

        throw stepImportError;
      }

      setProgress("Import completed. Opening editor...");

      router.push(`/guides/${guide.id}/edit`);
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
              Workflow capture
            </p>

            <h1 className="text-3xl font-bold tracking-tight">
              Import a recorded workflow
            </h1>

            <p className="mt-2 text-sm text-zinc-500">
              Upload the JSON file exported by the Zivora Chrome
              extension.
            </p>
          </div>

          <Link
            href="/dashboard"
            className="rounded-xl border border-zinc-200 bg-white px-4 py-2.5 text-sm font-semibold shadow-sm transition hover:bg-zinc-50"
          >
            Back to dashboard
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
            onDragLeave={() => setDragging(false)}
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
              Select the JSON file downloaded from the extension.
            </p>

            <label className="mt-6 inline-flex cursor-pointer rounded-xl bg-violet-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-violet-700">
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
                    {stepCount} captured{" "}
                    {stepCount === 1 ? "step" : "steps"}
                  </p>
                </div>

                <button
                  type="button"
                  onClick={importWorkflow}
                  disabled={importing}
                  className="rounded-xl bg-violet-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-violet-700 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {importing
                    ? "Importing..."
                    : "Create Zivora guide"}
                </button>
              </div>

              {progress ? (
                <div className="mt-4 rounded-xl bg-violet-50 px-4 py-3 text-sm font-semibold text-violet-700">
                  {progress}
                </div>
              ) : null}

              <div className="mt-6 space-y-3">
                <h3 className="text-sm font-bold">
                  Recording preview
                </h3>

                {previewSteps.map((step, index) => (
                  <div
                    key={step.id || `${step.title}-${index}`}
                    className="flex gap-4 rounded-xl border border-zinc-200 p-4"
                  >
                    <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-violet-100 text-sm font-bold text-violet-700">
                      {index + 1}
                    </div>

                    <div className="min-w-0">
                      <p className="font-semibold">
                        {step.title}
                      </p>

                      {step.url ? (
                        <p className="mt-1 truncate text-xs text-zinc-400">
                          {step.url}
                        </p>
                      ) : null}
                    </div>
                  </div>
                ))}

                {stepCount > previewSteps.length ? (
                  <p className="text-center text-sm text-zinc-400">
                    And {stepCount - previewSteps.length} more steps
                  </p>
                ) : null}
              </div>
            </div>
          ) : null}
        </section>

        <section className="mt-6 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
          <h2 className="font-bold">
            How to record a workflow
          </h2>

          <div className="mt-4 grid gap-4 md:grid-cols-4">
            {[
              "Open the Zivora extension",
              "Start recording",
              "Complete your browser workflow",
              "Export and import the JSON file"
            ].map((instruction, index) => (
              <div
                key={instruction}
                className="rounded-xl bg-zinc-50 p-4"
              >
                <div className="mb-3 grid h-8 w-8 place-items-center rounded-full bg-violet-600 text-xs font-bold text-white">
                  {index + 1}
                </div>

                <p className="text-sm font-semibold">
                  {instruction}
                </p>
              </div>
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}
EOF

###############################################################################
# README FOR EXTENSION
###############################################################################

cat > extension/README.md <<'EOF'
# Zivora Workflow Capture Extension

## Install locally

1. Open Google Chrome.
2. Visit `chrome://extensions`.
3. Enable **Developer mode**.
4. Click **Load unpacked**.
5. Select the `extension` folder inside the Zivora project.

## Record a workflow

1. Open the Zivora extension.
2. Enter a guide title.
3. Click **Start recording**.
4. Perform the workflow in the browser.
5. Open the extension and click **Stop recording**.
6. Click **Export recording**.
7. Open `http://localhost:3000/capture/import`.
8. Upload the downloaded JSON file.
9. Click **Create Zivora guide**.
EOF

###############################################################################
# VERIFY AND BUILD
###############################################################################

echo ""
echo "Phase 2 files created."
echo ""

echo "Running production build..."
rm -rf .next
npm run build

echo ""
echo "Build completed successfully."
echo ""
echo "Starting Zivora..."
npm run dev
