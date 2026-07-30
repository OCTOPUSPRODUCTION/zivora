#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Creating backups..."

cp extension/background.js \
  extension/background.js.before-popup-cleanup

cp extension/popup.js \
  extension/popup.js.before-popup-cleanup

cp extension/popup.html \
  extension/popup.html.before-popup-cleanup

python3 <<'PY'
from pathlib import Path

# ---------------------------------------------------------
# 1. Simplify popup.html
# ---------------------------------------------------------

popup_html_path = Path("extension/popup.html")
popup_html = popup_html_path.read_text()

blocks_to_remove = [
'''      <button id="export" class="secondary" disabled>
        Export recording
      </button>

''',
'''      <button id="openImport" class="secondary">
        Open Zivora importer
      </button>

''',
'''      <button id="clear" class="textButton">
        Clear recording
      </button>

'''
]

for block in blocks_to_remove:
    popup_html = popup_html.replace(block, "")

popup_html_path.write_text(popup_html)

# ---------------------------------------------------------
# 2. Simplify popup.js
# ---------------------------------------------------------

popup_js_path = Path("extension/popup.js")
popup_js = popup_js_path.read_text()

popup_js = popup_js.replace(
'''const exportButton = document.getElementById("export");
const openImportButton =
  document.getElementById("openImport");
const clearButton = document.getElementById("clear");
''',
""
)

popup_js = popup_js.replace(
'''  exportButton.disabled = count === 0;
''',
""
)

export_handler = '''exportButton.addEventListener("click", async () => {
  const response = await sendMessage({
    type: "EXPORT_RECORDING"
  });

  if (!response.success) {
    alert(
      response.error ||
        "Could not export the recording."
    );
  }
});

'''

popup_js = popup_js.replace(export_handler, "")

import_handler = '''openImportButton.addEventListener(
  "click",
  async () => {
    await chrome.tabs.create({
      url: "http://localhost:3000/capture/import"
    });
  }
);

'''

popup_js = popup_js.replace(import_handler, "")

clear_handler = '''clearButton.addEventListener("click", async () => {
  const confirmed = confirm(
    "Delete the current captured workflow?"
  );

  if (!confirmed) return;

  titleInput.value = "";

  render(
    await sendMessage({
      type: "CLEAR_RECORDING"
    })
  );
});

'''

popup_js = popup_js.replace(clear_handler, "")

popup_js_path.write_text(popup_js)

# ---------------------------------------------------------
# 3. Update background.js
# Keep a temporary pending copy after Stop Recording.
# ---------------------------------------------------------

background_path = Path("extension/background.js")
background = background_path.read_text()

# Add pending workflow variable.
old_variables = '''let recording = false;
let steps = [];
let recordingTitle = "Captured workflow";
let startedAt = null;
'''

new_variables = '''let recording = false;
let steps = [];
let recordingTitle = "Captured workflow";
let startedAt = null;
let pendingWorkflow = null;
'''

if old_variables in background:
    background = background.replace(
        old_variables,
        new_variables,
        1
    )
elif "let pendingWorkflow = null;" not in background:
    raise SystemExit(
        "Could not find the background state variables."
    )

# Include pendingWorkflow while loading state.
old_load_keys = '''    "recordingTitle",
    "startedAt"
  ]);
'''

new_load_keys = '''    "recordingTitle",
    "startedAt",
    "pendingWorkflow"
  ]);
'''

if old_load_keys in background:
    background = background.replace(
        old_load_keys,
        new_load_keys,
        1
    )

old_load_assignment = '''  startedAt = state.startedAt || null;
}
'''

new_load_assignment = '''  startedAt = state.startedAt || null;
  pendingWorkflow =
    state.pendingWorkflow || null;
}
'''

if old_load_assignment in background:
    background = background.replace(
        old_load_assignment,
        new_load_assignment,
        1
    )

# Include pendingWorkflow while saving.
old_save_state = '''    recordingTitle,
    startedAt
  });
}
'''

