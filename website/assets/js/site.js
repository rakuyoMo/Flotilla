// 官网各页共用的交互：导航的毛玻璃与窄屏菜单、当前区块高亮、区块淡入、复制按钮、语言切换

(() => {
  "use strict";

  // 复制成功的提示停留的时长，单位毫秒
  const COPIED_DURATION = 2400;

  // site.css 兜底显示 `.reveal` 的延迟，单位毫秒，须与其中 `reveal-fallback` 动画的延迟一致
  const REVEAL_FALLBACK_DELAY = 3000;

  // 每个复制按钮的收起计时器，再次点击时先清掉上一次的
  const copyTimers = new WeakMap();

  // 播报复制结果的读屏区域，所有复制按钮共用
  const announcer = createAnnouncer();

  setUpHeader();
  setUpMenu();
  setUpSectionHighlight();
  setUpReveal();
  setUpCopyButtons();
  setUpLanguageSwitch();

  /**
   * 滚动离开页顶后，导航换成毛玻璃并出现细分隔线。
   */
  function setUpHeader() {
    const header = document.querySelector("[data-site-header]");

    if (!header) {
      return;
    }

    // 按当前的滚动位置切换导航的样式
    const update = () => {
      header.classList.toggle("is-scrolled", window.scrollY > 8);
    };

    update();
    window.addEventListener("scroll", update, { passive: true });
  }

  /**
   * 窄屏的菜单按钮：点击展开或收起导航；点了菜单里的链接、按 Esc、窗口变宽时收起。
   */
  function setUpMenu() {
    const header = document.querySelector("[data-site-header]");
    const toggle = document.querySelector("[data-nav-toggle]");

    const menu = document.getElementById(
      toggle?.getAttribute("aria-controls") ?? "",
    );

    if (!header || !toggle || !menu) {
      return;
    }

    // 展开或收起菜单，同步菜单按钮的 `aria-expanded`
    const setOpen = (open) => {
      header.classList.toggle("is-open", open);
      toggle.setAttribute("aria-expanded", String(open));

      // 导航收起时一并关闭语言菜单，下次展开从导航入口开始
      if (!open) {
        menu.querySelectorAll(".language-menu[open]").forEach((item) => {
          item.open = false;
        });
      }
    };

    toggle.addEventListener("click", () => {
      setOpen(!header.classList.contains("is-open"));
    });

    menu.addEventListener("click", (event) => {
      if (event.target.closest("a")) {
        setOpen(false);
      }
    });

    // 按 Esc 收起时把焦点还给菜单按钮，键盘用户不会迷失位置
    document.addEventListener("keydown", (event) => {
      if (
        event.key !== "Escape"
        || !header.classList.contains("is-open")
        || document.querySelector(".language-menu[open]")
      ) {
        return;
      }

      setOpen(false);
      toggle.focus();
    });

    // 与 CSS 里收起菜单的断点一致
    const wide = window.matchMedia("(min-width: 900px)");

    wide.addEventListener("change", (event) => {
      if (event.matches) {
        setOpen(false);
      }
    });
  }

  /**
   * 导航里指向本页区块的链接，在滚到那个区块时高亮。
   */
  function setUpSectionHighlight() {
    const links = [...document.querySelectorAll("[data-nav-section]")];

    const sections = links
      .map((link) => document.getElementById(link.dataset.navSection))
      .filter(Boolean);

    if (sections.length === 0) {
      return;
    }

    // 只看视口中间的一条窄带：哪个区块压在这条带上，哪个就是当前区块
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const link = links.find(
            (item) => item.dataset.navSection === entry.target.id,
          );

          link?.classList.toggle("is-active", entry.isIntersecting);
        }
      },
      { rootMargin: "-45% 0px -50% 0px" },
    );

    sections.forEach((section) => observer.observe(section));
  }

  /**
   * 带 `reveal` 的元素进入视口时淡入上移，只播放一次。
   */
  function setUpReveal() {
    const items = document.querySelectorAll(".reveal");

    if (items.length === 0) {
      return;
    }

    // site.css 会在页面打开几秒后兜底显示所有 `.reveal`，免得本脚本没能运行时内容一直透明；
    // 晚于兜底才运行时保持全部显示，否则取消兜底，由下面的观察者逐个淡入
    if (performance.now() >= REVEAL_FALLBACK_DELAY) {
      items.forEach((item) => item.classList.add("is-visible"));
      return;
    }

    document.documentElement.classList.add("reveal-ready");

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) {
            continue;
          }

          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      },
      {
        rootMargin: "0px 0px -6% 0px",
        threshold: 0.1,
      },
    );

    items.forEach((item) => observer.observe(item));
  }

  /**
   * 复制按钮：`data-copy` 有值时复制这段文字，否则复制所在代码块里的命令；成功后浮出提示。
   * 用事件委托处理，更新日志页由脚本生成的按钮也能用。
   */
  function setUpCopyButtons() {
    document.addEventListener("click", async (event) => {
      const button = event.target.closest("[data-copy]");

      if (!button) {
        return;
      }

      const text = button.dataset.copy
        || commandsIn(button.closest(".code-block"));

      // 剪贴板不可用（如不安全的上下文、用户拒绝授权）时不给提示，免得误以为已复制
      try {
        await navigator.clipboard.writeText(text);
      } catch {
        return;
      }

      showCopied(button);
    });
  }

  /**
   * 导航与页脚的语言菜单：管理展开状态，并保留当前页面的锚点。
   */
  function setUpLanguageSwitch() {
    const menus = [...document.querySelectorAll(".language-menu")];

    // 点到菜单外部或另一处语言入口时，收起已展开的菜单
    document.addEventListener("click", (event) => {
      menus.forEach((menu) => {
        if (!menu.contains(event.target)) {
          menu.open = false;
        }
      });

      const link = event.target.closest("[data-language-switch]");

      if (!link) {
        return;
      }

      link.hash = location.hash;
    });

    // 焦点离开后关闭浮层，避免键盘用户移到正文时仍被菜单遮挡
    document.addEventListener("focusin", (event) => {
      menus.forEach((menu) => {
        if (!menu.contains(event.target)) {
          menu.open = false;
        }
      });
    });

    // Esc 先关闭语言菜单并归还焦点；窄屏导航保持展开
    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") {
        return;
      }

      const menu = menus.find((item) => item.open);

      if (menu) {
        menu.open = false;
        menu.querySelector("summary").focus();
      }
    });
  }

  /**
   * 取代码块里要复制的命令：去掉注释与空行，粘贴进 zsh 时不会把注释当成命令执行。
   *
   * @param {Element | null} block 代码块元素
   * @returns {string} 一行一条命令
   */
  function commandsIn(block) {
    const code = block?.querySelector("code");

    if (!code) {
      return "";
    }

    const copy = code.cloneNode(true);
    copy.querySelectorAll(".code-comment").forEach((node) => node.remove());

    return copy.textContent
      .split("\n")
      .map((line) => line.trimEnd())
      .filter((line) => line.trim() !== "")
      .join("\n");
  }

  /**
   * 复制成功后：按钮的图标换成对勾，下方浮出 `data-copied-label` 的提示，同时播报给读屏软件；过一会儿复原。
   *
   * @param {HTMLElement} button 被点击的复制按钮
   */
  function showCopied(button) {
    const label = button.dataset.copiedLabel ?? "";
    const icon = button.querySelector("use");

    // 记下原来的图标，连续点击时也能复原成它，而不是对勾
    if (icon && !icon.dataset.icon) {
      icon.dataset.icon = icon.getAttribute("href");
    }

    clearTimeout(copyTimers.get(button));
    button.querySelector(".copy-toast")?.remove();

    // 提示只给眼睛看，读屏软件从共用的播报区域读到同一句话
    const toast = document.createElement("span");
    toast.className = "copy-toast";
    toast.setAttribute("aria-hidden", "true");
    toast.textContent = label;
    button.append(toast);

    icon?.setAttribute("href", "#i-check");
    announcer.textContent = label;

    copyTimers.set(
      button,
      setTimeout(() => {
        toast.remove();
        icon?.setAttribute("href", icon.dataset.icon);
        announcer.textContent = "";
      }, COPIED_DURATION),
    );
  }

  /**
   * 在页面末尾建一个不可见的播报区域，读屏软件会读出写进去的文字。
   *
   * @returns {HTMLElement} 播报区域
   */
  function createAnnouncer() {
    const region = document.createElement("p");
    region.className = "visually-hidden";
    region.setAttribute("role", "status");
    document.body.append(region);

    return region;
  }
})();
