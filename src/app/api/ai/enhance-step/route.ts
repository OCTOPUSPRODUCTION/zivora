import { NextRequest, NextResponse } from "next/server";

type EnhanceRequest = {
  title?: string;
  action?: string;
  website?: string;
  element?: string;
  elementRole?: string;
  pageTitle?: string;
  pageUrl?: string;
};

type EnhancedStep = {
  title: string;
  action: string;
  element: string;
};

function clean(value: unknown, maximum = 180) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maximum);
}

function localFallback(
  body: EnhanceRequest
): EnhancedStep {
  const element =
    clean(body.element, 100) ||
    clean(body.elementRole, 60) ||
    "highlighted element";

  const website =
    clean(body.website, 80) || "this website";

  return {
    title:
      clean(body.title, 80) ||
      `Click ${element.slice(0, 55)}`,
    action:
      clean(body.action, 220) ||
      `Click the highlighted ${element} on ${website}.`,
    element
  };
}

function parseJsonText(text: string) {
  const cleaned = text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  return JSON.parse(cleaned) as EnhancedStep;
}

export async function POST(request: NextRequest) {
  let body: EnhanceRequest;

  try {
    body = (await request.json()) as EnhanceRequest;
  } catch {
    return NextResponse.json(
      { error: "Invalid request body." },
      { status: 400 }
    );
  }

  const fallback = localFallback(body);
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    return NextResponse.json({
      enhanced: fallback,
      source: "local"
    });
  }

  const model =
    process.env.OPENAI_MODEL || "gpt-5-mini";

  const prompt = {
    task:
      "Rewrite one browser workflow step as concise professional documentation.",
    requirements: [
      "Return only valid JSON.",
      "Use imperative language.",
      "Title must be 2 to 7 words.",
      "Action must be one clear sentence.",
      "Do not include CSS selectors, full URLs, query strings, IDs, tokens, or technical metadata.",
      "Do not invent actions not supported by the input.",
      "Keep element under 80 characters."
    ],
    output_schema: {
      title: "string",
      action: "string",
      element: "string"
    },
    input: {
      current_title: clean(body.title, 120),
      current_action: clean(body.action, 260),
      website: clean(body.website, 100),
      element: clean(body.element, 160),
      role: clean(body.elementRole, 80),
      page_title: clean(body.pageTitle, 160),
      page_url_without_query: clean(
        String(body.pageUrl || "").split("?")[0],
        180
      )
    }
  };

  try {
    const response = await fetch(
      "https://api.openai.com/v1/responses",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model,
          input: JSON.stringify(prompt),
          max_output_tokens: 220
        })
      }
    );

    if (!response.ok) {
      const details = await response.text();
      console.error(
        "OpenAI step enhancement failed:",
        response.status,
        details
      );

      return NextResponse.json({
        enhanced: fallback,
        source: "local"
      });
    }

    const data = await response.json();

    const outputText =
      data.output_text ||
      data.output
        ?.flatMap(
          (item: {
            content?: Array<{
              type?: string;
              text?: string;
            }>;
          }) => item.content || []
        )
        ?.find(
          (item: {
            type?: string;
            text?: string;
          }) => item.type === "output_text"
        )?.text;

    if (!outputText) {
      throw new Error("The model returned no text.");
    }

    const parsed = parseJsonText(outputText);

    const enhanced: EnhancedStep = {
      title:
        clean(parsed.title, 80) ||
        fallback.title,
      action:
        clean(parsed.action, 240) ||
        fallback.action,
      element:
        clean(parsed.element, 100) ||
        fallback.element
    };

    return NextResponse.json({
      enhanced,
      source: "openai"
    });
  } catch (error) {
    console.error(error);

    return NextResponse.json({
      enhanced: fallback,
      source: "local"
    });
  }
}
