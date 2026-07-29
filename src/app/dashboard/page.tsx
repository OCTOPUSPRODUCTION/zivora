"use client";

import {
  BookOpen,
  Copy,
  FileCheck2,
  Grid2X2,
  List,
  LogOut,
  Plus,
  Search,
  Trash2,
} from "lucide-react";
import Link from "next/link";
import {
  useRouter,
} from "next/navigation";
import {
  useEffect,
  useMemo,
  useState,
} from "react";
import { createClient } from "@/lib/supabase/client";
import type {
  Guide,
  GuideStatus,
} from "@/lib/types";

type GuideFilter =
  | "all"
  | GuideStatus;

type ViewMode =
  | "grid"
  | "list";

export default function DashboardPage() {
  const router = useRouter();

  const [guides, setGuides] =
    useState<Guide[]>([]);

  const [query, setQuery] =
    useState("");

  const [filter, setFilter] =
    useState<GuideFilter>("all");

  const [view, setView] =
    useState<ViewMode>("grid");

  const [loading, setLoading] =
    useState(true);

  useEffect(() => {
    void loadGuides();
  }, []);

  async function loadGuides() {
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
        data,
        error,
      } = await supabase
        .from("guides")
        .select("*")
        .order("updated_at", {
          ascending: false,
        });

      if (error) {
        throw error;
      }

      setGuides(
        (data ?? []) as Guide[],
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not load guides.",
      );
    } finally {
      setLoading(false);
    }
  }

  async function createGuide() {
    try {
      const supabase = createClient();

      const {
        data: authData,
      } = await supabase.auth.getUser();

      if (!authData.user) {
        router.push("/login");
        return;
      }

      const {
        data: newGuide,
        error,
      } = await supabase
        .from("guides")
        .insert({
          user_id: authData.user.id,
          title: "Untitled guide",
          description:
            "A new step-by-step workflow guide.",
          status: "draft",
          is_public: false,
        })
        .select()
        .single();

      if (error || !newGuide) {
        throw (
          error ??
          new Error(
            "Could not create guide.",
          )
        );
      }

      const {
        error: stepError,
      } = await supabase
        .from("steps")
        .insert({
          guide_id: newGuide.id,
          position: 0,
          title: "First step",
          description:
            "Explain what the reader should do.",
        });

      if (stepError) {
        throw stepError;
      }

      router.push(
        `/guides/${newGuide.id}/edit`,
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not create guide.",
      );
    }
  }

  async function duplicateGuide(
    guide: Guide,
  ) {
    try {
      const supabase = createClient();

      const {
        data: authData,
      } = await supabase.auth.getUser();

      if (!authData.user) {
        return;
      }

      const {
        data: newGuide,
        error,
      } = await supabase
        .from("guides")
        .insert({
          user_id: authData.user.id,
          title: `${guide.title} copy`,
          description:
            guide.description,
          status: "draft",
          is_public: false,
        })
        .select()
        .single();

      if (error || !newGuide) {
        throw (
          error ??
          new Error(
            "Could not duplicate guide.",
          )
        );
      }

      const {
        data: sourceSteps,
        error: stepsError,
      } = await supabase
        .from("steps")
        .select("*")
        .eq(
          "guide_id",
          guide.id,
        )
        .order("position");

      if (stepsError) {
        throw stepsError;
      }

      if (
        sourceSteps &&
        sourceSteps.length > 0
      ) {
        const {
          error: insertError,
        } = await supabase
          .from("steps")
          .insert(
            sourceSteps.map(
              (step) => ({
                guide_id:
                  newGuide.id,
                position:
                  step.position,
                title:
                  step.title,
                description:
                  step.description,
                image_url:
                  step.image_url,
              }),
            ),
          );

        if (insertError) {
          throw insertError;
        }
      }

      await loadGuides();
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not duplicate guide.",
      );
    }
  }

  async function deleteGuide(
    guideId: string,
  ) {
    const confirmed =
      window.confirm(
        "Delete this guide permanently?",
      );

    if (!confirmed) {
      return;
    }

    try {
      const supabase = createClient();

      const {
        error,
      } = await supabase
        .from("guides")
        .delete()
        .eq("id", guideId);

      if (error) {
        throw error;
      }

      setGuides(
        (current) =>
          current.filter(
            (guide) =>
              guide.id !== guideId,
          ),
      );
    } catch (error) {
      alert(
        error instanceof Error
          ? error.message
          : "Could not delete guide.",
      );
    }
  }

  async function signOut() {
    const supabase = createClient();

    await supabase.auth.signOut();

    router.push("/");
    router.refresh();
  }

  const filteredGuides =
    useMemo(() => {
      const normalizedQuery =
        query.trim().toLowerCase();

      return guides.filter(
        (guide) => {
          const matchesSearch =
            !normalizedQuery ||
            guide.title
              .toLowerCase()
              .includes(
                normalizedQuery,
              ) ||
            guide.description
              .toLowerCase()
              .includes(
                normalizedQuery,
              );

          const matchesFilter =
            filter === "all" ||
            guide.status === filter;

          return (
            matchesSearch &&
            matchesFilter
          );
        },
      );
    }, [
      guides,
      query,
      filter,
    ]);

  const publishedCount =
    guides.filter(
      (guide) =>
        guide.status ===
        "published",
    ).length;

  const draftCount =
    guides.filter(
      (guide) =>
        guide.status ===
        "draft",
    ).length;

  return (
    <main className="phaseDashboard">
      <aside className="phaseSidebar">
        <div>
          <Link
            href="/"
            className="phaseLogo"
          >
            <span>Z</span>
            Zivora
          </Link>

          <nav>
            <button className="active">
              <BookOpen size={18} />
              My guides
            </button>
          </nav>
        </div>

        <button
          className="phaseSignOut"
          onClick={signOut}
        >
          <LogOut size={18} />
          Sign out
        </button>
      </aside>

      <section className="phaseWorkspace">
        <header className="phaseWorkspaceHeader">
          <div>
            <p className="phaseEyebrow">
              WORKSPACE
            </p>

            <h1>My guides</h1>

            <p>
              Create, edit and share
              workflow documentation.
            </p>
          </div>

          <button
            className="phasePrimary"
            onClick={createGuide}
          >
            <Plus size={18} />
            New guide
          </button>
        </header>

        <section className="phaseStats">
          <article>
            <span>
              All guides
            </span>

            <strong>
              {guides.length}
            </strong>
          </article>

          <article>
            <span>
              Published
            </span>

            <strong>
              {publishedCount}
            </strong>

            <FileCheck2 size={20} />
          </article>

          <article>
            <span>
              Drafts
            </span>

            <strong>
              {draftCount}
            </strong>
          </article>
        </section>

        <section className="phaseToolbar">
          <label>
            <Search size={18} />

            <input
              value={query}
              onChange={(event) =>
                setQuery(
                  event.target.value,
                )
              }
              placeholder="Search guides"
            />
          </label>

          <div className="phaseFilters">
            {(
              [
                "all",
                "published",
                "draft",
              ] as const
            ).map((item) => (
              <button
                key={item}
                className={
                  filter === item
                    ? "active"
                    : ""
                }
                onClick={() =>
                  setFilter(item)
                }
              >
                {item}
              </button>
            ))}
          </div>

          <div className="phaseViewButtons">
            <button
              aria-label="Grid view"
              className={
                view === "grid"
                  ? "active"
                  : ""
              }
              onClick={() =>
                setView("grid")
              }
            >
              <Grid2X2 size={17} />
            </button>

            <button
              aria-label="List view"
              className={
                view === "list"
                  ? "active"
                  : ""
              }
              onClick={() =>
                setView("list")
              }
            >
              <List size={17} />
            </button>
          </div>
        </section>

        {loading ? (
          <p>Loading guides...</p>
        ) : filteredGuides.length ? (
          <section
            className={
              view === "grid"
                ? "phaseGuideGrid"
                : "phaseGuideList"
            }
          >
            {filteredGuides.map(
              (guide) => (
                <article
                  className="phaseGuideCard"
                  key={guide.id}
                >
                  <Link
                    href={`/guides/${guide.id}/edit`}
                  >
                    <div className="phaseThumb">
                      <BookOpen
                        size={34}
                      />
                    </div>

                    <div className="phaseGuideCardBody">
                      <span
                        className={`phaseStatus ${guide.status}`}
                      >
                        {guide.status}
                      </span>

                      <h2>
                        {guide.title}
                      </h2>

                      <p>
                        {
                          guide.description
                        }
                      </p>

                      <small>
                        Updated{" "}
                        {new Date(
                          guide.updated_at,
                        ).toLocaleDateString(
                          "en-GB",
                        )}
                      </small>
                    </div>
                  </Link>

                  <footer>
                    <button
                      onClick={() =>
                        duplicateGuide(
                          guide,
                        )
                      }
                    >
                      <Copy size={16} />
                      Duplicate
                    </button>

                    <button
                      onClick={() =>
                        deleteGuide(
                          guide.id,
                        )
                      }
                    >
                      <Trash2
                        size={16}
                      />
                      Delete
                    </button>
                  </footer>
                </article>
              ),
            )}
          </section>
        ) : (
          <section className="phaseEmpty">
            <BookOpen size={38} />

            <h2>
              No guides found
            </h2>

            <p>
              Create your first
              workflow guide.
            </p>

            <button
              className="phasePrimary"
              onClick={createGuide}
            >
              <Plus size={18} />
              New guide
            </button>
          </section>
        )}
      </section>
    </main>
  );
}
