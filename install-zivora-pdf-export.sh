#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Creating backups..."

cp "src/app/guides/[id]/edit/page.tsx" \
   "src/app/guides/[id]/edit/page.tsx.before-pdf-export"

mkdir -p "src/app/guides/[id]/print"

cat > "src/app/guides/[id]/print/page.tsx" <<'EOF'
"use client";

import {
  ArrowLeft,
  Download,
  Loader2,
  Printer
} from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
  useEffect,
  useRef,
  useState
} from "react";

import { createClient } from "@/lib/supabase/client";
import type { Guide, Step } from "@/lib/types";

function createSafeFileName(title: string) {
  const safeTitle = title
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);

  return `${safeTitle || "zivora-guide"}.pdf`;
}

export default function GuidePrintPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const guideId = params.id;

  const printedRef = useRef(false);

  const [guide, setGuide] =
    useState<Guide | null>(null);

  const [steps, setSteps] =
    useState<Step[]>([]);

  const [loading, setLoading] =
    useState(true);

  const [error, setError] =
    useState("");

  const [imagesReady, setImagesReady] =
    useState(false);

  useEffect(() => {
    void loadGuide();
  }, [guideId]);

  useEffect(() => {
    if (
      !loading &&
      guide &&
      imagesReady &&
      !printedRef.current
    ) {
      printedRef.current = true;

      document.title = createSafeFileName(
        guide.title
      ).replace(/\.pdf$/, "");

      const timer = window.setTimeout(() => {
        window.print();
      }, 500);

      return () => {
        window.clearTimeout(timer);
      };
    }
  }, [
    loading,
    guide,
    imagesReady
  ]);

  async function loadGuide() {
    setLoading(true);
    setError("");

    try {
      const supabase = createClient();

      const {
        data: { user },
        error: userError
      } = await supabase.auth.getUser();

      if (userError || !user) {
        router.replace("/login");
        return;
      }

      const {
        data: guideData,
        error: guideError
      } = await supabase
        .from("guides")
        .select("*")
        .eq("id", guideId)
        .single();

      if (guideError || !guideData) {
        throw (
          guideError ||
          new Error("Guide not found.")
        );
      }

      const {
        data: stepData,
        error: stepError
      } = await supabase
        .from("steps")
        .select("*")
        .eq("guide_id", guideId)
        .order("position", {
          ascending: true
        });

      if (stepError) {
        throw stepError;
      }

      const loadedSteps =
        (stepData ?? []) as Step[];

      setGuide(guideData as Guide);
      setSteps(loadedSteps);

      await waitForImages(loadedSteps);

      setImagesReady(true);
    } catch (caughtError) {
      console.error(caughtError);

      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not prepare the PDF."
      );
    } finally {
      setLoading(false);
    }
  }

  async function waitForImages(
    loadedSteps: Step[]
  ) {
    const imageUrls = loadedSteps
      .map((step) => step.image_url)
      .filter(
        (url): url is string =>
          typeof url === "string" &&
          url.length > 0
      );

    await Promise.all(
      imageUrls.map(
        (url) =>
          new Promise<void>((resolve) => {
            const image = new Image();

            image.onload = () => resolve();
            image.onerror = () => resolve();
            image.src = url;

            if (image.complete) {
              resolve();
            }
          })
      )
    );
  }

  function printGuide() {
    if (!guide) return;

    document.title = createSafeFileName(
      guide.title
    ).replace(/\.pdf$/, "");

    window.print();
  }

  if (loading) {
    return (
      <main className="pdfLoading">
        <Loader2
          className="pdfSpinner"
          size={30}
        />

        <h1>Preparing your PDF</h1>

        <p>
          Loading the guide and its screenshots…
        </p>

        <PrintStyles />
      </main>
    );
  }

  if (error || !guide) {
    return (
      <main className="pdfLoading">
        <div className="pdfErrorIcon">!</div>

        <h1>PDF preparation failed</h1>

        <p>
          {error ||
            "The guide could not be loaded."}
        </p>

        <Link
          href={`/guides/${guideId}/edit`}
          className="pdfBackLink"
        >
          <ArrowLeft size={17} />
          Return to guide
        </Link>

        <PrintStyles />
      </main>
    );
  }

  return (
    <>
      <header className="pdfToolbar noPrint">
        <Link
          href={`/guides/${guide.id}/edit`}
          className="pdfToolbarButton"
        >
          <ArrowLeft size={17} />
          Back to guide
        </Link>

        <div className="pdfToolbarMessage">
          In the print window, choose
          <strong> Save as PDF</strong>.
        </div>

        <button
          type="button"
          onClick={printGuide}
          className="pdfDownloadButton"
        >
          <Download size={17} />
          Download PDF
        </button>
      </header>

      <main className="pdfPage">
        <section className="pdfDocument">
          <header className="pdfGuideHeader">
            <div className="pdfBrand">
              <span className="pdfLogo">
                Z
              </span>

              <span>Zivora</span>
            </div>

            <p className="pdfLabel">
              WORKFLOW GUIDE
            </p>

            <h1>{guide.title}</h1>

            {guide.description && (
              <p className="pdfDescription">
                {guide.description}
              </p>
            )}

            <div className="pdfMetadata">
              <span>
                {steps.length}{" "}
                {steps.length === 1
                  ? "step"
                  : "steps"}
              </span>

              <span>
                Generated{" "}
                {new Date().toLocaleDateString(
                  "en-GB",
                  {
                    day: "numeric",
                    month: "long",
                    year: "numeric"
                  }
                )}
              </span>
            </div>
          </header>

          <div className="pdfSteps">
            {steps.length === 0 ? (
              <div className="pdfEmpty">
                This guide contains no steps.
              </div>
            ) : (
              steps.map((step, index) => (
                <article
                  className="pdfStep"
                  key={step.id}
                >
                  <div className="pdfStepHeader">
                    <span className="pdfStepNumber">
                      {index + 1}
                    </span>

                    <h2>{step.title}</h2>
                  </div>

                  {step.description && (
                    <p className="pdfStepDescription">
                      {step.description}
                    </p>
                  )}

                  {step.image_url && (
                    <div className="pdfImageFrame">
                      <img
                        src={step.image_url}
                        alt={step.title}
                      />
                    </div>
                  )}
                </article>
              ))
            )}
          </div>

          <footer className="pdfFooter">
            <div className="pdfBrand">
              <span className="pdfLogo small">
                Z
              </span>

              <span>
                Created with Zivora
              </span>
            </div>
          </footer>
        </section>
      </main>

      <PrintStyles />
    </>
  );
}

