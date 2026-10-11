(function () {
  var key = "sealgen-lang";

  function preferred() {
    var saved = localStorage.getItem(key);
    if (saved === "zh" || saved === "en") return saved;
    return (navigator.language || "").toLowerCase().indexOf("zh") === 0 ? "zh" : "en";
  }

  function apply(lang) {
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    document.querySelectorAll("[data-lang]").forEach(function (node) {
      node.hidden = node.getAttribute("data-lang") !== lang;
    });
    document.querySelectorAll("[data-set-lang]").forEach(function (button) {
      button.setAttribute("aria-pressed", button.getAttribute("data-set-lang") === lang ? "true" : "false");
    });
    localStorage.setItem(key, lang);
  }

  document.querySelectorAll("[data-set-lang]").forEach(function (button) {
    button.addEventListener("click", function () {
      apply(button.getAttribute("data-set-lang"));
    });
  });

  apply(preferred());
})();
