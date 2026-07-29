const titleInput = document.getElementById("title");
const statusElement = document.getElementById("status");
const counterElement = document.getElementById("counter");

const startButton = document.getElementById("start");
const stopButton = document.getElementById("stop");
const exportButton = document.getElementById("export");
const openImportButton =
  document.getElementById("openImport");
const clearButton = document.getElementById("clear");

async function sendMessage(message) {
  return chrome.runtime.sendMessage(message);
}

function render(state) {
  const active = Boolean(state.recording);
  const count = Array.isArray(state.steps)
    ? state.steps.length
    : 0;

  if (state.recordingTitle) {
    titleInput.value = state.recordingTitle;
  }

  statusElement.textContent = active
    ? "Recording in progress"
    : "Not recording";

  statusElement.classList.toggle(
    "recording",
    active
  );

  counterElement.textContent =
    `${count} step${count === 1 ? "" : "s"} captured`;

  startButton.disabled = active;
  stopButton.disabled = !active;
  exportButton.disabled = count === 0;
  titleInput.disabled = active;
}

startButton.addEventListener("click", async () => {
  const state = await sendMessage({
    type: "START_RECORDING",
    title: titleInput.value
  });

  render(state);
  window.close();
});

stopButton.addEventListener("click", async () => {
  render(
    await sendMessage({
      type: "STOP_RECORDING"
    })
  );
});

exportButton.addEventListener("click", async () => {
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

openImportButton.addEventListener(
  "click",
  async () => {
    await chrome.tabs.create({
      url: "http://localhost:3000/capture/import"
    });
  }
);

clearButton.addEventListener("click", async () => {
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

sendMessage({
  type: "GET_STATE"
})
  .then(render)
  .catch((error) => {
    console.error(error);
    statusElement.textContent = "Extension error";
  });