function PrintStyles() {
  return (
    <style>{`
      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        background: #f4f4f8;
        color: #18181b;
        font-family:
          Arial,
          Helvetica,
          sans-serif;
      }

      .pdfToolbar {
        position: sticky;
        top: 0;
        z-index: 50;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 18px;
        min-height: 72px;
        padding: 14px 24px;
        border-bottom: 1px solid #e4e4e7;
        background: rgba(255, 255, 255, 0.96);
        backdrop-filter: blur(14px);
      }

      .pdfToolbarButton,
      .pdfDownloadButton {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        min-height: 42px;
        border-radius: 12px;
        padding: 0 16px;
        font-size: 14px;
        font-weight: 700;
        text-decoration: none;
        cursor: pointer;
      }

      .pdfToolbarButton {
        border: 1px solid #e4e4e7;
        background: #ffffff;
        color: #27272a;
      }

      .pdfDownloadButton {
        border: 0;
        background: #6d45f5;
        color: #ffffff;
      }

      .pdfToolbarMessage {
        color: #71717a;
        font-size: 13px;
        text-align: center;
      }

      .pdfPage {
        padding: 42px 20px 70px;
      }

      .pdfDocument {
        width: min(100%, 900px);
        margin: 0 auto;
        overflow: hidden;
        border: 1px solid #e4e4e7;
        border-radius: 24px;
        background: #ffffff;
        box-shadow:
          0 24px 70px
          rgba(24, 24, 27, 0.08);
      }

      .pdfGuideHeader {
        padding: 54px 58px 42px;
        border-bottom: 1px solid #ececf1;
      }

      .pdfBrand {
        display: flex;
        align-items: center;
        gap: 9px;
        font-size: 15px;
        font-weight: 800;
      }

      .pdfLogo {
        display: inline-grid;
        width: 34px;
        height: 34px;
        place-items: center;
        border-radius: 10px;
        background: #6d45f5;
        color: #ffffff;
        font-size: 16px;
        font-weight: 900;
      }

      .pdfLogo.small {
        width: 27px;
        height: 27px;
        border-radius: 8px;
        font-size: 13px;
      }

      .pdfLabel {
        margin: 38px 0 12px;
        color: #6d45f5;
        font-size: 11px;
        font-weight: 900;
        letter-spacing: 0.16em;
      }

      .pdfGuideHeader h1 {
        max-width: 760px;
        margin: 0;
        font-size: 42px;
        line-height: 1.12;
        letter-spacing: -0.04em;
      }

      .pdfDescription {
        max-width: 720px;
        margin: 18px 0 0;
        color: #62626c;
        font-size: 17px;
        line-height: 1.7;
        white-space: pre-wrap;
      }

      .pdfMetadata {
        display: flex;
        flex-wrap: wrap;
        gap: 10px 24px;
        margin-top: 26px;
        color: #8a8a94;
        font-size: 12px;
        font-weight: 700;
      }

      .pdfSteps {
        padding: 38px 58px 48px;
      }

      .pdfStep {
        break-inside: avoid;
        page-break-inside: avoid;
        margin-bottom: 30px;
        padding: 28px;
        border: 1px solid #e7e7ed;
        border-radius: 19px;
        background: #ffffff;
      }

      .pdfStep:last-child {
        margin-bottom: 0;
      }

      .pdfStepHeader {
        display: flex;
        align-items: flex-start;
        gap: 16px;
      }

      .pdfStepNumber {
        display: inline-grid;
        width: 38px;
        height: 38px;
        flex: 0 0 38px;
        place-items: center;
        border-radius: 999px;
        background: #eee9ff;
        color: #6d45f5;
        font-size: 14px;
        font-weight: 900;
      }

      .pdfStep h2 {
        margin: 5px 0 0;
        font-size: 21px;
        line-height: 1.35;
        letter-spacing: -0.02em;
      }

      .pdfStepDescription {
        margin: 17px 0 0 54px;
        color: #555560;
        font-size: 14px;
        line-height: 1.75;
        white-space: pre-wrap;
      }

      .pdfImageFrame {
        margin: 22px 0 0 54px;
        overflow: hidden;
        border: 1px solid #e5e5eb;
        border-radius: 15px;
        background: #f7f7fa;
      }

      .pdfImageFrame img {
        display: block;
        width: 100%;
        max-height: 620px;
        object-fit: contain;
      }

      .pdfFooter {
        padding: 23px 58px;
        border-top: 1px solid #ececf1;
        color: #71717a;
      }

      .pdfEmpty {
        padding: 40px;
        border: 1px dashed #d4d4d8;
        border-radius: 18px;
        color: #71717a;
        text-align: center;
      }

      .pdfLoading {
        display: grid;
        min-height: 100vh;
        place-content: center;
        justify-items: center;
        gap: 12px;
        padding: 24px;
        text-align: center;
      }

      .pdfLoading h1 {
        margin: 4px 0 0;
        font-size: 26px;
      }

      .pdfLoading p {
        max-width: 460px;
        margin: 0;
        color: #71717a;
        line-height: 1.6;
      }

      .pdfSpinner {
        animation: pdfSpin 0.8s linear infinite;
        color: #6d45f5;
      }

      .pdfErrorIcon {
        display: grid;
        width: 58px;
        height: 58px;
        place-items: center;
        border-radius: 18px;
        background: #fee2e2;
        color: #b91c1c;
        font-size: 24px;
        font-weight: 900;
      }

      .pdfBackLink {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        margin-top: 10px;
        border-radius: 12px;
        background: #6d45f5;
        padding: 12px 17px;
        color: #ffffff;
        font-size: 14px;
        font-weight: 800;
        text-decoration: none;
      }

      @keyframes pdfSpin {
        to {
          transform: rotate(360deg);
        }
      }

      @media (max-width: 700px) {
        .pdfToolbar {
          align-items: stretch;
          flex-direction: column;
        }

        .pdfToolbarMessage {
          order: 3;
        }

        .pdfGuideHeader,
        .pdfSteps {
          padding-left: 24px;
          padding-right: 24px;
        }

        .pdfGuideHeader h1 {
          font-size: 34px;
        }

        .pdfStepDescription,
        .pdfImageFrame {
          margin-left: 0;
        }
      }

      @page {
        size: A4;
        margin: 12mm;
      }

      @media print {
        html,
        body {
          background: #ffffff !important;
          print-color-adjust: exact;
          -webkit-print-color-adjust: exact;
        }

        .noPrint {
          display: none !important;
        }

        .pdfPage {
          padding: 0;
        }

        .pdfDocument {
          width: 100%;
          max-width: none;
          overflow: visible;
          border: 0;
          border-radius: 0;
          box-shadow: none;
        }

        .pdfGuideHeader {
          padding:
            8mm
            5mm
            9mm;
        }

        .pdfGuideHeader h1 {
          font-size: 28pt;
        }

        .pdfDescription {
          font-size: 11pt;
        }

        .pdfSteps {
          padding:
            8mm
            5mm;
        }

        .pdfStep {
          margin-bottom: 7mm;
          padding: 6mm;
          border-radius: 4mm;
        }

        .pdfStep h2 {
          font-size: 15pt;
        }

        .pdfStepDescription {
          font-size: 10pt;
        }

        .pdfImageFrame img {
          max-height: 155mm;
        }

        .pdfFooter {
          padding:
            6mm
            5mm;
        }
      }
    `}</style>
  );
}
EOF