new_save_state = '''    recordingTitle,
    startedAt,
    pendingWorkflow
  });
}
'''

if old_save_state in background:
    background = background.replace(
        old_save_state,
        new_save_state,
        1
    )

# Replace Stop Recording logic.
start_marker = '''      if (message.type === "STOP_RECORDING") {'''
end_marker = '''      if (message.type === "GET_AUTO_IMPORT") {'''

start_index = background.find(start_marker)
end_index = background.find(end_marker)

if start_index == -1 or end_index == -1:
    raise SystemExit(
        "Could not find the automatic import blocks."
    )

new_stop_block = '''      if (message.type === "STOP_RECORDING") {
        recording = false;

        if (steps.length === 0) {
          await saveState();

          sendResponse({
            success: false,
            recording,
            steps,
            recordingTitle,
            startedAt,
            error: "No workflow steps were captured."
          });
          return;
        }

        pendingWorkflow = {
          version: 2,
          source: "zivora-chrome-extension",
          title: recordingTitle,
          description: `Workflow captured with Zivora on ${
            startedAt
              ? new Date(startedAt).toLocaleString()
              : "an unknown date"
          }.`,
          startedAt,
          exportedAt: new Date().toISOString(),
          steps: [...steps]
        };

        steps = [];
        recordingTitle = "Captured workflow";
        startedAt = null;

        await saveState();

        await chrome.tabs.create({
          url: "http://localhost:3000/capture/auto-import"
        });

        sendResponse({
          success: true,
          recording: false,
          steps: [],
          recordingTitle: "Captured workflow",
          startedAt: null,
          creatingGuide: true
        });
        return;
      }

'''

background = (
    background[:start_index]
    + new_stop_block
    + background[end_index:]
)

# Replace GET_AUTO_IMPORT so it sends the temporary copy.
get_start_marker = '''      if (message.type === "GET_AUTO_IMPORT") {'''
get_end_marker = '''      if (message.type === "AUTO_IMPORT_COMPLETE") {'''

get_start = background.find(get_start_marker)
get_end = background.find(get_end_marker)

if get_start == -1 or get_end == -1:
    raise SystemExit(
        "Could not find GET_AUTO_IMPORT block."
    )

new_get_block = '''      if (message.type === "GET_AUTO_IMPORT") {
        if (!pendingWorkflow) {
          sendResponse({
            success: false,
            error: "No completed workflow is waiting to be imported."
          });
          return;
        }

        sendResponse({
          success: true,
          workflow: pendingWorkflow
        });
        return;
      }

'''

background = (
    background[:get_start]
    + new_get_block
    + background[get_end:]
)

# Replace import-complete block so it clears only pendingWorkflow.
complete_start_marker = '''      if (message.type === "AUTO_IMPORT_COMPLETE") {'''
complete_end_marker = '''      if (message.type === "CLEAR_RECORDING") {'''

complete_start = background.find(
    complete_start_marker
)
complete_end = background.find(
    complete_end_marker
)

if complete_start == -1 or complete_end == -1:
    raise SystemExit(
        "Could not find AUTO_IMPORT_COMPLETE block."
    )

new_complete_block = '''      if (message.type === "AUTO_IMPORT_COMPLETE") {
        pendingWorkflow = null;
        await saveState();

        sendResponse({
          success: true
        });
        return;
      }

'''

background = (
    background[:complete_start]
    + new_complete_block
    + background[complete_end:]
)

background_path.write_text(background)

print("Extension cleanup installed successfully.")
PY

echo ""
echo "Checking the application build..."
npm run build

echo ""
echo "============================================"
echo "EXTENSION CLEANUP COMPLETE"
echo "============================================"
echo ""
echo "The popup now contains only:"
echo "- Guide title"
echo "- Start recording"
echo "- Stop recording"
echo "- Privacy protection"
echo ""
echo "After Stop recording:"
echo "- captured steps clear immediately"
echo "- guide creation continues safely"
echo "- the new guide opens automatically"
