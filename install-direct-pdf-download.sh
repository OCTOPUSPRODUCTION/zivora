#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Creating backup..."

mkdir -p "src/app/guides/[id]/print"
mkdir -p "src/types"

if [ -f "src/app/guides/[id]/print/page.tsx" ]; then
  cp "src/app/guides/[id]/print/page.tsx" \
     "src/app/guides/[id]/print/page.tsx.before-direct-pdf"
fi

echo "Installing PDF generator..."

npm install html2pdf.js

cat > "src/types/html2pdf.d.ts" <<'EOF'
declare module "html2pdf.js" {
  type Html2PdfWorker = {
    set(options: Record<string, unknown>): Html2PdfWorker;
    from(element: HTMLElement): Html2PdfWorker;
    toPdf(): Html2PdfWorker;
    get(
      key: string
    ): Promise<{
      internal: {
        getNumberOfPages(): number;
        pageSize: {
          getWidth(): number;
          getHeight(): number;
        };
      };
      setPage(pageNumber: number): void;
      setFontSize(size: number): void;
      setTextColor(
        red: number,
        green: number,
        blue: number
      ): void;
      text(
        text: string,
        x: number,
        y: number,
        options?: {
          align?: "left" | "center" | "right";
        }
      ): void;
    }>;
    save(): Promise<void>;
  };

  type Html2PdfFactory = () => Html2PdfWorker;

  const html2pdf: Html2PdfFactory;

  export default html2pdf;
}
EOF

cat > "src/app/guides/[id]/print/page.tsx" <<'EOF'
"use client";

import {
  ArrowLeft,
  Check,
  Download,
  Loader2
} from "lucide-react";
import Link from "next/link";
import {
  useParams,
  useRouter
} from "next/navigation";
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

