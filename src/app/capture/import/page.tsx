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
