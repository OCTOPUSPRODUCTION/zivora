"use client";

import {
  ArrowDown,
  ArrowLeft,
  ArrowUp,
  Check,
  Copy,
  Eye,
  ImagePlus,
  Loader2,
  Plus,
  Save,
  Share2,
  Trash2,
  X,
} from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
  ChangeEvent,
  useEffect,
  useRef,
  useState,
} from "react";
import { createClient } from "@/lib/supabase/client";
import type { Guide, Step } from "@/lib/types";

type SaveStatus =
  | "saved"
  | "saving"
  | "error";

export default function GuideEditorPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const guideId = params.id;

  const [guide, setGuide] =
    useState<Guide | null>(null);

  const [steps, setSteps] =
    useState<Step[]>([]);

  const [loading, setLoading] =
    useState(true);

  const [saveStatus, setSaveStatus] =
    useState<SaveStatus>("saved");

  const [previewMode, setPreviewMode] =
    useState(true);

  const [publishing, setPublishing] =
    useState(false);

  const [copied, setCopied] =
    useState(false);

  const [uploadingStepId, setUploadingStepId] =
    useState<string | null>(null);

  const guideSaveTimer =
    useRef<ReturnType<typeof setTimeout> | null>(null);

  const stepSaveTimers =
    useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  useEffect(() => {
    void loadGuide();

    return () => {
      if (guideSaveTimer.current) {
        clearTimeout(guideSaveTimer.current);
      }

      Object.values(stepSaveTimers.current).forEach(
        clearTimeout,
      );
    };
  }, [guideId]);

  async function loadGuide() {
    setLoading(true);

    try {
      const supabase = createClient();

      const {
        data: authData,
      } = await supabase.auth.getUser();

      if (!authData.user) {
        router.replace("/login");
        return;
      }

      const {
        data: guideData,
        error: guideError,
      } = await supabase
        .from("guides")
        .select("*")
        .eq("id", guideId)
        .single();

      if (guideError) {
        throw guideError;
      }

      const {
        data: stepData,
        error: stepError,
      } = await supabase
        .from("steps")
        .select("*")
        .eq("guide_id", guideId)
        .order("position", {
          ascending: true,
        });

      if (stepError) {
        throw stepError;
      }

      setGuide(guideData as Guide);
      setSteps((stepData ?? []) as Step[]);
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not load this guide.",
      );
    } finally {
      setLoading(false);
    }
  }

  function updateGuideLocally(
    changes: Partial<Guide>,
  ) {
    if (!guide) {
      return;
    }

    const updatedGuide = {
      ...guide,
      ...changes,
    };

    setGuide(updatedGuide);
    setSaveStatus("saving");

    if (guideSaveTimer.current) {
      clearTimeout(guideSaveTimer.current);
    }

    guideSaveTimer.current = setTimeout(() => {
      void saveGuide(changes);
    }, 650);
  }

  async function saveGuide(
    changes: Partial<Guide>,
  ) {
    try {
      const supabase = createClient();

      const {
        error,
      } = await supabase
        .from("guides")
        .update(changes)
        .eq("id", guideId);

      if (error) {
        throw error;
      }

      setSaveStatus("saved");
    } catch {
      setSaveStatus("error");
    }
  }

  function updateStepLocally(
    stepId: string,
    changes: Partial<Step>,
  ) {
    setSteps((current) =>
      current.map((step) =>
        step.id === stepId
          ? {
              ...step,
              ...changes,
            }
          : step,
      ),
    );

    setSaveStatus("saving");

    if (stepSaveTimers.current[stepId]) {
      clearTimeout(
        stepSaveTimers.current[stepId],
      );
    }

    stepSaveTimers.current[stepId] =
      setTimeout(() => {
        void saveStep(stepId, changes);
      }, 650);
  }

  async function saveStep(
    stepId: string,
    changes: Partial<Step>,
  ) {
    try {
      const supabase = createClient();

      const {
        error,
      } = await supabase
        .from("steps")
        .update(changes)
        .eq("id", stepId);

      if (error) {
        throw error;
      }

      setSaveStatus("saved");
    } catch {
      setSaveStatus("error");
    }
  }

  async function addStep() {
    try {
      const supabase = createClient();

      const {
        data,
        error,
      } = await supabase
        .from("steps")
        .insert({
          guide_id: guideId,
          position: steps.length,
          title: `Step ${steps.length + 1}`,
          description:
            "Explain what the reader should do in this step.",
          image_url: null,
        })
        .select()
        .single();

      if (error || !data) {
        throw (
          error ??
          new Error("Could not add the step.")
        );
      }

      setSteps((current) => [
        ...current,
        data as Step,
      ]);

      setSaveStatus("saved");
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not add the step.",
      );
    }
  }

  async function duplicateStep(
    step: Step,
  ) {
    try {
      const supabase = createClient();

      const insertPosition =
        steps.findIndex(
          (item) => item.id === step.id,
        ) + 1;

      const reordered = steps.map(
        (item, index) => ({
          ...item,
          position:
            index >= insertPosition
              ? index + 1
              : index,
        }),
      );

      await Promise.all(
        reordered
          .filter(
            (item) =>
              item.position !==
              steps.find(
                (existing) =>
                  existing.id === item.id,
              )?.position,
          )
          .map((item) =>
            supabase
              .from("steps")
              .update({
                position: item.position,
              })
              .eq("id", item.id),
          ),
      );

      const {
        data,
        error,
      } = await supabase
        .from("steps")
        .insert({
          guide_id: guideId,
          position: insertPosition,
          title: `${step.title} copy`,
          description: step.description,
          image_url: step.image_url,
        })
        .select()
        .single();

      if (error || !data) {
        throw (
          error ??
          new Error(
            "Could not duplicate the step.",
          )
        );
      }

      const result = [
        ...reordered.slice(0, insertPosition),
        data as Step,
        ...reordered.slice(insertPosition),
      ].map((item, index) => ({
        ...item,
        position: index,
      }));

      setSteps(result);
      setSaveStatus("saved");
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not duplicate the step.",
      );
    }
  }

  async function deleteStep(
    stepId: string,
  ) {
    const confirmed =
      window.confirm(
        "Delete this step permanently?",
      );

    if (!confirmed) {
      return;
    }

    try {
      const supabase = createClient();

      const {
        error,
      } = await supabase
        .from("steps")
        .delete()
        .eq("id", stepId);

      if (error) {
        throw error;
      }

      const remaining = steps
        .filter((step) => step.id !== stepId)
        .map((step, position) => ({
          ...step,
          position,
        }));

      setSteps(remaining);

      await Promise.all(
        remaining.map((step) =>
          supabase
            .from("steps")
            .update({
              position: step.position,
            })
            .eq("id", step.id),
        ),
      );

      setSaveStatus("saved");
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not delete the step.",
      );
    }
  }

  async function moveStep(
    index: number,
    direction: -1 | 1,
  ) {
    const targetIndex =
      index + direction;

    if (
      targetIndex < 0 ||
      targetIndex >= steps.length
    ) {
      return;
    }

    const reordered = [...steps];

    [
      reordered[index],
      reordered[targetIndex],
    ] = [
      reordered[targetIndex],
      reordered[index],
    ];

    const normalized = reordered.map(
      (step, position) => ({
        ...step,
        position,
      }),
    );

    setSteps(normalized);
    setSaveStatus("saving");

    try {
      const supabase = createClient();

      await Promise.all(
        normalized.map((step) =>
          supabase
            .from("steps")
            .update({
              position: step.position,
            })
            .eq("id", step.id),
        ),
      );

      setSaveStatus("saved");
    } catch {
      setSaveStatus("error");
    }
  }

  async function uploadImage(
    stepId: string,
    event: ChangeEvent<HTMLInputElement>,
  ) {
    const file =
      event.target.files?.[0];

    if (!file) {
      return;
    }

    if (
      ![
        "image/png",
        "image/jpeg",
        "image/webp",
      ].includes(file.type)
    ) {
      alert(
        "Please upload a PNG, JPG or WEBP image.",
      );
      return;
    }

    if (file.size > 8 * 1024 * 1024) {
      alert(
        "The image must be smaller than 8 MB.",
      );
      return;
    }

    setUploadingStepId(stepId);

    try {
      const supabase = createClient();

      const extension =
        file.name.split(".").pop() ?? "png";

      const storagePath =
        `${guideId}/${stepId}-${Date.now()}.${extension}`;

      const {
        error: uploadError,
      } = await supabase.storage
        .from("guide-images")
        .upload(storagePath, file, {
          upsert: false,
        });

      if (uploadError) {
        throw uploadError;
      }

      const {
        data: publicData,
      } = supabase.storage
        .from("guide-images")
        .getPublicUrl(storagePath);

      await saveStep(stepId, {
        image_url: publicData.publicUrl,
      });

      setSteps((current) =>
        current.map((step) =>
          step.id === stepId
            ? {
                ...step,
                image_url:
                  publicData.publicUrl,
              }
            : step,
        ),
      );

      setSaveStatus("saved");
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not upload the screenshot.",
      );
    } finally {
      setUploadingStepId(null);
      event.target.value = "";
    }
  }

  async function removeImage(
    stepId: string,
  ) {
    const confirmed =
      window.confirm(
        "Remove this screenshot?",
      );

    if (!confirmed) {
      return;
    }

    await saveStep(stepId, {
      image_url: null,
    });

    setSteps((current) =>
      current.map((step) =>
        step.id === stepId
          ? {
              ...step,
              image_url: null,
            }
          : step,
      ),
    );
  }

  async function togglePublish() {
    if (!guide) {
      return;
    }

    setPublishing(true);

    const publishing =
      guide.status === "draft";

    try {
      const changes: Partial<Guide> = {
        status:
          publishing
            ? "published"
            : "draft",
        is_public: publishing,
      };

      const supabase = createClient();

      const {
        error,
      } = await supabase
        .from("guides")
        .update(changes)
        .eq("id", guide.id);

      if (error) {
        throw error;
      }

      setGuide({
        ...guide,
        ...changes,
      });

      setSaveStatus("saved");
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not update publishing.",
      );
    } finally {
      setPublishing(false);
    }
  }

  async function publishAndCopyLink() {
    if (!guide) {
      return;
    }

    setPublishing(true);

    try {
      const supabase = createClient();

      const {
        error,
      } = await supabase
        .from("guides")
        .update({
          status: "published",
          is_public: true,
        })
        .eq("id", guide.id);

      if (error) {
        throw error;
      }

      setGuide({
        ...guide,
        status: "published",
        is_public: true,
      });

      const publicUrl =
        `${window.location.origin}/share/${guide.id}`;

      await navigator.clipboard.writeText(
        publicUrl,
      );

      setCopied(true);

      window.setTimeout(
        () => setCopied(false),
        2000,
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not publish the guide.",
      );
    } finally {
      setPublishing(false);
    }
  }

  if (loading) {
    return (
      <main className="phaseEditorLoading">
        <Loader2
          className="phaseSpin"
          size={28}
        />
        Loading guide...
      </main>
    );
  }

  if (!guide) {
    return (
      <main className="phaseEditorLoading">
        Guide not found.
      </main>
    );
  }

  return (
    <main className="phaseEditorPro">
      <header className="phaseEditorTopbar">
        <Link
          href="/dashboard"
          className="phaseBackButton"
        >
          <ArrowLeft size={17} />
          Dashboard
        </Link>

        <div
          className={`phaseSaveStatus ${saveStatus}`}
        >
          {saveStatus === "saving" ? (
            <Loader2
              className="phaseSpin"
              size={15}
            />
          ) : saveStatus === "saved" ? (
            <Check size={15} />
          ) : (
            <Save size={15} />
          )}

          {saveStatus === "saving"
            ? "Saving..."
            : saveStatus === "saved"
              ? "Saved"
              : "Save failed"}
        </div>

        <div className="phaseEditorTopActions">
          <button
            className="phaseEditorSecondary"
            onClick={() =>
              setPreviewMode(
                (current) => !current,
              )
            }
          >
            <Eye size={17} />
            {previewMode
              ? "Edit guide"
              : "Finish editing"}
          </button>

          <button
            className="phaseEditorSecondary"
            disabled={publishing}
            onClick={togglePublish}
          >
            {guide.status === "draft"
              ? "Publish"
              : "Unpublish"}
          </button>

          <button
            className="phaseEditorPrimary"
            disabled={publishing}
            onClick={publishAndCopyLink}
          >
            {publishing ? (
              <Loader2
                className="phaseSpin"
                size={17}
              />
            ) : copied ? (
              <Check size={17} />
            ) : (
              <Share2 size={17} />
            )}

            {copied
              ? "Link copied"
              : "Publish and copy link"}
          </button>
        </div>
      </header>

      <section className="phaseEditorContainer">
        {previewMode ? (
          <article className="phasePreviewDocument">
            <div className="phasePreviewHeader">
              <span
                className={`phaseEditorBadge ${guide.status}`}
              >
                {guide.status}
              </span>

              <h1>{guide.title}</h1>
              <p>{guide.description}</p>
            </div>

            <div className="phasePreviewSteps">
              {steps.map(
                (step, index) => (
                  <section
                    className="phasePreviewStep"
                    key={step.id}
                  >
                    <span>
                      {index + 1}
                    </span>

                    <div>
                      <h2>
                        {step.title}
                      </h2>

                      <p>
                        {
                          step.description
                        }
                      </p>

                      {step.image_url && (
                        <img
                          src={
                            step.image_url
                          }
                          alt={step.title}
                        />
                      )}
                    </div>
                  </section>
                ),
              )}
            </div>
          </article>
        ) : (
          <>
            <section className="phaseEditorGuideHeader">
              <div className="phaseEditorGuideStatusRow">
                <span
                  className={`phaseEditorBadge ${guide.status}`}
                >
                  {guide.status}
                </span>

                <small>
                  Click the title or description
                  to edit
                </small>
              </div>

              <input
                className="phaseEditorTitleInput"
                aria-label="Guide title"
                value={guide.title}
                onChange={(event) =>
                  updateGuideLocally({
                    title:
                      event.target.value,
                  })
                }
                placeholder="Guide title"
              />

              <textarea
                className="phaseEditorDescriptionInput"
                aria-label="Guide description"
                value={guide.description}
                onChange={(event) =>
                  updateGuideLocally({
                    description:
                      event.target.value,
                  })
                }
                placeholder="Describe what this guide helps someone complete."
              />
            </section>

            <section className="phaseEditorSteps">
              {steps.map(
                (step, index) => (
                  <article
                    className="phaseEditorStepCard"
                    key={step.id}
                  >
                    <span className="phaseEditorStepNumber">
                      {index + 1}
                    </span>

                    <div className="phaseEditorStepContent">
                      <input
                        className="phaseEditorStepTitle"
                        value={step.title}
                        aria-label={`Step ${index + 1} title`}
                        onChange={(event) =>
                          updateStepLocally(
                            step.id,
                            {
                              title:
                                event.target
                                  .value,
                            },
                          )
                        }
                        placeholder="Step title"
                      />

                      <textarea
                        className="phaseEditorStepDescription"
                        value={
                          step.description
                        }
                        aria-label={`Step ${index + 1} description`}
                        onChange={(event) =>
                          updateStepLocally(
                            step.id,
                            {
                              description:
                                event.target
                                  .value,
                            },
                          )
                        }
                        placeholder="Explain what the reader should do."
                      />

                      {step.image_url ? (
                        <div className="phaseEditorImageBox">
                          <img
                            src={
                              step.image_url
                            }
                            alt={step.title}
                          />

                          <button
                            onClick={() =>
                              removeImage(
                                step.id,
                              )
                            }
                          >
                            <X size={15} />
                            Remove screenshot
                          </button>
                        </div>
                      ) : (
                        <label className="phaseEditorUploadBox">
                          {uploadingStepId ===
                          step.id ? (
                            <>
                              <Loader2
                                className="phaseSpin"
                                size={25}
                              />
                              <strong>
                                Uploading...
                              </strong>
                            </>
                          ) : (
                            <>
                              <ImagePlus
                                size={25}
                              />

                              <strong>
                                Upload screenshot
                              </strong>

                              <small>
                                PNG, JPG or WEBP,
                                maximum 8 MB
                              </small>
                            </>
                          )}

                          <input
                            type="file"
                            accept="image/png,image/jpeg,image/webp"
                            disabled={
                              uploadingStepId ===
                              step.id
                            }
                            onChange={(
                              event,
                            ) =>
                              uploadImage(
                                step.id,
                                event,
                              )
                            }
                          />
                        </label>
                      )}
                    </div>

                    <div className="phaseEditorStepActions">
                      <button
                        title="Move step up"
                        disabled={index === 0}
                        onClick={() =>
                          moveStep(
                            index,
                            -1,
                          )
                        }
                      >
                        <ArrowUp
                          size={16}
                        />
                      </button>

                      <button
                        title="Move step down"
                        disabled={
                          index ===
                          steps.length - 1
                        }
                        onClick={() =>
                          moveStep(
                            index,
                            1,
                          )
                        }
                      >
                        <ArrowDown
                          size={16}
                        />
                      </button>

                      <button
                        title="Duplicate step"
                        onClick={() =>
                          duplicateStep(
                            step,
                          )
                        }
                      >
                        <Copy size={16} />
                      </button>

                      <button
                        className="phaseEditorDeleteButton"
                        title="Delete step"
                        onClick={() =>
                          deleteStep(
                            step.id,
                          )
                        }
                      >
                        <Trash2
                          size={16}
                        />
                      </button>
                    </div>
                  </article>
                ),
              )}
            </section>

            <button
              className="phaseEditorAddStep"
              onClick={addStep}
            >
              <Plus size={18} />
              Add another step
            </button>
          </>
        )}
      </section>
    </main>
  );
}