export default function GuidePdfPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const guideId = params.id;

  const documentRef =
    useRef<HTMLDivElement | null>(null);

  const [guide, setGuide] =
    useState<Guide | null>(null);

  const [steps, setSteps] =
    useState<Step[]>([]);

  const [loading, setLoading] =
    useState(true);

  const [downloading, setDownloading] =
    useState(false);

  const [downloaded, setDownloaded] =
    useState(false);

  const [error, setError] =
    useState("");

  useEffect(() => {
    void loadGuide();
  }, [guideId]);

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

      setGuide(guideData as Guide);
      setSteps((stepData ?? []) as Step[]);
    } catch (caughtError) {
      console.error(caughtError);

      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not load this guide."
      );
    } finally {
      setLoading(false);
    }
  }

  async function waitForImages(
    container: HTMLElement
  ) {
    const images = Array.from(
      container.querySelectorAll("img")
    );

    await Promise.all(
      images.map(
        (image) =>
          new Promise<void>((resolve) => {
            if (image.complete) {
              resolve();
              return;
            }

            image.onload = () => resolve();
            image.onerror = () => resolve();
          })
      )
    );
  }

  async function downloadPdf() {
    if (
      !guide ||
      !documentRef.current ||
      downloading
    ) {
      return;
    }

    setDownloading(true);
    setDownloaded(false);
    setError("");

    try {
      await waitForImages(
        documentRef.current
      );

      const html2pdfModule =
        await import("html2pdf.js");

      const html2pdf =
        html2pdfModule.default;

      const fileName =
        createSafeFileName(guide.title);

      const worker = html2pdf()
        .set({
          margin: [
            10,
            10,
            16,
            10
          ],
          filename: fileName,
          image: {
            type: "jpeg",
            quality: 0.96
          },
          html2canvas: {
            scale: 2,
            useCORS: true,
            allowTaint: false,
            logging: false,
            backgroundColor: "#ffffff"
          },
          jsPDF: {
            unit: "mm",
            format: "a4",
            orientation: "portrait"
          },
          pagebreak: {
            mode: [
              "css",
              "legacy"
            ],
            avoid: [
              ".zivoraPdfStep",
              ".zivoraPdfHeader"
            ]
          }
        })
        .from(documentRef.current)
        .toPdf();

      const pdf = await worker.get("pdf");

      const totalPages =
        pdf.internal.getNumberOfPages();

      const pageWidth =
        pdf.internal.pageSize.getWidth();

      const pageHeight =
        pdf.internal.pageSize.getHeight();

      for (
        let page = 1;
        page <= totalPages;
        page += 1
      ) {
        pdf.setPage(page);
        pdf.setFontSize(9);
        pdf.setTextColor(
          113,
          113,
          122
        );

        pdf.text(
          `Page ${page} of ${totalPages}`,
          pageWidth - 12,
          pageHeight - 7,
          {
            align: "right"
          }
        );

        pdf.text(
          "Created with Zivora",
          12,
          pageHeight - 7
        );
      }

      await worker.save();

      setDownloaded(true);

      window.setTimeout(() => {
        setDownloaded(false);
      }, 2500);
    } catch (caughtError) {
      console.error(caughtError);

      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not generate the PDF."
      );
    } finally {
      setDownloading(false);
    }
  }

  if (loading) {
    return (
      <main className="zivoraPdfLoading">
        <Loader2
          className="zivoraPdfSpinner"
          size={30}
        />

        <h1>Preparing your guide</h1>

        <p>
          Loading the guide and screenshots…
        </p>

        <PdfStyles />
      </main>
    );
  }

  if (error && !guide) {
    return (
      <main className="zivoraPdfLoading">
        <div className="zivoraPdfErrorIcon">
          !
        </div>

        <h1>Could not prepare PDF</h1>

        <p>{error}</p>

        <Link
          href={`/guides/${guideId}/edit`}
          className="zivoraPdfBackButton"
        >
          <ArrowLeft size={17} />
          Return to guide
        </Link>

        <PdfStyles />
      </main>
    );
  }

  if (!guide) {
    return null;
  }

  return (
    <>
      <header className="zivoraPdfToolbar">
        <Link
          href={`/guides/${guide.id}/edit`}
          className="zivoraPdfToolbarButton"
        >
          <ArrowLeft size={17} />
          Back to guide
        </Link>

        <div className="zivoraPdfToolbarText">
          Download a clean PDF without
          browser links or headers.
        </div>

        <button
          type="button"
          onClick={downloadPdf}
          disabled={downloading}
          className="zivoraPdfDownloadButton"
        >
          {downloading ? (
            <Loader2
              className="zivoraPdfSpinner"
              size={17}
            />
          ) : downloaded ? (
            <Check size={17} />
          ) : (
            <Download size={17} />
          )}

          {downloading
            ? "Generating PDF..."
            : downloaded
              ? "PDF downloaded"
              : "Download PDF"}
        </button>
      </header>

      {error && (
        <div className="zivoraPdfErrorMessage">
          {error}
        </div>
      )}

      <main className="zivoraPdfPreview">
        <div
          ref={documentRef}
          className="zivoraPdfDocument"
        >
          <header className="zivoraPdfHeader">
            <div className="zivoraPdfBrand">
              <span className="zivoraPdfLogo">
                Z
              </span>

              <strong>Zivora</strong>
            </div>

            <p className="zivoraPdfLabel">
              WORKFLOW GUIDE
            </p>

            <h1>{guide.title}</h1>

            {guide.description && (
              <p className="zivoraPdfDescription">
                {guide.description}
              </p>
            )}

            <div className="zivoraPdfMetadata">
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

          <section className="zivoraPdfSteps">
            {steps.length === 0 ? (
              <div className="zivoraPdfEmpty">
                This guide contains no steps.
              </div>
            ) : (
              steps.map((step, index) => (
                <article
                  key={step.id}
                  className="zivoraPdfStep"
                >
                  <div className="zivoraPdfStepHeading">
                    <span className="zivoraPdfStepNumber">
                      {index + 1}
                    </span>

                    <h2>{step.title}</h2>
                  </div>

                  {step.description && (
                    <p className="zivoraPdfStepDescription">
                      {step.description}
                    </p>
                  )}

                  {step.image_url && (
                    <div className="zivoraPdfImageFrame">
                      <img
                        src={step.image_url}
                        alt={step.title}
                        crossOrigin="anonymous"
                      />
                    </div>
                  )}
                </article>
              ))
            )}
          </section>

          <footer className="zivoraPdfDocumentFooter">
            <div className="zivoraPdfBrand">
              <span className="zivoraPdfLogo small">
                Z
              </span>

              <span>
                Created with Zivora
              </span>
            </div>
          </footer>
        </div>
      </main>

      <PdfStyles />
    </>
  );
}

