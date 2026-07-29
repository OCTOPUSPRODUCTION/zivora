function safeEscape(value) {
  if (window.CSS && typeof window.CSS.escape === "function") {
    return window.CSS.escape(value);
  }
  return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
}

function getSelector(element) {
  if (!(element instanceof Element)) return "";

  if (element.id) {
    return `#${safeEscape(element.id)}`;
  }

  const parts = [];
  let current = element;

  while (
    current &&
    current !== document.body &&
    parts.length < 5
  ) {
    let part = current.tagName.toLowerCase();

    if (current.classList.length > 0) {
      part +=
        "." +
        Array.from(current.classList)
          .slice(0, 2)
          .map(safeEscape)
          .join(".");
    }

    const parent = current.parentElement;

    if (parent) {
      const siblings = Array.from(parent.children).filter(
        (child) => child.tagName === current.tagName
      );

      if (siblings.length > 1) {
        part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
      }
    }

    parts.unshift(part);
    current = current.parentElement;
  }

  return parts.join(" > ");
}

function cleanText(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 220);
}

function getElementLabel(element) {
  const ariaLabel =
    element.getAttribute("aria-label");

  const title =
    element.getAttribute("title");

  const placeholder =
    element.getAttribute("placeholder");

  if (ariaLabel) {
    return cleanText(ariaLabel);
  }

  if (title) {
    return cleanText(title);
  }

  if (placeholder) {
    return cleanText(placeholder);
  }

  const heading = element.querySelector(
    "h1, h2, h3, h4, [role='heading']"
  );

  if (heading?.textContent) {
    return cleanText(heading.textContent);
  }

  const headingParent = element.closest(
    "div, article, section"
  )?.querySelector(
    "h1, h2, h3, h4, [role='heading']"
  );

  if (headingParent?.textContent) {
    return cleanText(
      headingParent.textContent
    );
  }

  const directText = Array.from(
    element.childNodes
  )
    .filter(
      (node) =>
        node.nodeType === Node.TEXT_NODE
    )
    .map((node) =>
      cleanText(node.textContent)
    )
    .filter(Boolean);

  if (directText.length > 0) {
    return directText[0];
  }

  return cleanText(
    element.innerText ||
      element.textContent ||
      element.getAttribute("name") ||
      element.tagName.toLowerCase()
  );
}

function getElementRole(element) {
  const explicitRole = element.getAttribute("role");
  if (explicitRole) return explicitRole;

  const tag = element.tagName.toLowerCase();
  const type = element.getAttribute("type");

  if (tag === "a") return "link";
  if (tag === "button") return "button";
  if (tag === "input" && type === "search") return "search box";
  if (tag === "input") return "input";
  if (tag === "select") return "dropdown";
  if (tag === "textarea") return "text area";

  return tag;
}

function rectToPlain(rect) {
  return {
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height
  };
}

function isSensitiveElement(element) {
  if (!(element instanceof Element)) return false;

  const text = [
    element.getAttribute("name"),
    element.getAttribute("id"),
    element.getAttribute("autocomplete"),
    element.getAttribute("aria-label"),
    element.getAttribute("placeholder"),
    element.getAttribute("type")
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return (
    element instanceof HTMLInputElement &&
    element.type === "password"
  ) || /password|passwd|secret|token|api[-_ ]?key|access[-_ ]?key|auth|credit|card|cvv|cvc|account[-_ ]?id|email/.test(text);
}

function findSensitiveRects() {
  const candidates = Array.from(
    document.querySelectorAll(
      "input, textarea, [contenteditable='true'], [data-token], [data-secret]"
    )
  );

  return candidates
    .filter(isSensitiveElement)
    .map((element) => rectToPlain(element.getBoundingClientRect()))
    .filter(
      (rect) =>
        rect.width > 0 &&
        rect.height > 0 &&
        rect.x < window.innerWidth &&
        rect.y < window.innerHeight &&
        rect.x + rect.width > 0 &&
        rect.y + rect.height > 0
    );
}

function detectSensitiveTextRects() {
  const emailPattern =
    /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i;

  const tokenPattern =
    /\b(?:sk-|sb_|ghp_|github_pat_|AIza|eyJ)[A-Za-z0-9_\-.]{8,}\b/;

  const rects = [];

  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_TEXT
  );

  let node;

  while ((node = walker.nextNode())) {
    const text = cleanText(node.textContent);
    if (!text || (!emailPattern.test(text) && !tokenPattern.test(text))) {
      continue;
    }

    const parent = node.parentElement;
    if (!parent) continue;

    const rect = parent.getBoundingClientRect();

    if (
      rect.width > 0 &&
      rect.height > 0 &&
      rect.x < window.innerWidth &&
      rect.y < window.innerHeight
    ) {
      rects.push(rectToPlain(rect));
    }

    if (rects.length >= 20) break;
  }

  return rects;
}

document.addEventListener(
  "click",
  async (event) => {
    const rawTarget =
      event.target instanceof Element ? event.target : null;

    if (!rawTarget) return;

    const target =
      rawTarget.closest(
        "button, a, input, select, textarea, [role='button'], [role='link'], [tabindex]"
      ) || rawTarget;

    const rect = target.getBoundingClientRect();

    if (rect.width <= 0 || rect.height <= 0) return;

    try {
      await chrome.runtime.sendMessage({
        type: "CAPTURE_CLICK",
        payload: {
          pageUrl: window.location.href,
          pageTitle: document.title,
          hostname: window.location.hostname,
          elementText: getElementLabel(target),
          elementRole: getElementRole(target),
          tagName: target.tagName.toLowerCase(),
          selector: getSelector(target),
          ariaLabel: target.getAttribute("aria-label") || "",
          placeholder: target.getAttribute("placeholder") || "",
          rect: rectToPlain(rect),
          viewport: {
            width: window.innerWidth,
            height: window.innerHeight,
            devicePixelRatio: window.devicePixelRatio || 1
          },
          sensitiveRects: [
            ...findSensitiveRects(),
            ...detectSensitiveTextRects()
          ]
        }
      });
    } catch {
      // Extension reloads can temporarily invalidate the channel.
    }
  },
  true
);
