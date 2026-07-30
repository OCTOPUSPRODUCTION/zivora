#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Creating backups..."
cp extension/background.js extension/background.js.before-auto-import
cp extension/content.js extension/content.js.before-auto-import

mkdir -p src/app/capture/auto-import

cat > src/app/capture/auto-import/page.tsx <<'EOF'
"use client";

import { useEffect, useRef, useState } from "react";
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

  const workflow = value as Partial<CapturedWorkflow>;

  return (
    typeof workflow.title === "string" &&
    Array.isArray(workflow.steps) &&
    workflow.steps.length > 0 &&
    workflow.steps.every(
      (step) =>
        step &&
        typeof step === "object" &&
        typeof (step as CapturedStep).title === "string"
    )
  );
}

function dataUrlToBlob(dataUrl: string): Blob {
  const [metadata, encoded] = dataUrl.split(",");

  if (!metadata || !encoded) {
    throw new Error("Invalid screenshot format.");
  }

  const mime =
    metadata.match(/data:(.*?);base64/)?.[1] ||
    "image/jpeg";

  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
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
  const website = cleanHostname(
    step.website || step.pageUrl
  );

  return [
    "📍 Website",
    website,
    "",
    "🎯 Element",
    enhanced.element ||
      step.element ||
      step.elementRole ||
      "Highlighted element",
    "",
    "📝 Action",
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
      throw new Error("Enhancement failed.");
    }

    const result = await response.json();

    return result.enhanced as EnhancedStep;
  } catch {
    return {
      title: step.title || "Captured step",
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

export default function AutoImportPage() {
  const router = useRouter();

  const startedRef = useRef(false);

  const [status, setStatus] = useState(
    "Connecting to the Zivora extension..."
  );

  const [error, setError] = useState("");

  useEffect(() => {
    function requestCapture() {
      window.dispatchEvent(
        new CustomEvent("ZIVORA_REQUEST_CAPTURE")
      );
    }

    async function handleCapture(
      event: Event
    ) {
      if (startedRef.current) return;

      const customEvent =
        event as CustomEvent<unknown>;

      const workflow = customEvent.detail;

      if (!isCapturedWorkflow(workflow)) {
        setError(
          "No valid recording was received from the extension."
        );
        setStatus("");
        return;
      }

      startedRef.current = true;

      try {
        await createGuide(workflow);
      } catch (caughtError) {
        console.error(caughtError);

        setError(
          caughtError instanceof Error
            ? caughtError.message
            : "Could not create the guide."
        );

        setStatus("");
        startedRef.current = false;
      }
    }

    window.addEventListener(
      "ZIVORA_CAPTURE_DATA",
      handleCapture
    );

    requestCapture();

    const retryTimer = window.setTimeout(
      requestCapture,
      1000
    );

    return () => {
      window.clearTimeout(retryTimer);

      window.removeEventListener(
        "ZIVORA_CAPTURE_DATA",
        handleCapture
      );
    };
  }, []);

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

  async function createGuide(
    workflow: CapturedWorkflow
  ) {
    const supabase = createClient();

    setStatus("Checking your Zivora account...");

    const {
      data: { user },
      error: userError
    } = await supabase.auth.getUser();

    if (userError || !user) {
      throw new Error(
        "You must be signed in to Zivora. Sign in, then stop the recording again."
      );
    }

    setStatus("Creating your guide...");

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
        new Error("Could not create the guide.")
      );
    }

    try {
      for (
        let index = 0;
        index < workflow.steps.length;
        index += 1
      ) {
        const step = workflow.steps[index];

        setStatus(
          `Preparing step ${index + 1} of ${workflow.steps.length}...`
        );

        const enhanced = await enhanceStep(step);

        let imageUrl: string | null = null;

        if (
          step.screenshot?.startsWith("data:image/")
        ) {
          setStatus(
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
                step.title ||
                `Step ${index + 1}`,
              description: structuredDescription(
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

    setStatus(
      "Guide created successfully. Opening the editor..."
    );

    window.dispatchEvent(
      new CustomEvent("ZIVORA_IMPORT_COMPLETE")
    );

    router.replace(
      `/guides/${guide.id}/edit`
    );
  }

  return (
    <main className="grid min-h-screen place-items-center bg-[#f7f7fb] px-5 text-zinc-950">
      <section className="w-full max-w-lg rounded-3xl border border-zinc-200 bg-white p-8 text-center shadow-xl shadow-zinc-200/50">
        <div className="mx-auto mb-5 grid h-16 w-16 place-items-center rounded-2xl bg-violet-100 text-3xl">
          {error ? "!" : "✨"}
        </div>

        <p className="mb-2 text-xs font-bold uppercase tracking-[0.18em] text-violet-600">
          Zivora smart capture
        </p>

        <h1 className="text-2xl font-bold tracking-tight">
          {error
            ? "Guide creation failed"
            : "Creating your guide"}
        </h1>

        {status && (
          <p className="mt-4 text-sm leading-6 text-zinc-600">
            {status}
          </p>
        )}

        {error && (
          <div className="mt-5 rounded-2xl border border-red-200 bg-red-50 p-4 text-left text-sm leading-6 text-red-700">
            {error}
          </div>
        )}

        {!error && (
          <div className="mx-auto mt-6 h-8 w-8 animate-spin rounded-full border-4 border-violet-200 border-t-violet-600" />
        )}

        {error && (
          <button
            type="button"
            onClick={() => {
              window.location.href =
                "/capture/import";
            }}
            className="mt-6 rounded-xl bg-violet-600 px-5 py-3 text-sm font-bold text-white"
          >
            Use manual JSON import
          </button>
        )}
      </section>
    </main>
  );
}
EOF

python3 <<'PY'
from pathlib import Path

background_path = Path("extension/background.js")
background = background_path.read_text()

old_stop = '''      if (message.type === "STOP_RECORDING") {
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
      }'''

new_stop = '''      if (message.type === "STOP_RECORDING") {
        recording = false;
        await saveState();

        if (steps.length === 0) {
          sendResponse({
            success: false,
            recording,
            steps,
            recordingTitle,
            startedAt,
            error: "No workflow steps were captured."
          });
          return;
        }

        await chrome.tabs.create({
          url: "http://localhost:3000/capture/auto-import"
        });

        sendResponse({
          success: true,
          recording,
          steps,
          recordingTitle,
          startedAt,
          creatingGuide: true
        });
        return;
      }'''

if old_stop not in background:
    raise SystemExit(
        "Could not find STOP_RECORDING block in extension/background.js"
    )

background = background.replace(
    old_stop,
    new_stop,
    1
)

marker = '''      if (message.type === "CLEAR_RECORDING") {'''

get_capture_block = '''      if (message.type === "GET_AUTO_IMPORT") {
        const workflow = {
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

        sendResponse({
          success: true,
          workflow
        });
        return;
      }

      if (message.type === "AUTO_IMPORT_COMPLETE") {
        recording = false;
        steps = [];
        recordingTitle = "Captured workflow";
        startedAt = null;

        await saveState();

        sendResponse({
          success: true
        });
        return;
      }

'''

if "GET_AUTO_IMPORT" not in background:
    background = background.replace(
        marker,
        get_capture_block + marker,
        1
    )

background_path.write_text(background)

content_path = Path("extension/content.js")
content = content_path.read_text()

bridge = r'''

// Zivora automatic import bridge.
// This allows the signed-in Zivora web application to request
// the completed recording from the extension.
if (!window.__zivoraAutoImportBridgeInstalled) {
  window.__zivoraAutoImportBridgeInstalled = true;

  window.addEventListener(
    "ZIVORA_REQUEST_CAPTURE",
    async () => {
      try {
        const response =
          await chrome.runtime.sendMessage({
            type: "GET_AUTO_IMPORT"
          });

        if (
          response?.success &&
          response.workflow
        ) {
          window.dispatchEvent(
            new CustomEvent(
              "ZIVORA_CAPTURE_DATA",
              {
                detail: response.workflow
              }
            )
          );
        }
      } catch (error) {
        console.error(
          "Could not provide Zivora capture:",
          error
        );
      }
    }
  );

  window.addEventListener(
    "ZIVORA_IMPORT_COMPLETE",
    async () => {
      try {
        await chrome.runtime.sendMessage({
          type: "AUTO_IMPORT_COMPLETE"
        });
      } catch (error) {
        console.error(
          "Could not clear completed Zivora capture:",
          error
        );
      }
    }
  );
}
'''

if "zivoraAutoImportBridgeInstalled" not in content:
    content += bridge

content_path.write_text(content)

popup_path = Path("extension/popup.js")
popup = popup_path.read_text()

old_popup_stop = '''stopButton.addEventListener("click", async () => {
  render(
    await sendMessage({
      type: "STOP_RECORDING"
    })
  );
});'''

new_popup_stop = '''stopButton.addEventListener("click", async () => {
  stopButton.disabled = true;
  statusElement.textContent = "Creating your guide...";

  try {
    const response = await sendMessage({
      type: "STOP_RECORDING"
    });

    if (!response.success) {
      throw new Error(
        response.error ||
          "Could not stop the recording."
      );
    }

    render(response);

    statusElement.textContent =
      "Opening Zivora...";

    window.setTimeout(() => {
      window.close();
    }, 500);
  } catch (error) {
    stopButton.disabled = false;

    statusElement.textContent =
      "Could not create guide";

    alert(
      error instanceof Error
        ? error.message
        : "Could not create the guide."
    );
  }
});'''

if old_popup_stop not in popup:
    raise SystemExit(
        "Could not find stop button block in extension/popup.js"
    )

popup = popup.replace(
    old_popup_stop,
    new_popup_stop,
    1
)

popup_path.write_text(popup)

print("Automatic import code installed.")
PY

echo ""
echo "Running production build..."
npm run build

echo ""
echo "============================================"
echo "INSTALLATION COMPLETE"
echo "============================================"
echo ""
echo "Next:"
echo "1. Open chrome://extensions"
echo "2. Reload the Zivora extension"
echo "3. Run: npm run dev"
echo "4. Sign in to Zivora"
echo "5. Start recording"
echo "6. Capture some clicks"
echo "7. Click Stop Recording"
echo ""
echo "The guide should be created automatically."
