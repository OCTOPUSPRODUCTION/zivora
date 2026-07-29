"use client";

import {
  ArrowRight,
  BookOpen,
  Check,
  ChevronLeft,
  FileText,
  Home as HomeIcon,
  MousePointerClick,
  Plus,
  Search,
  Share2,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

type Status = "draft" | "published";

type Step = {
  id: string;
  title: string;
  description: string;
};

type Guide = {
  id: string;
  title: string;
  description: string;
  status: Status;
  createdAt: string;
  updatedAt: string;
  steps: Step[];
};

type Screen = "landing" | "dashboard" | "editor";

const STORAGE_KEY = "zivora-guides";

const starterGuide: Guide = {
  id: "zivora-start-guide",
  title: "How to create your first Zivora guide",
  description:
    "Learn how to create, edit, publish and share a workflow guide.",
  status: "published",
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
  steps: [
    {
      id: "starter-1",
      title: "Open your Zivora workspace",
      description:
        "Go to the dashboard to view all the workflow guides in your workspace.",
    },
    {
      id: "starter-2",
      title: "Create a new guide",
      description:
        "Select New Guide and provide a useful title and description.",
    },
    {
      id: "starter-3",
      title: "Add your instructions",
      description:
        "Add a clear step for every action required to complete the process.",
    },
    {
      id: "starter-4",
      title: "Publish and share",
      description:
        "Publish your finished guide and copy the link to share it.",
    },
  ],
};

function createId(prefix: string) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function Logo() {
  return (
    <div className="logo">
      <div className="logoIcon">Z</div>
      <span>Zivora</span>
    </div>
  );
}

export default function Home() {
  const [screen, setScreen] = useState<Screen>("landing");
  const [guides, setGuides] = useState<Guide[]>([]);
  const [activeGuideId, setActiveGuideId] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [createModal, setCreateModal] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [copied, setCopied] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);

      if (saved) {
        setGuides(JSON.parse(saved));
      } else {
        setGuides([starterGuide]);
        localStorage.setItem(STORAGE_KEY, JSON.stringify([starterGuide]));
      }
    } catch {
      setGuides([starterGuide]);
    }

    setLoaded(true);
  }, []);

  useEffect(() => {
    if (loaded) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(guides));
    }
  }, [guides, loaded]);

  const activeGuide =
    guides.find((guide) => guide.id === activeGuideId) ?? null;

  const filteredGuides = useMemo(() => {
    const query = search.trim().toLowerCase();

    if (!query) {
      return guides;
    }

    return guides.filter(
      (guide) =>
        guide.title.toLowerCase().includes(query) ||
        guide.description.toLowerCase().includes(query),
    );
  }, [guides, search]);

  function openGuide(id: string) {
    setActiveGuideId(id);
    setScreen("editor");
  }

  function createGuide() {
    if (!newTitle.trim()) {
      return;
    }

    const now = new Date().toISOString();

    const guide: Guide = {
      id: createId("guide"),
      title: newTitle.trim(),
      description:
        newDescription.trim() ||
        "A step-by-step workflow guide created with Zivora.",
      status: "draft",
      createdAt: now,
      updatedAt: now,
      steps: [
        {
          id: createId("step"),
          title: "First step",
          description: "Explain what the reader should do in this step.",
        },
      ],
    };

    setGuides((current) => [guide, ...current]);
    setActiveGuideId(guide.id);
    setNewTitle("");
    setNewDescription("");
    setCreateModal(false);
    setScreen("editor");
  }

  function updateGuide(changes: Partial<Guide>) {
    if (!activeGuideId) return;

    setGuides((current) =>
      current.map((guide) =>
        guide.id === activeGuideId
          ? {
              ...guide,
              ...changes,
              updatedAt: new Date().toISOString(),
            }
          : guide,
      ),
    );
  }

  function updateStep(stepId: string, changes: Partial<Step>) {
    if (!activeGuide) return;

    updateGuide({
      steps: activeGuide.steps.map((step) =>
        step.id === stepId ? { ...step, ...changes } : step,
      ),
    });
  }

  function addStep() {
    if (!activeGuide) return;

    updateGuide({
      steps: [
        ...activeGuide.steps,
        {
          id: createId("step"),
          title: `Step ${activeGuide.steps.length + 1}`,
          description: "Explain what happens during this step.",
        },
      ],
    });
  }

  function removeStep(stepId: string) {
    if (!activeGuide) return;

    updateGuide({
      steps: activeGuide.steps.filter((step) => step.id !== stepId),
    });
  }

  function deleteGuide() {
    if (!activeGuide) return;

    const confirmed = window.confirm(
      `Delete "${activeGuide.title}" permanently?`,
    );

    if (!confirmed) return;

    setGuides((current) =>
      current.filter((guide) => guide.id !== activeGuide.id),
    );

    setActiveGuideId(null);
    setScreen("dashboard");
  }

  async function copyLink() {
    if (!activeGuide) return;

    const url = `${window.location.origin}/?guide=${activeGuide.id}`;

    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      window.prompt("Copy this guide link:", url);
    }
  }

  if (screen === "landing") {
    return (
      <main>
        <header className="topbar">
          <Logo />

          <nav>
            <a href="#features">Features</a>
            <a href="#how">How it works</a>
          </nav>

          <button
            className="button buttonDark"
            onClick={() => setScreen("dashboard")}
          >
            Get started
          </button>
        </header>

        <section className="hero">
          <div className="heroText">
            <span className="eyebrow">
              <Sparkles size={15} />
              Workflow documentation
            </span>

            <h1>Turn every process into a clear guide.</h1>

            <p>
              Zivora helps teams create, edit and share beautiful step-by-step
              instructions for every repeatable workflow.
            </p>

            <div className="heroButtons">
              <button
                className="button buttonPurple"
                onClick={() => setScreen("dashboard")}
              >
                Create your first guide
                <ArrowRight size={18} />
              </button>

              <a className="button buttonLight" href="#features">
                Explore features
              </a>
            </div>
          </div>

          <div className="preview">
            <div className="browserDots">
              <span />
              <span />
              <span />
            </div>

            <div className="previewHeading" />

            {[1, 2, 3, 4].map((number) => (
              <div className="previewStep" key={number}>
                <div className="previewNumber">{number}</div>

                <div className="previewLines">
                  <div />
                  <div />
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="section" id="features">
          <div className="sectionHeading">
            <span className="eyebrow">Core features</span>
            <h2>Documentation without the busywork</h2>
            <p>
              Create useful process guides that are simple to maintain and
              share.
            </p>
          </div>

          <div className="featureGrid">
            <article className="featureCard">
              <MousePointerClick size={30} />
              <h3>Create workflows</h3>
              <p>
                Build structured guides with clear and editable instructions.
              </p>
            </article>

            <article className="featureCard">
              <FileText size={30} />
              <h3>Edit everything</h3>
              <p>
                Update titles, descriptions and workflow steps whenever needed.
              </p>
            </article>

            <article className="featureCard">
              <Share2 size={30} />
              <h3>Publish and share</h3>
              <p>
                Make finished guides available to colleagues and customers.
              </p>
            </article>
          </div>
        </section>

        <section className="section sectionGrey" id="how">
          <div className="sectionHeading">
            <span className="eyebrow">How it works</span>
            <h2>Create. Refine. Share.</h2>
          </div>

          <div className="processGrid">
            <article>
              <b>01</b>
              <h3>Create a guide</h3>
              <p>Name the process you want to document.</p>
            </article>

            <article>
              <b>02</b>
              <h3>Add the steps</h3>
              <p>Explain every action clearly and concisely.</p>
            </article>

            <article>
              <b>03</b>
              <h3>Publish it</h3>
              <p>Share the completed guide with your team.</p>
            </article>
          </div>
        </section>
      </main>
    );
  }

  if (screen === "editor" && activeGuide) {
    return (
      <div className="app">
        <aside className="sidebar">
          <Logo />

          <button
            className="sidebarButton"
            onClick={() => setScreen("dashboard")}
          >
            <ChevronLeft size={18} />
            Back to dashboard
          </button>

          <div className="sidebarFooter">
            <strong>Zivora Phase 1</strong>
            <small>Manual guide creation</small>
          </div>
        </aside>

        <main className="workspace">
          <header className="workspaceHeader">
            <button
              className="button buttonLight"
              onClick={() => setScreen("dashboard")}
            >
              <ChevronLeft size={17} />
              Dashboard
            </button>

            <div className="headerActions">
              <button className="button buttonLight" onClick={copyLink}>
                {copied ? <Check size={17} /> : <Share2 size={17} />}
                {copied ? "Copied" : "Copy link"}
              </button>

              <button
                className="button buttonPurple"
                onClick={() =>
                  updateGuide({
                    status:
                      activeGuide.status === "draft" ? "published" : "draft",
                  })
                }
              >
                {activeGuide.status === "draft" ? "Publish" : "Unpublish"}
              </button>
            </div>
          </header>

          <div className="editor">
            <section className="guideHeaderCard">
              <div className="guideHeaderTop">
                <span className={`status ${activeGuide.status}`}>
                  {activeGuide.status}
                </span>

                <button className="iconButton danger" onClick={deleteGuide}>
                  <Trash2 size={18} />
                </button>
              </div>

              <input
                className="guideTitleInput"
                value={activeGuide.title}
                onChange={(event) =>
                  updateGuide({ title: event.target.value })
                }
              />

              <textarea
                className="guideDescriptionInput"
                value={activeGuide.description}
                onChange={(event) =>
                  updateGuide({ description: event.target.value })
                }
              />
            </section>

            <div className="steps">
              {activeGuide.steps.map((step, index) => (
                <article className="stepCard" key={step.id}>
                  <div className="stepNumber">{index + 1}</div>

                  <div className="stepContent">
                    <input
                      value={step.title}
                      onChange={(event) =>
                        updateStep(step.id, {
                          title: event.target.value,
                        })
                      }
                    />

                    <textarea
                      value={step.description}
                      onChange={(event) =>
                        updateStep(step.id, {
                          description: event.target.value,
                        })
                      }
                    />

                    <div className="screenshotPlaceholder">
                      Screenshots captured by the Phase 2 browser recorder will
                      appear here.
                    </div>
                  </div>

                  <button
                    className="iconButton"
                    onClick={() => removeStep(step.id)}
                    aria-label="Remove step"
                  >
                    <Trash2 size={17} />
                  </button>
                </article>
              ))}
            </div>

            <button className="addStepButton" onClick={addStep}>
              <Plus size={19} />
              Add another step
            </button>
          </div>
        </main>
      </div>
    );
  }

  return (
    <div className="app">
      <aside className="sidebar">
        <Logo />

        <div className="workspaceName">
          <strong>Personal workspace</strong>
          <small>Octopus Production</small>
        </div>

        <nav className="sidebarNav">
          <button className="sidebarButton active">
            <HomeIcon size={18} />
            Home
          </button>

          <button className="sidebarButton">
            <BookOpen size={18} />
            My guides
          </button>
        </nav>

        <div className="sidebarFooter">
          <button
            className="sidebarButton"
            onClick={() => setScreen("landing")}
          >
            <ChevronLeft size={18} />
            Back to website
          </button>
        </div>
      </aside>

      <main className="workspace">
        <header className="workspaceHeader">
          <div>
            <span className="eyebrow">Workspace</span>
            <h2>My guides</h2>
          </div>

          <button
            className="button buttonPurple"
            onClick={() => setCreateModal(true)}
          >
            <Plus size={18} />
            New guide
          </button>
        </header>

        <div className="dashboard">
          <section className="recorderBanner">
            <div>
              <span className="bannerLabel">
                <Sparkles size={16} />
                Zivora recorder
              </span>

              <h2>Capture your next workflow</h2>

              <p>
                Manual guide creation is available now. Browser recording,
                automatic screenshots and click capture will arrive in Phase 2.
              </p>
            </div>

            <button
              className="button buttonWhite"
              onClick={() => setCreateModal(true)}
            >
              Start creating
            </button>
          </section>

          <div className="toolbar">
            <label className="searchBox">
              <Search size={18} />

              <input
                placeholder="Search guides"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
              />
            </label>

            <span>
              {filteredGuides.length}{" "}
              {filteredGuides.length === 1 ? "guide" : "guides"}
            </span>
          </div>

          <div className="guideGrid">
            {filteredGuides.map((guide) => (
              <button
                className="guideCard"
                key={guide.id}
                onClick={() => openGuide(guide.id)}
              >
                <div className="guideThumbnail">
                  <MousePointerClick size={38} />
                </div>

                <div className="guideBody">
                  <span className={`status ${guide.status}`}>
                    {guide.status}
                  </span>

                  <h3>{guide.title}</h3>
                  <p>{guide.description}</p>

                  <div className="guideMeta">
                    <span>{guide.steps.length} steps</span>
                    <span>
                      {new Date(guide.updatedAt).toLocaleDateString()}
                    </span>
                  </div>
                </div>
              </button>
            ))}

            {filteredGuides.length === 0 && (
              <div className="emptyState">
                <BookOpen size={40} />
                <h3>No guides found</h3>
                <p>Try another search or create a new guide.</p>
              </div>
            )}
          </div>
        </div>
      </main>

      {createModal && (
        <div className="modalBackground">
          <div className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">New guide</span>
                <h2>What will you document?</h2>
              </div>

              <button
                className="iconButton"
                onClick={() => setCreateModal(false)}
              >
                <X size={19} />
              </button>
            </div>

            <label>
              Guide title
              <input
                autoFocus
                placeholder="How to create a GitHub repository"
                value={newTitle}
                onChange={(event) => setNewTitle(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") createGuide();
                }}
              />
            </label>

            <label>
              Description
              <textarea
                placeholder="What will the reader learn?"
                value={newDescription}
                onChange={(event) => setNewDescription(event.target.value)}
              />
            </label>

            <div className="modalActions">
              <button
                className="button buttonLight"
                onClick={() => setCreateModal(false)}
              >
                Cancel
              </button>

              <button className="button buttonPurple" onClick={createGuide}>
                Create guide
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
