const status = document.querySelector("#status");
const desktop = new URL(location.href).searchParams.get("desktop");
const isPwa = window.matchMedia("(display-mode: standalone)").matches;

if (isPwa && desktop) {
  fetch(`/launch?desktop=${encodeURIComponent(desktop)}`, { method: "POST" })
    .then(async (response) => {
      if (!response.ok) throw new Error(await response.text());
      window.close();
    })
    .catch((error) => {
      status.textContent = error.message;
    });
}
