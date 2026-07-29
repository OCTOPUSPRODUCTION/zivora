"use client";

import {
  useParams,
} from "next/navigation";
import {
  useEffect,
  useState,
} from "react";
import { createClient } from "@/lib/supabase/client";
import type {
  Guide,
  Step,
} from "@/lib/types";

export default function SharedGuidePage() {
  const params =
    useParams<{ id: string }>();

  const guideId =
    params.id;

  const [guide, setGuide] =
    useState<Guide | null>(null);

  const [steps, setSteps] =
    useState<Step[]>([]);

  const [loading, setLoading] =
    useState(true);

  useEffect(() => {
    void loadPublicGuide();
  }, [guideId]);

  async function loadPublicGuide() {
    try {
      const supabase =
        createClient();

      const {
        data: guideData,
        error: guideError,
      } = await supabase
        .from("guides")
        .select("*")
        .eq("id", guideId)
        .eq("is_public", true)
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
    } catch {
      setGuide(null);
    } finally {
      setLoading(false);
    }
  }

  if (loading) {
    return (
      <main className="phaseLoading">
        Loading shared guide...
      </main>
    );
  }

  if (!guide) {
    return (
      <main className="phaseLoading">
        This guide is unavailable
        or private.
      </main>
    );
  }

  return (
    <main className="phaseShare">
      <header>
        <span>Z</span>
        Zivora
      </header>

      <article>
        <p className="phaseEyebrow">
          SHARED GUIDE
        </p>

        <h1>
          {guide.title}
        </h1>

        <p className="phaseShareDescription">
          {guide.description}
        </p>

        <div className="phaseShareSteps">
          {steps.map(
            (step, index) => (
              <section key={step.id}>
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
    </main>
  );
}