python3 <<'PY'
from pathlib import Path

path = Path(
    "src/app/guides/[id]/edit/page.tsx"
)

text = path.read_text()

# Add Download icon import.
old_import = '''  Copy,
  Eye,
  ImagePlus,
'''

new_import = '''  Copy,
  Download,
  Eye,
  ImagePlus,
'''

if old_import in text:
    text = text.replace(
        old_import,
        new_import,
        1
    )
elif "  Download,\n" not in text:
    raise SystemExit(
        "Could not find the Lucide icon import section."
    )

# Add PDF button before publish/copy button.
marker = '''          <button
            className="phaseEditorPrimary"
            disabled={publishing}
            onClick={publishAndCopyLink}
          >'''

pdf_button = '''          <Link
            href={`/guides/${guide.id}/print`}
            target="_blank"
            className="phaseEditorSecondary"
          >
            <Download size={17} />
            Download PDF
          </Link>

'''

if marker not in text:
    raise SystemExit(
        "Could not find the Publish and copy link button."
    )

if "Download PDF" not in text:
    text = text.replace(
        marker,
        pdf_button + marker,
        1
    )

path.write_text(text)

print(
    "PDF route and Download PDF button installed."
)
PY

echo ""
echo "Running production build..."
npm run build

echo ""
echo "============================================"
echo "PDF EXPORT INSTALLED"
echo "============================================"
echo ""
echo "The guide toolbar now contains:"
echo "- Edit guide"
echo "- Publish / Unpublish"
echo "- Download PDF"
echo "- Publish and copy link"
echo ""
echo "Click Download PDF and select:"
echo "Destination -> Save as PDF"