function PdfStyles() {
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

      .zivoraPdfToolbar {
        position: sticky;
        top: 0;
        z-index: 50;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 20px;
        min-height: 72px;
        padding: 14px 24px;
        border-bottom: 1px solid #e4e4e7;
        background: rgba(255, 255, 255, 0.97);
        backdrop-filter: blur(14px);
      }

      .zivoraPdfToolbarButton,
      .zivoraPdfDownloadButton,
      .zivoraPdfBackButton {
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
      }

      .zivoraPdfToolbarButton {
        border: 1px solid #e4e4e7;
        background: #ffffff;
        color: #27272a;
      }

      .zivoraPdfDownloadButton,
      .zivoraPdfBackButton {
        border: 0;
        background: #6d45f5;
        color: #ffffff;
        cursor: pointer;
      }

      .zivoraPdfDownloadButton:disabled {
        cursor: wait;
        opacity: 0.75;
      }

      .zivoraPdfToolbarText {
        color: #71717a;
        font-size: 13px;
        text-align: center;
      }

      .zivoraPdfPreview {
        padding: 42px 20px 70px;
      }

      .zivoraPdfDocument {
        width: 794px;
        max-width: 100%;
        margin: 0 auto;
        overflow: hidden;
        border: 1px solid #e4e4e7;
        border-radius: 22px;
        background: #ffffff;
        box-shadow:
          0 24px 70px
          rgba(24, 24, 27, 0.08);
      }

      .zivoraPdfHeader {
        padding: 52px 54px 40px;
        border-bottom: 1px solid #ececf1;
      }

      .zivoraPdfBrand {
        display: flex;
        align-items: center;
        gap: 9px;
        font-size: 15px;
        font-weight: 800;
      }

      .zivoraPdfLogo {
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

      .zivoraPdfLogo.small {
        width: 27px;
        height: 27px;
        border-radius: 8px;
        font-size: 13px;
      }

      .zivoraPdfLabel {
        margin: 34px 0 12px;
        color: #6d45f5;
        font-size: 11px;
        font-weight: 900;
        letter-spacing: 0.16em;
      }

      .zivoraPdfHeader h1 {
        margin: 0;
        font-size: 40px;
        line-height: 1.13;
        letter-spacing: -0.04em;
      }

      .zivoraPdfDescription {
        margin: 17px 0 0;
        color: #62626c;
        font-size: 16px;
        line-height: 1.7;
        white-space: pre-wrap;
      }

      .zivoraPdfMetadata {
        display: flex;
        flex-wrap: wrap;
        gap: 10px 24px;
        margin-top: 24px;
        color: #8a8a94;
        font-size: 12px;
        font-weight: 700;
      }

      .zivoraPdfSteps {
        padding: 36px 54px 44px;
      }

      .zivoraPdfStep {
        break-inside: avoid;
        page-break-inside: avoid;
        margin-bottom: 28px;
        padding: 26px;
        border: 1px solid #e7e7ed;
        border-radius: 18px;
        background: #ffffff;
      }

      .zivoraPdfStep:last-child {
        margin-bottom: 0;
      }

      .zivoraPdfStepHeading {
        display: flex;
        align-items: flex-start;
        gap: 15px;
      }

      .zivoraPdfStepNumber {
        display: inline-grid;
        width: 37px;
        height: 37px;
        flex: 0 0 37px;
        place-items: center;
        border-radius: 999px;
        background: #eee9ff;
        color: #6d45f5;
        font-size: 14px;
        font-weight: 900;
      }

      .zivoraPdfStep h2 {
        margin: 5px 0 0;
        font-size: 20px;
        line-height: 1.35;
        letter-spacing: -0.02em;
      }

      .zivoraPdfStepDescription {
        margin: 16px 0 0 52px;
        color: #555560;
        font-size: 14px;
        line-height: 1.7;
        white-space: pre-wrap;
      }

      .zivoraPdfImageFrame {
        margin: 21px 0 0 52px;
        overflow: hidden;
        border: 1px solid #e5e5eb;
        border-radius: 14px;
        background: #f7f7fa;
      }

      .zivoraPdfImageFrame img {
        display: block;
        width: 100%;
        max-height: 580px;
        object-fit: contain;
      }

      .zivoraPdfDocumentFooter {
        padding: 22px 54px;
        border-top: 1px solid #ececf1;
        color: #71717a;
      }

      .zivoraPdfEmpty {
        padding: 40px;
        border: 1px dashed #d4d4d8;
        border-radius: 18px;
        color: #71717a;
        text-align: center;
      }

      .zivoraPdfLoading {
        display: grid;
        min-height: 100vh;
        place-content: center;
        justify-items: center;
        gap: 12px;
        padding: 24px;
        text-align: center;
      }

      .zivoraPdfLoading h1 {
        margin: 4px 0 0;
        font-size: 26px;
      }

      .zivoraPdfLoading p {
        max-width: 460px;
        margin: 0;
        color: #71717a;
        line-height: 1.6;
      }

      .zivoraPdfSpinner {
        animation:
          zivoraPdfSpin
          0.8s
          linear
          infinite;
      }

      .zivoraPdfErrorIcon {
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

      .zivoraPdfErrorMessage {
        width: min(720px, calc(100% - 40px));
        margin: 20px auto 0;
        border: 1px solid #fecaca;
        border-radius: 14px;
        background: #fef2f2;
        padding: 14px 16px;
        color: #b91c1c;
        font-size: 14px;
      }

      @keyframes zivoraPdfSpin {
        to {
          transform: rotate(360deg);
        }
      }

      @media (max-width: 720px) {
        .zivoraPdfToolbar {
          align-items: stretch;
          flex-direction: column;
        }

        .zivoraPdfToolbarText {
          order: 3;
        }

        .zivoraPdfHeader,
        .zivoraPdfSteps {
          padding-left: 24px;
          padding-right: 24px;
        }

        .zivoraPdfHeader h1 {
          font-size: 32px;
        }

        .zivoraPdfStepDescription,
        .zivoraPdfImageFrame {
          margin-left: 0;
        }
      }
    `}</style>
  );
}
EOF

echo ""
echo "Running production build..."

npm run build

echo ""
echo "============================================"
echo "DIRECT PDF DOWNLOAD INSTALLED"
echo "============================================"
echo ""
echo "The PDF will now:"
echo "- download directly"
echo "- contain Page X of Y"
echo "- contain no localhost link"
echo "- contain no browser date or title"
echo "- preserve guide steps and screenshots"
