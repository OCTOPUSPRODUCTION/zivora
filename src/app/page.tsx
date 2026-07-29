"use client";

import {
  ArrowRight,
  BookOpen,
  Check,
  ChevronDown,
  ChevronLeft,
  FileText,
  Home as HomeIcon,
  Menu,
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
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
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
      <main className="marketingPage">
        <header className="professionalNavbar">
          <div className="navbarInner">
            <button
              className="brandButton"
              onClick={() => window.scrollTo({ top: 0, behavior: "smooth" })}
              aria-label="Go to Zivora homepage"
            >
              <Logo />
            </button>

            <nav className="desktopNavigation" aria-label="Main navigation">
              <div className="navDropdown">
                <button className="navLink">
                  Product
                  <ChevronDown size={15} />
                </button>

                <div className="dropdownPanel">
                  <a href="#product">
                    <span className="dropdownIcon">
                      <MousePointerClick size={19} />
                    </span>
                    <span>
                      <strong>Workflow guides</strong>
                      <small>Create clear step-by-step documentation.</small>
                    </span>
                  </a>

                  <a href="#product">
                    <span className="dropdownIcon">
                      <FileText size={19} />
                    </span>
                    <span>
                      <strong>Guide editor</strong>
                      <small>Edit, organise and publish every process.</small>
                    </span>
                  </a>

                  <a href="#product">
                    <span className="dropdownIcon">
                      <Share2 size={19} />
                    </span>
                    <span>
                      <strong>Team sharing</strong>
                      <small>Keep important knowledge accessible.</small>
                    </span>
                  </a>
                </div>
              </div>

              <div className="navDropdown">
                <button className="navLink">
                  Solutions
                  <ChevronDown size={15} />
                </button>

                <div className="dropdownPanel compactDropdown">
                  <a href="#solutions">
                    <span>
                      <strong>Standard operating procedures</strong>
                      <small>Document repeatable business processes.</small>
                    </span>
                  </a>

                  <a href="#solutions">
                    <span>
                      <strong>Employee onboarding</strong>
                      <small>Help new team members become productive.</small>
                    </span>
                  </a>

                  <a href="#solutions">
                    <span>
                      <strong>Customer support</strong>
                      <small>Turn common answers into reusable guides.</small>
                    </span>
                  </a>
                </div>
              </div>

              <a className="navLink" href="#customers">
                Customers
              </a>

              <div className="navDropdown">
                <button className="navLink">
                  Resources
                  <ChevronDown size={15} />
                </button>

                <div className="dropdownPanel compactDropdown">
                  <a href="#how">
                    <span>
                      <strong>How Zivora works</strong>
                      <small>See the complete documentation workflow.</small>
                    </span>
                  </a>

                  <a href="#resources">
                    <span>
                      <strong>Documentation guides</strong>
                      <small>Learn how to create better processes.</small>
                    </span>
                  </a>

                  <a href="#resources">
                    <span>
                      <strong>Best practices</strong>
                      <small>Build documentation people will use.</small>
                    </span>
                  </a>
                </div>
              </div>

              <a className="navLink" href="#about">
                About
              </a>
            </nav>

            <div className="navbarActions">
              <button
                className="signInButton"
                onClick={() => setScreen("dashboard")}
              >
                Sign in
              </button>

              <button
                className="navbarPrimaryButton"
                onClick={() => setScreen("dashboard")}
              >
                Get started
                <ArrowRight size={17} />
              </button>

              <button
                className="mobileMenuButton"
                onClick={() => setMobileMenuOpen((current) => !current)}
                aria-label="Open navigation menu"
              >
                {mobileMenuOpen ? <X size={22} /> : <Menu size={22} />}
              </button>
            </div>
          </div>

          {mobileMenuOpen && (
            <div className="mobileNavigation">
              <a href="#product" onClick={() => setMobileMenuOpen(false)}>
                Product
              </a>
              <a href="#solutions" onClick={() => setMobileMenuOpen(false)}>
                Solutions
              </a>
              <a href="#customers" onClick={() => setMobileMenuOpen(false)}>
                Customers
              </a>
              <a href="#resources" onClick={() => setMobileMenuOpen(false)}>
                Resources
              </a>
              <a href="#about" onClick={() => setMobileMenuOpen(false)}>
                About
              </a>

              <div className="mobileNavigationActions">
                <button
                  className="button buttonLight"
                  onClick={() => {
                    setMobileMenuOpen(false);
                    setScreen("dashboard");
                  }}
                >
                  Sign in
                </button>

                <button
                  className="button buttonPurple"
                  onClick={() => {
                    setMobileMenuOpen(false);
                    setScreen("dashboard");
                  }}
                >
                  Get started
                </button>
              </div>
            </div>
          )}
        </header>

        <section className="professionalHero">
          <div className="heroBackgroundGrid" />

          <div className="heroGlow heroGlowOne" />
          <div className="heroGlow heroGlowTwo" />

          <div className="professionalHeroInner">
            <div className="professionalHeroCopy">
              <span className="heroAnnouncement">
                <span className="announcementDot" />
                A smarter way to document how work gets done
                <ArrowRight size={15} />
              </span>

              <h1>
                Turn everyday work into
                <span> knowledge everyone can use.</span>
              </h1>

              <p>
                Zivora helps teams capture important workflows, create clear
                step-by-step guides and keep knowledge accessible across the
                organisation.
              </p>

              <div className="professionalHeroButtons">
                <button
                  className="heroPrimaryButton"
                  onClick={() => setScreen("dashboard")}
                >
                  Start creating for free
                  <ArrowRight size={18} />
                </button>

                <button
                  className="heroSecondaryButton"
                  onClick={() =>
                    document
                      .getElementById("product")
                      ?.scrollIntoView({ behavior: "smooth" })
                  }
                >
                  <span className="playButton">
                    <MousePointerClick size={17} />
                  </span>
                  See how it works
                </button>
              </div>

              <div className="heroTrustPoints">
                <span>
                  <Check size={16} />
                  No credit card
                </span>

                <span>
                  <Check size={16} />
                  Create guides in minutes
                </span>

                <span>
                  <Check size={16} />
                  Built for modern teams
                </span>
              </div>
            </div>

            <div className="productShowcase">
              <div className="showcaseDecoration showcaseDecorationOne" />
              <div className="showcaseDecoration showcaseDecorationTwo" />

              <div className="productWindow">
                <div className="productWindowHeader">
                  <div className="windowControls">
                    <span />
                    <span />
                    <span />
                  </div>

                  <div className="windowAddress">
                    <span className="addressLock">Z</span>
                    app.zivora.com/guides
                  </div>

                  <div className="windowUser">VA</div>
                </div>

                <div className="productWindowBody">
                  <aside className="showcaseSidebar">
                    <div className="miniLogo">Z</div>

                    <div className="miniSidebarItem active">
                      <HomeIcon size={15} />
                    </div>

                    <div className="miniSidebarItem">
                      <BookOpen size={15} />
                    </div>

                    <div className="miniSidebarItem">
                      <FileText size={15} />
                    </div>
                  </aside>

                  <div className="showcaseContent">
                    <div className="showcaseTopline">
                      <div>
                        <small>Workspace</small>
                        <h3>Customer onboarding</h3>
                      </div>

                      <button>
                        <Plus size={14} />
                        New guide
                      </button>
                    </div>

                    <div className="showcaseGuide">
                      <div className="showcaseGuideHeader">
                        <span className="publishedPill">Published</span>
                        <div className="showcaseGuideActions">
                          <span />
                          <span />
                          <span />
                        </div>
                      </div>

                      <h4>How to invite a new team member</h4>

                      <p>
                        Follow these steps to add a colleague to your workspace.
                      </p>

                      <div className="showcaseSteps">
                        <div className="showcaseStep">
                          <span>1</span>
                          <div>
                            <strong>Open workspace settings</strong>
                            <small>
                              Select Settings from the navigation menu.
                            </small>
                          </div>
                        </div>

                        <div className="showcaseStep selected">
                          <span>2</span>
                          <div>
                            <strong>Choose team members</strong>
                            <small>
                              Open the Members tab and select Invite.
                            </small>
                          </div>
                        </div>

                        <div className="showcaseStep">
                          <span>3</span>
                          <div>
                            <strong>Send the invitation</strong>
                            <small>
                              Enter their email address and confirm.
                            </small>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div className="floatingCaptureCard">
                <div className="captureIcon">
                  <Sparkles size={18} />
                </div>

                <div>
                  <strong>Guide created</strong>
                  <small>3 steps captured automatically</small>
                </div>

                <Check size={18} />
              </div>
            </div>
          </div>
        </section>

        <section className="customerStrip" id="customers">
          <p>Designed for teams that care about clear, reliable knowledge</p>

          <div className="customerNames">
            <span>Northstar</span>
            <span>Octopus</span>
            <span>Vertex</span>
            <span>Cloudline</span>
            <span>Everfield</span>
            <span>BrightLabs</span>
          </div>
        </section>

        <section className="professionalSection" id="solutions">
          <div className="professionalSectionHeading">
            <span className="sectionLabel">Built for every workflow</span>

            <h2>How will your team use Zivora?</h2>

            <p>
              Create one reliable source of knowledge for every process your
              team repeats.
            </p>
          </div>

          <div className="useCaseGrid">
            <article className="useCaseCard coral">
              <div className="useCaseIcon">
                <FileText size={24} />
              </div>

              <h3>Create SOPs</h3>

              <p>
                Turn repeatable business processes into consistent,
                easy-to-follow standard operating procedures.
              </p>

              <a href="#product">
                Explore SOPs
                <ArrowRight size={16} />
              </a>
            </article>

            <article className="useCaseCard yellow">
              <div className="useCaseIcon">
                <Sparkles size={24} />
              </div>

              <h3>Train your team</h3>

              <p>
                Give employees practical guides that help them learn tools,
                systems and responsibilities faster.
              </p>

              <a href="#product">
                Explore training
                <ArrowRight size={16} />
              </a>
            </article>

            <article className="useCaseCard green">
              <div className="useCaseIcon">
                <BookOpen size={24} />
              </div>

              <h3>Build a knowledge base</h3>

              <p>
                Keep important company knowledge organised, searchable and
                accessible whenever it is needed.
              </p>

              <a href="#product">
                Explore knowledge
                <ArrowRight size={16} />
              </a>
            </article>

            <article className="useCaseCard blue">
              <div className="useCaseIcon">
                <MousePointerClick size={24} />
              </div>

              <h3>Onboard new hires</h3>

              <p>
                Help new team members understand processes without relying on
                repeated meetings and explanations.
              </p>

              <a href="#product">
                Explore onboarding
                <ArrowRight size={16} />
              </a>
            </article>
          </div>
        </section>

        <section className="productExperienceSection" id="product">
          <div className="productExperienceInner">
            <div className="productExperienceCopy">
              <span className="sectionLabel">A better documentation process</span>

              <h2>From an undocumented task to a useful guide.</h2>

              <p>
                Zivora gives your team a simple place to create, refine,
                organise and share operational knowledge.
              </p>

              <div className="featureList">
                <div>
                  <span>
                    <Check size={17} />
                  </span>

                  <div>
                    <strong>Create structured workflow guides</strong>
                    <p>
                      Break every process into clear and understandable steps.
                    </p>
                  </div>
                </div>

                <div>
                  <span>
                    <Check size={17} />
                  </span>

                  <div>
                    <strong>Edit and improve at any time</strong>
                    <p>
                      Keep documentation accurate as tools and processes change.
                    </p>
                  </div>
                </div>

                <div>
                  <span>
                    <Check size={17} />
                  </span>

                  <div>
                    <strong>Share knowledge across your organisation</strong>
                    <p>
                      Give people a reliable place to find the answers they
                      need.
                    </p>
                  </div>
                </div>
              </div>

              <button
                className="heroPrimaryButton"
                onClick={() => setScreen("dashboard")}
              >
                Explore your workspace
                <ArrowRight size={18} />
              </button>
            </div>

            <div className="workflowVisual">
              <div className="workflowVisualHeader">
                <span className="workflowStatus">
                  <span />
                  Recording workflow
                </span>

                <span className="workflowTimer">00:24</span>
              </div>

              <div className="workflowBrowser">
                <div className="workflowBrowserTop">
                  <div>
                    <span />
                    <span />
                    <span />
                  </div>

                  <div className="workflowUrl">workspace.example.com</div>
                </div>

                <div className="workflowPage">
                  <div className="workflowFakeSidebar">
                    <span />
                    <span />
                    <span />
                    <span />
                  </div>

                  <div className="workflowFakeContent">
                    <div className="fakePageTitle" />

                    <div className="fakeForm">
                      <div />
                      <div />
                      <button>Invite member</button>
                    </div>

                    <div className="clickIndicator">
                      <MousePointerClick size={20} />
                    </div>
                  </div>
                </div>
              </div>

              <div className="workflowCompleteCard">
                <span>
                  <Check size={17} />
                </span>

                <div>
                  <strong>Step captured</strong>
                  <small>Click “Invite member”</small>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section className="howSection" id="how">
          <div className="professionalSectionHeading">
            <span className="sectionLabel">Simple from start to finish</span>
            <h2>Document a process in three steps.</h2>
          </div>

          <div className="howGrid">
            <article>
              <span className="howNumber">01</span>
              <div className="howIcon">
                <MousePointerClick size={25} />
              </div>
              <h3>Capture the workflow</h3>
              <p>
                Start with a process your team performs regularly.
              </p>
            </article>

            <article>
              <span className="howNumber">02</span>
              <div className="howIcon">
                <FileText size={25} />
              </div>
              <h3>Refine the guide</h3>
              <p>
                Add context, improve the instructions and organise each step.
              </p>
            </article>

            <article>
              <span className="howNumber">03</span>
              <div className="howIcon">
                <Share2 size={25} />
              </div>
              <h3>Share the knowledge</h3>
              <p>
                Publish the finished guide and make it available to your team.
              </p>
            </article>
          </div>
        </section>

        <section className="resourcesSection" id="resources">
          <div className="resourcesContent">
            <div>
              <span className="sectionLabel">Documentation that stays useful</span>

              <h2>
                Give your team the clarity to do their best work.
              </h2>

              <p>
                Stop important processes from living inside messages, meetings
                and individual memory.
              </p>
            </div>

            <button
              className="resourcesButton"
              onClick={() => setScreen("dashboard")}
            >
              Build your first guide
              <ArrowRight size={18} />
            </button>
          </div>
        </section>

        <footer className="professionalFooter" id="about">
          <div className="footerTop">
            <div className="footerBrand">
              <Logo />

              <p>
                Clear process documentation for teams that want to work
                smarter.
              </p>
            </div>

            <div className="footerLinks">
              <div>
                <strong>Product</strong>
                <a href="#product">Workflow guides</a>
                <a href="#product">Guide editor</a>
                <a href="#product">Sharing</a>
              </div>

              <div>
                <strong>Solutions</strong>
                <a href="#solutions">SOPs</a>
                <a href="#solutions">Onboarding</a>
                <a href="#solutions">Training</a>
              </div>

              <div>
                <strong>Company</strong>
                <a href="#about">About</a>
                <a href="#resources">Resources</a>
                <a href="#customers">Customers</a>
              </div>
            </div>
          </div>

          <div className="footerBottom">
            <span>© {new Date().getFullYear()} Zivora</span>
            <span>Built by Octopus Production</span>
          </div>
        </footer>
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
