// 发版数据：读取组装时写好的 releases.json，把最新版本填进下载按钮、版本号与日期，渲染更新日志页；
// 下载开始后在首页弹出通知卡片，在下载页切换为 “已开始下载” 并滚到安装步骤

(() => {
  "use strict";

  // 页面的根元素：发版数据的读取状态写在它的 `data-release` 上，CSS 据此切换显示的内容
  const root = document.documentElement;

  // 页面到站点根目录的相对路径，由各页在 <html data-root> 上声明
  const siteRoot = root.dataset.root ?? "./";

  // 等待 releases.json 的上限，单位毫秒；超时按读取失败处理，页面退回到 GitHub 链接
  const LOAD_TIMEOUT = 5000;

  // 下载页切换为 “已开始下载” 后，停留多久再滚到安装步骤，单位毫秒
  const SCROLL_DELAY = 450;

  // 系统的 “减弱动态效果” 设置；打开时滚到安装步骤不用平滑滚动
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  // 按页面语言格式化发布日期，如 “October 14, 2026”
  const dateFormat = new Intl.DateTimeFormat(root.lang, {
    dateStyle: "long",
  });

  // 按页面语言格式化 zip 的大小，以 MB 为单位、保留一位小数
  const sizeFormat = new Intl.NumberFormat(root.lang, {
    style: "unit",
    unit: "megabyte",
    maximumFractionDigits: 1,
  });

  setUpToast();

  // 先填好内容再声明状态：CSS 按 `data-release` 决定显示哪一组元素，避免露出空的版本号
  loadReleases()
    .then((releases) => {
      const latest = releases.find((release) => !release.prerelease);

      if (latest) {
        fillLatest(latest);
      }

      renderReleaseNotes(releases, latest);
      root.dataset.release = latest ? "latest" : "none";
    })
    .catch(() => {
      root.dataset.release = "error";
    });

  /**
   * 读取同源的 releases.json。
   *
   * @returns {Promise<Array<object>>} 全部 Release，已按发布时间从新到旧排好
   */
  async function loadReleases() {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), LOAD_TIMEOUT);

    try {
      const response = await fetch(`${siteRoot}releases.json`, {
        cache: "no-cache",
        signal: controller.signal,
      });

      if (!response.ok) {
        throw new Error(`releases.json 返回 ${response.status}`);
      }

      const releases = await response.json();

      if (!Array.isArray(releases)) {
        throw new TypeError("releases.json 不是数组");
      }

      return releases;
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * 把最新版本填进页面：版本号、发布日期、zip 的名称与大小、下载链接与更新日志的锚点。
   *
   * @param {object} release 第一个非预发布的 Release
   */
  function fillLatest(release) {
    const zip = zipOf(release);
    const zipSize = zip ? sizeOf(zip) : "";

    setText("[data-release-version]", versionOf(release));
    setText("[data-release-asset-name]", zip?.name ?? "");
    setText("[data-release-asset-size]", zipSize);

    document.querySelectorAll("[data-release-date]").forEach((node) => {
      node.dateTime = release.publishedAt;
      node.textContent = formatDate(release.publishedAt);
    });

    document.querySelectorAll("[data-release-notes-link]").forEach((link) => {
      link.hash = release.tag;
    });

    // 有 zip 时按钮直接下载它；这个版本没有 zip 时退回到它在 GitHub 上的页面，也就不提示 “已开始下载”
    document.querySelectorAll("[data-download]").forEach((link) => {
      link.href = zip?.url ?? release.url;
    });

    if (zip) {
      setUpDownloadFeedback();
    }
  }

  /**
   * 下载按钮被点击后照常下载，同时给出反馈：首页弹出通知卡片，下载页切换卡片状态。
   */
  function setUpDownloadFeedback() {
    const toast = document.querySelector("[data-download-toast]");
    const card = document.querySelector("[data-download-card]");

    // 不阻止默认行为：zip 的链接由 GitHub 以附件返回，浏览器直接下载，页面不跳转
    document.querySelectorAll("[data-download]").forEach((link) => {
      link.addEventListener("click", () => {
        if (toast && !toast.open) {
          toast.show();
        }

        if (card) {
          markDownloadStarted(card);
        }
      });
    });
  }

  /**
   * 通知卡片不自动消失：关闭按钮与 Esc 都能关掉它。
   */
  function setUpToast() {
    const toast = document.querySelector("[data-download-toast]");

    if (!toast) {
      return;
    }

    const closeButton = toast.querySelector("[data-toast-close]");

    closeButton?.addEventListener("click", () => {
      toast.close();
    });

    // 非模态的 dialog 不响应 Esc，这里补上
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && toast.open) {
        toast.close();
      }
    });
  }

  /**
   * 下载页：卡片切换为 “已开始下载”，稍后平滑滚到安装步骤，并短暂高亮第一步。
   *
   * @param {HTMLElement} card 下载卡片
   */
  function markDownloadStarted(card) {
    card.dataset.state = "started";

    const install = document.getElementById("install");
    const firstStep = document.querySelector("[data-install-step]");

    if (!install) {
      return;
    }

    setTimeout(() => {
      install.scrollIntoView({
        behavior: reduceMotion.matches ? "auto" : "smooth",
        block: "start",
      });

      // 先去掉再加上，连续点击时高亮也能重新播放
      firstStep?.classList.remove("is-highlighted");
      void firstStep?.offsetWidth;
      firstStep?.classList.add("is-highlighted");
    }, SCROLL_DELAY);
  }

  /**
   * 更新日志页：逐个渲染版本，生成桌面的版本目录与窄屏的 “跳到版本” 选择；没有版本时显示空状态。
   *
   * @param {Array<object>} releases 全部 Release
   * @param {object | undefined} latest 最新的正式版本
   */
  function renderReleaseNotes(releases, latest) {
    const list = document.querySelector("[data-release-list]");

    if (!list) {
      return;
    }

    if (releases.length === 0) {
      document.querySelector("[data-release-empty]").hidden = false;
      return;
    }

    const template = document.querySelector("[data-release-template]");

    for (const release of releases) {
      list.append(renderRelease(template, release, release === latest));
    }

    renderNavigation(releases);
    document.querySelector("[data-release-content]").hidden = false;

    // 锚点指向的版本是刚生成的，浏览器加载时跳不过去，渲染完再跳一次；
    // 锚点的百分号编码不合法时解码会抛错，这时不跳，免得整页被当成读取失败
    let targetId;

    try {
      targetId = decodeURIComponent(location.hash.slice(1));
    } catch {
      return;
    }

    document.getElementById(targetId)?.scrollIntoView();
  }

  /**
   * 按模板生成一个版本的条目。
   *
   * @param {HTMLTemplateElement} template 更新日志页里的版本模板
   * @param {object} release 要渲染的 Release
   * @param {boolean} isLatest 是否为最新的正式版本
   * @returns {DocumentFragment} 渲染好的条目
   */
  function renderRelease(template, release, isLatest) {
    const fragment = template.content.cloneNode(true);
    const zip = zipOf(release);

    // 取模板里 `data-field` 为 name 的元素
    const field = (name) => fragment.querySelector(`[data-field="${name}"]`);

    // 版本标题链到自己的锚点，复制链接按钮复制这个锚点的完整地址
    const permalink = new URL(`#${release.tag}`, location.href);

    fragment.querySelector("article").id = release.tag;
    field("anchor").href = `#${release.tag}`;
    field("version").textContent = versionOf(release);
    field("copy-link").dataset.copy = permalink.href;

    field("latest").hidden = !isLatest;
    field("prerelease").hidden = !release.prerelease;

    field("date").dateTime = release.publishedAt;
    field("date").textContent = formatDate(release.publishedAt);

    // 没有 zip 的版本不放下载 chip
    if (zip) {
      field("asset").href = zip.url;
      field("asset-name").textContent = zip.name;
      field("asset-size").textContent = sizeOf(zip);
    } else {
      field("asset").remove();
    }

    field("body").append(bodyOf(release));
    field("url").href = release.url;

    return fragment;
  }

  /**
   * 生成版本目录与 “跳到版本” 的选项，并随滚动高亮当前所在的版本。
   *
   * @param {Array<object>} releases 全部 Release
   */
  function renderNavigation(releases) {
    const toc = document.querySelector("[data-release-toc]");
    const jump = document.querySelector("[data-release-jump]");

    for (const release of releases) {
      const item = document.createElement("li");
      const link = document.createElement("a");
      const date = document.createElement("time");

      link.href = `#${release.tag}`;
      link.textContent = versionOf(release);

      date.dateTime = release.publishedAt;
      date.textContent = formatDate(release.publishedAt);

      link.append(date);
      item.append(link);
      toc.append(item);

      jump.append(new Option(versionOf(release), release.tag));
    }

    // 选中某个版本即跳过去；改的是锚点，浏览器的前进后退也能用
    jump.addEventListener("change", () => {
      // 锚点已经是这个版本时，再写一次浏览器不会跳，直接滚过去
      if (location.hash === `#${jump.value}`) {
        document.getElementById(jump.value)?.scrollIntoView();
        return;
      }

      location.hash = jump.value;
    });

    const articles = [
      ...document.querySelectorAll("[data-release-list] > article"),
    ];

    // 每次滚动都重新判断：平滑滚动停下的最后一刻也要算一次，跳到的版本才会被高亮；
    // 视口尺寸变化会移动判断线，也重新判断
    const update = () => {
      highlightCurrent(articles, toc, jump);
    };

    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    update();
  }

  /**
   * 高亮当前所在的版本：顶边越过判断线的最后一个版本；一个都没越过时是第一个版本。
   * 判断线在视口 30% 处；视口矮时下移到跳转后条目顶边的停靠位置，跳到的版本也算越过。
   *
   * @param {Array<HTMLElement>} articles 全部版本的条目，从上到下
   * @param {HTMLElement} toc 版本目录
   * @param {HTMLSelectElement} jump “跳到版本” 的选择
   */
  function highlightCurrent(articles, toc, jump) {
    // 跳转后条目顶边停在 `scroll-padding-top` 加上条目的 `scroll-margin-top` 处，两者随断点变化，每次从计算样式读
    const stop = parseFloat(getComputedStyle(root).scrollPaddingTop)
      + parseFloat(getComputedStyle(articles[0]).scrollMarginTop);

    // 多留 1 px，免得小数像素的停靠位置刚好落在线下
    const line = Math.max(window.innerHeight * 0.3, (stop || 0) + 1);

    const passed = articles.filter(
      (article) => article.getBoundingClientRect().top <= line,
    );

    const current = passed.at(-1) ?? articles[0];

    // `aria-current` 写空字符串等同于 false，当前项要明确写 true
    toc.querySelectorAll("a").forEach((link) => {
      if (link.hash === `#${current.id}`) {
        link.setAttribute("aria-current", "true");
      } else {
        link.removeAttribute("aria-current");
      }
    });

    jump.value = current.id;
  }

  /**
   * 把页面语言的正文变成节点，没有这种语言的正文时用英文的；
   * 正文里的标题降一级，接在版本号的 h2 之下，保持标题层级连续。
   *
   * @param {object} release 要渲染的 Release
   * @returns {DocumentFragment} 正文的节点
   */
  function bodyOf(release) {
    const container = document.createElement("template");
    container.innerHTML = release.bodyHtml[root.lang] ?? release.bodyHtml.en ?? "";

    const headings = container.content.querySelectorAll("h1, h2, h3, h4, h5");

    headings.forEach((heading) => {
      const level = Math.max(3, Number(heading.tagName[1]) + 1);
      const replacement = document.createElement(`h${level}`);

      replacement.append(...heading.childNodes);
      heading.replaceWith(replacement);
    });

    return container.content;
  }

  /**
   * 取 Release 里的 zip 资产。
   *
   * @param {object} release 一个 Release
   * @returns {object | undefined} zip 资产，没有时为 undefined
   */
  function zipOf(release) {
    return release.assets.find((asset) => asset.name.endsWith(".zip"));
  }

  /**
   * 按页面语言格式化资产的大小。
   *
   * @param {object} asset Release 里的一个资产
   * @returns {string} 以 MB 为单位的大小，如 “1.2 MB”
   */
  function sizeOf(asset) {
    return sizeFormat.format(asset.size / 1_000_000);
  }

  /**
   * 去掉 tag 开头的 `v`，得到页面上显示的版本号。
   *
   * @param {object} release 一个 Release
   * @returns {string} 版本号，如 `1.0.0`
   */
  function versionOf(release) {
    return release.tag.replace(/^v/, "");
  }

  /**
   * 按页面语言格式化日期；中文在数字与汉字之间留空格，与页面其它中文的排版一致。
   *
   * @param {string} iso ISO 8601 格式的时间
   * @returns {string} 格式化后的日期
   */
  function formatDate(iso) {
    const text = dateFormat.format(new Date(iso));

    if (!root.lang.startsWith("zh")) {
      return text;
    }

    return text.replace(/(\d)(?=[^\d\s])|([^\d\s])(?=\d)/gu, "$1$2 ");
  }

  /**
   * 把文字写进所有匹配的元素。
   *
   * @param {string} selector 选择器
   * @param {string} text 文字
   */
  function setText(selector, text) {
    document.querySelectorAll(selector).forEach((node) => {
      node.textContent = text;
    });
  }
})();
