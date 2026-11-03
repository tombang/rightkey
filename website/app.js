(() => {
  "use strict";
  const release = window.RIGHTKEY_RELEASE;
  if (release) {
    document.querySelectorAll("[data-download]").forEach((link) => {
      link.href = release.download;
    });
    document.querySelectorAll("[data-checksum]").forEach((link) => {
      link.href = release.checksum;
    });
    document.querySelectorAll("[data-version]").forEach((label) => {
      label.textContent = `v${release.version}`;
    });
  }
  document.querySelector("#year").textContent = new Date().getFullYear();
  const files = document.querySelector("#demo-files");
  const initialFiles = files.innerHTML;
  const toast = document.querySelector("#demo-toast");
  const status = document.querySelector("#demo-status");
  const paste = document.querySelector('[data-demo="paste"]');
  const pasteLabel = document.querySelector("#paste-label");
  const templateMenu = document.querySelector("#template-menu");
  let clipboard = null;
  let toastTimer;
  function notify(message) {
    clearTimeout(toastTimer);
    toast.textContent = message;
    toast.hidden = false;
    toastTimer = setTimeout(() => {
      toast.hidden = true;
    }, 4200);
  }
  function count() {
    status.textContent = `${files.children.length} 个项目`;
  }
  function addFile(extension) {
    const item = document.createElement("div");
    item.className = "demo-file new-file";
    const art = document.createElement("span");
    art.className = `file-art ${extension ? "document-art" : "folder-art"}`;
    art.textContent = extension ? extension.toUpperCase() : "";
    const label = document.createElement("span");
    const base = extension ? "未命名文件" : "新建文件夹";
    const suffix = extension ? `.${extension}` : "";
    const names = new Set(
      [...files.children].map((child) => child.lastElementChild.textContent),
    );
    let name = base + suffix;
    let number = 2;
    while (names.has(name)) {
      name = `${base} (${number++})${suffix}`;
    }
    label.textContent = name;
    item.append(art, label);
    files.append(item);
    count();
    return name;
  }
  function closeTemplates() {
    templateMenu.hidden = true;
    document
      .querySelector('[data-demo="template"]')
      .setAttribute("aria-expanded", "false");
  }
  document.querySelectorAll("[data-demo]").forEach((button) => {
    if (button.dataset.demo === "template") {
      button.setAttribute("aria-controls", "template-menu");
      button.setAttribute("aria-expanded", "false");
    }
    button.addEventListener("click", () => {
      const action = button.dataset.demo;
      if (action === "template") {
        templateMenu.hidden = !templateMenu.hidden;
        button.setAttribute("aria-expanded", String(!templateMenu.hidden));
        if (!templateMenu.hidden) templateMenu.querySelector("button").focus();
        return;
      }
      closeTemplates();
      if (action === "folder") notify(`已新建「${addFile("")}」`);
      if (action === "copy" || action === "cut") {
        files
          .querySelectorAll(".is-cut")
          .forEach((item) => item.classList.remove("is-cut"));
        clipboard = action;
        paste.disabled = false;
        pasteLabel.textContent =
          action === "cut" ? "粘贴（移动剪切项）" : "粘贴（复制）";
        if (action === "cut") files.children[1]?.classList.add("is-cut");
        notify(
          action === "cut"
            ? "已标记「灵感笔记.md」。点击粘贴，体验移动。"
            : "已复制「灵感笔记.md」。点击粘贴，体验创建副本。",
        );
      }
      if (action === "paste" && clipboard) {
        if (clipboard === "cut") {
          files
            .querySelectorAll(".is-cut")
            .forEach((item) => item.classList.remove("is-cut"));
          notify(
            "移动成功。实际使用时，请先进入目标文件夹，再粘贴。此演示不移动任何真实文件。",
          );
          clipboard = null;
          paste.disabled = true;
          pasteLabel.textContent = "粘贴（复制）";
        } else {
          addFile("md");
          files.lastElementChild.lastElementChild.textContent =
            uniqueNoteName();
          notify("已创建笔记副本，源文件保留。遇到同名文件会自动编号。");
        }
      }
      if (action === "path")
        notify("路径示例：/Users/you/Projects/灵感笔记.md（未修改你的剪贴板）");
      if (action === "terminal")
        notify("实际使用时，终端会直接打开当前文件夹，无需手动输入路径。");
    });
  });
  function uniqueNoteName() {
    const names = new Set(
      [...files.children]
        .slice(0, -1)
        .map((item) => item.lastElementChild.textContent),
    );
    let index = 2;
    while (names.has(`灵感笔记 (${index}).md`)) index++;
    return `灵感笔记 (${index}).md`;
  }
  document.querySelectorAll("[data-demo-file]").forEach((button) =>
    button.addEventListener("click", () => {
      notify(`已从模板创建「${addFile(button.dataset.demoFile)}」`);
      closeTemplates();
      document.querySelector('[data-demo="template"]').focus();
    }),
  );
  document.addEventListener("click", (event) => {
    if (
      !event.target.closest(".template-menu") &&
      !event.target.closest('[data-demo="template"]')
    )
      closeTemplates();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !templateMenu.hidden) {
      closeTemplates();
      document.querySelector('[data-demo="template"]').focus();
    }
  });
  document.querySelector("#reset-demo").addEventListener("click", () => {
    files.innerHTML = initialFiles;
    clipboard = null;
    paste.disabled = true;
    pasteLabel.textContent = "粘贴（复制）";
    closeTemplates();
    count();
    notify("演示已重置。选一个菜单，再试一次。");
  });
})();
