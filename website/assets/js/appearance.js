// 浅色、深色外观：页面默认跟着系统外观，访客用导航里的按钮换成另一种之后按选择显示，
// 换回系统此刻的外观就重新跟着系统；
// 本脚本由各页 <head> 同步加载，在首次绘制前应用，避免先按系统外观闪一下

(() => {
  "use strict";

  // 选择存在 localStorage 里的键，与语言的选择分开
  const STORAGE_KEY = "flotilla.appearance";

  // 系统外观是不是深色
  const systemDark = window.matchMedia("(prefers-color-scheme: dark)");

  // 访客是不是要求减少动态效果
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  // 访客的选择：`light` 或 `dark`；空字符串表示没有选择，跟着系统
  let choice = readChoice();

  // 样式表里以系统外观为条件的规则，连同原来的条件
  const rules = collectRules();

  // 元素原来写着的条件，第一次见到这个元素时记下；不归这里管的记成 `null`
  const originals = new WeakMap();

  apply();

  // 没有选择时页面跟着系统外观，系统换了 `<html>` 上的属性也跟着换
  systemDark.addEventListener("change", () => {
    if (!choice) {
      apply();
    }
  });

  // 正文还在解析：`<picture>` 里的 `<source>` 一出现就换掉条件，赶在这一段正文绘制之前；
  // 导航上的按钮等正文解析完再接
  if (document.readyState === "loading") {
    const parsing = new MutationObserver(applyToElements);

    parsing.observe(document, { childList: true, subtree: true });

    document.addEventListener("DOMContentLoaded", () => {
      parsing.disconnect();
      applyToElements();
      setUp();
    });
  } else {
    setUp();
  }

  /**
   * 把各页按系统外观换的样式与位图改成按这次的选择换：<html> 上写 `data-appearance`，
   * 样式表里以 `prefers-color-scheme` 为条件的规则换掉条件，元素上的条件见 applyToElements()。
   */
  function apply() {
    document.documentElement.dataset.appearance = effective();

    for (const rule of rules) {
      set(rule.media, "mediaText", rule.original);
    }

    applyToElements();
  }

  /**
   * 把各页的 `theme-color` 与 `<picture>` 里换图的 `<source>` 的 `media` 换成按这次的选择。
   */
  function applyToElements() {
    // `<source>` 在正文里，晚于本脚本出现，每次现查；条件改过之后认不出来，按第一次见到时记下的原条件判断
    for (const element of document.querySelectorAll("meta[media], picture > source[media]")) {
      if (!originals.has(element)) {
        const media = element.getAttribute("media");

        // 只认按系统外观换的：favicon 之类的记成 `null`，让它继续跟着系统
        originals.set(element, media.includes("prefers-color-scheme") ? media : null);
      }

      const original = originals.get(element);

      if (original !== null) {
        set(element, "media", original);
      }
    }
  }

  /**
   * 给导航上的按钮接上切换：点击后换成另一种外观，并把选择记进 localStorage。
   */
  function setUp() {
    const button = document.querySelector("[data-appearance-toggle]");

    if (!button) {
      return;
    }

    button.addEventListener("click", () => {
      const next = effective() === "dark" ? "light" : "dark";

      // 换回系统此刻的外观就是不再指定：清掉选择，重新跟着系统
      choice = next === systemAppearance() ? "" : next;

      try {
        if (choice) {
          localStorage.setItem(STORAGE_KEY, choice);
        } else {
          localStorage.removeItem(STORAGE_KEY);
        }
      } catch {
        // 存不进去时只是下次打开记不住，这次照样按它显示
      }

      switchAppearance();
    });
  }

  /**
   * 换外观：由浏览器的整页过渡交叉淡入，渐变与图片都跟着淡过去。
   *
   * 浏览器不支持整页过渡时直接换；访客要求减少动态效果时也直接换，样式表里关动效的那条规则管不到整页过渡。
   */
  function switchAppearance() {
    if (reduceMotion.matches || !document.startViewTransition) {
      apply();

      return;
    }

    document.startViewTransition(apply);
  }

  /**
   * 这次该按哪种外观显示：访客选择过就按选择，没选择过按系统。
   *
   * @returns {string} `light` 或 `dark`
   */
  function effective() {
    return choice || systemAppearance();
  }

  /**
   * 系统此刻的外观。
   *
   * @returns {string} `light` 或 `dark`
   */
  function systemAppearance() {
    return systemDark.matches ? "dark" : "light";
  }

  /**
   * 读访客选择过的外观。
   *
   * @returns {string} `light`、`dark`，或没有选择时的空字符串
   */
  function readChoice() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);

      return saved === "light" || saved === "dark" ? saved : "";
    } catch {
      // 读取抛错时当作没有选择过，按系统外观显示
      return "";
    }
  }

  /**
   * 收集样式表里以系统外观为条件的规则，含嵌套在其它条件里的，连同它们原来的条件。
   *
   * @returns {Array<{ media: MediaList, original: string }>} 规则的条件
   */
  function collectRules() {
    const found = [];

    for (const sheet of document.styleSheets) {
      // 读不到跨域样式表的规则时当作没有，它是别的站点的资源，不受这里管
      let queue;

      try {
        queue = [...sheet.cssRules];
      } catch {
        continue;
      }

      while (queue.length > 0) {
        const rule = queue.shift();

        if (!rule.media) {
          continue;
        }

        if (rule.media.mediaText.includes("prefers-color-scheme")) {
          found.push({ media: rule.media, original: rule.media.mediaText });
        }

        queue.push(...rule.cssRules);
      }
    }

    return found;
  }

  /**
   * 把以系统外观为条件的媒体查询换成按这次的选择：选择浅色或深色时固定取其中一种，
   * 没有选择时恢复原来的条件，继续跟着系统。
   *
   * 页面里的媒体查询都是单独一项条件，如 `(prefers-color-scheme: dark)`；
   * 与其它条件并用时这里换不动，会原样留着。
   *
   * @param {string} media 原来的媒体查询
   * @param {string} value 这次的选择，空字符串表示没有选择
   * @returns {string} 换过条件的媒体查询
   */
  function swapScheme(media, value) {
    if (!value) {
      return media;
    }

    const condition = media.trim();

    if (!/^\(\s*prefers-color-scheme\s*:\s*(dark|light)\s*\)$/i.test(condition)) {
      return media;
    }

    const isDark = /dark\s*\)$/i.test(condition);

    return isDark === (value === "dark") ? "all" : "not all";
  }

  /**
   * 把一个样式表条件或元素上的条件换成按这次的选择算出的，值没变就不写。
   *
   * @param {object} target `MediaList` 或元素
   * @param {string} property 写条件的属性名：`MediaList` 用 `mediaText`，元素用 `media`
   * @param {string} media 原来的条件
   */
  function set(target, property, media) {
    const next = swapScheme(media, choice);

    if (target[property] !== next) {
      target[property] = next;
    }
  }
})();
