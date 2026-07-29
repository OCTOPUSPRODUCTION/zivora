"use client";

import {
  ArrowDown,
  ArrowUp,
  Check,
  Copy,
  ImagePlus,
  Plus,
  Share2,
  Trash2,
} from "lucide-react";
import Link from "next/link";
import {
  useParams,
  useRouter,
} from "next/navigation";
import {
  ChangeEvent,
  useEffect,
  useState,
} from "react";
import { createClient } from "@/lib/supabase/client";
import type {
  Guide,
  Step,
} from "@/lib/types";

export default function GuideEditorPage() {
  const params =
    useParams<{ id: string }>();

  const router = useRouter();

  const guideId = params.id;

  const [guide, setGuide] =
    useState<Guide | null>(null);

  const [steps, setSteps] =
    useState<Step[]>([]);

  const [saveStatus, setSaveStatus] =
    useState<
      "saved" |
      "saving" |
      "error"
    >("saved");

  const [loading, setLoading] =
    useState(true);

  useEffect(() => {
    void loadGuide();
  }, [guideId]);

  async function loadGuide() {
    try {
      const supabase =
        createClient();

      const {
        data: authData,
      } =
        await supabase.auth.getUser();

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

      setGuide(
        guideData as Guide,
      );

      setSteps(
        (stepData ?? []) as Step[],
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not load guide.",
      );
    } finally {
      setLoading(false);
    }
  }

  async function updateGuide(
    changes: Partial<Guide>,
  ) {
    if (!guide) {
      return;
    }

    setSaveStatus("saving");

    setGuide({
      ...guide,
      ...changes,
    });

    try {
      const supabase =
        createClient();

      const {
        error,
      } = await supabase
        .from("guides")
        .update(changes)
        .eq("id", guide.id);

      if (error) {
        throw error;
      }

      setSaveStatus("saved");
    } catch {
      setSaveStatus("error");
    }
  }

  async function updateStep(
    stepId: string,
    changes: Partial<Step>,
  ) {
    setSaveStatus("saving");

    setSteps(
      (current) =>
        current.map((step) =>
          step.id === stepId
            ? {
                ...step,
                ...changes,
              }
            : step,
        ),
    );

    try {
      const supabase =
        createClient();

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
      const supabase =
        createClient();

      const {
        data,
        error,
      } = await supabase
        .from("steps")
        .insert({
          guide_id: guideId,
          position: steps.length,
          title:
            `Step ${steps.length + 1}`,
          description:
            "Explain what the reader should do.",
        })
        .select()
        .single();

      if (error || !data) {
        throw (
          error ??
          new Error(
            "Could not add step.",
          )
        );
      }

      setSteps(
        (current) => [
          ...current,
          data as Step,
        ],
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not add step.",
      );
    }
  }

  async function duplicateStep(
    step: Step,
  ) {
    try {
      const supabase =
        createClient();

      const {
        data,
        error,
      } = await supabase
        .from("steps")
        .insert({
          guide_id: guideId,
          position: steps.length,
          title:
            `${step.title} copy`,
          description:
            step.description,
          image_url:
            step.image_url,
        })
        .select()
        .single();

      if (error || !data) {
        throw (
          error ??
          new Error(
            "Could not duplicate step.",
          )
        );
      }

      setSteps(
        (current) => [
          ...current,
          data as Step,
        ],
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not duplicate step.",
      );
    }
  }

  async function removeStep(
    stepId: string,
  ) {
    const confirmed =
      window.confirm(
        "Delete this step?",
      );

    if (!confirmed) {
      return;
    }

    try {
      const supabase =
        createClient();

      const {
        error,
      } = await supabase
        .from("steps")
        .delete()
        .eq("id", stepId);

      if (error) {
        throw error;
      }

      const remaining =
        steps.filter(
          (step) =>
            step.id !== stepId,
        );

      setSteps(remaining);

      await savePositions(
        remaining,
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not delete step.",
      );
    }
  }

  async function savePositions(
    reorderedSteps: Step[],
  ) {
    const supabase =
      createClient();

    await Promise.all(
      reorderedSteps.map(
        (step, index) =>
          supabase
            .from("steps")
            .update({
              position: index,
            })
            .eq("id", step.id),
      ),
    );
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

    const reordered = [
      ...steps,
    ];

    [
      reordered[index],
      reordered[targetIndex],
    ] = [
      reordered[targetIndex],
      reordered[index],
    ];

    const normalized =
      reordered.map(
        (step, position) => ({
          ...step,
          position,
        }),
      );

    setSteps(normalized);
    setSaveStatus("saving");

    try {
      await savePositions(
        normalized,
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

    try {
      const supabase =
        createClient();

      const safeFileName =
        file.name.replace(
          /[^a-zA-Z0-9._-]/g,
          "-",
        );

      const storagePath =
        `${guideId}/${stepId}-${Date.now()}-${safeFileName}`;

      const {
        error,
      } = await supabase.storage
        .from("guide-images")
        .upload(
          storagePath,
          file,
          {
            upsert: false,
          },
        );

      if (error) {
        throw error;
      }

      const {
        data,
      } = supabase.storage
        .from("guide-images")
        .getPublicUrl(
          storagePath,
        );

      await updateStep(
        stepId,
        {
          image_url:
            data.publicUrl,
        },
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not upload image.",
      );
    }
  }

  async function removeImage(
    stepId: string,
  ) {
    await updateStep(
      stepId,
      {
        image_url: null,
      },
    );
  }

  async function publishAndCopyLink() {
    if (!guide) {
      return;
    }

    try {
      await updateGuide({
        status: "published",
        is_public: true,
      });

      const publicUrl =
        `${window.location.origin}/share/${guide.id}`;

      await navigator.clipboard.writeText(
        publicUrl,
      );

      alert(
        "Guide published and public link copied.",
      );
    } catch {
      alert(
        "Could not publish guide.",
      );
    }
  }

  async function togglePublish() {
    if (!guide) {
      return;
    }

    const publishing =
      guide.status === "draft";

    await updateGuide({
      status:
        publishing
          ? "published"
          : "draft",
      is_public:
        publishing,
    });
  }

  if (loading) {
    return (
      <main className="phaseLoading">
        Loading guide...
      </main>
    );
  }

  if (!guide) {
    return (
      <main className="phaseLoading">
        Guide not found.
      </main>
    );
  }

  return (
    <main className="phaseEditor">
      <header>
        <Link href="/dashboard">
          ← Dashboard
        </Link>

        <span
          className={`saveState ${saveStatus}`}
        >
          <Check size={15} />

          {saveStatus === "saved"
            ? "Saved"
            : saveStatus === "saving"
              ? "Saving..."
              : "Save failed"}
        </span>

        <button
          className="phaseSecondary"
          onClick={togglePublish}
        >
          {guide.status === "draft"
            ? "Publish"
            : "Unpublish"}
        </button>

        <button
          className="phasePrimary"
          onClick={
            publishAndCopyLink
          }
        >
          <Share2 size={17} />
          Publish and copy link
        </button>
      </header>

      <section className="phaseEditorContent">
        <section className="phaseGuideHeader">
          <span
            className={`phaseStatus ${guide.status}`}
          >
            {guide.status}
          </span>

          <input
            aria-label="Guide title"
            value={guide.title}
            onChange={(event) =>
              updateGuide({
                title:
                  event.target.value,
              })
            }
          />

          <textarea
            aria-label="Guide description"
            value={
              guide.description
            }
            onChange={(event) =>
              updateGuide({
                description:
                  event.target.value,
              })
            }
          />
        </section>

        <section className="phaseSteps">
          {steps.map(
            (step, index) => (
              <article
                className="phaseStep"
                key={step.id}
              >
                <span className="phaseStepNumber">
                  {index + 1}
                </span>

                <div className="phaseStepBody">
                  <input
                    aria-label={`Step ${index + 1} title`}
                    value={step.title}
                    onChange={(
                      event,
                    ) =>
                      updateStep(
                        step.id,
                        {
                          title:
                            event
                              .target
                              .value,
                        },
                      )
                    }
                  />

                  <textarea
                    aria-label={`Step ${index + 1} description`}
                    value={
                      step.description
                    }
                    onChange={(
                      event,
                    ) =>
                      updateStep(
                        step.id,
                        {
                          description:
                            event
                              .target
                              .value,
                        },
                      )
                    }
                  />

                  {step.image_url ? (
                    <div className="phaseImage">
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
                        Remove image
                      </button>
                    </div>
                  ) : (
                    <label className="phaseUpload">
                      <ImagePlus
                        size={24}
                      />

                      <strong>
                        Upload screenshot
                      </strong>

                      <small>
                        PNG, JPG or WEBP
                      </small>

                      <input
                        type="file"
                        accept="image/png,image/jpeg,image/webp"
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

                <div className="phaseStepActions">
                  <button
                    aria-label="Move step up"
                    disabled={
                      index === 0
                    }
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
                    aria-label="Move step down"
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
                    aria-label="Duplicate step"
                    onClick={() =>
                      duplicateStep(
                        step,
                      )
                    }
                  >
                    <Copy size={16} />
                  </button>

                  <button
                    aria-label="Delete step"
                    onClick={() =>
                      removeStep(
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
          className="phaseAddStep"
          onClick={addStep}
        >
          <Plus size={18} />
          Add another step
        </button>
      </section>
    </main>
  );
}
