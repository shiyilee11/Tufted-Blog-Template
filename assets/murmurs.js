/**
 * Author murmurs widget: paginate the murmur history panel.
 *
 * Shows at most PER_PAGE entries per page inside the expandable panel,
 * with prev/next controls and a page indicator. The collapsed pill in
 * the top-right corner always shows the latest murmur.
 *
 * Loaded only on pages that render the murmur widget. Without JS, all
 * entries remain visible inside the scrollable panel (graceful fallback).
 */
(() => {
	"use strict";

	const PER_PAGE = 5;

	const widget = document.querySelector("details.murmur-widget");
	if (!widget) {
		return;
	}

	const panel = widget.querySelector(".murmur-panel");
	if (!panel) {
		return;
	}

	const items = Array.from(panel.querySelectorAll(".murmur-item"));
	if (items.length <= PER_PAGE) {
		// 5 条以内不需要翻页控件。
		return;
	}

	const pageCount = Math.ceil(items.length / PER_PAGE);
	let page = 0;

	const pager = document.createElement("div");
	pager.className = "murmur-pager";

	const prev = document.createElement("button");
	prev.type = "button";
	prev.className = "murmur-pager-btn";
	prev.textContent = "‹ 上一页";

	const info = document.createElement("span");
	info.className = "murmur-pager-info";
	info.setAttribute("aria-live", "polite");

	const next = document.createElement("button");
	next.type = "button";
	next.className = "murmur-pager-btn";
	next.textContent = "下一页 ›";

	function render() {
		items.forEach((item, index) => {
			item.hidden = !(
				index >= page * PER_PAGE && index < (page + 1) * PER_PAGE
			);
		});
		info.textContent = page + 1 + " / " + pageCount;
		prev.disabled = page === 0;
		next.disabled = page === pageCount - 1;
		panel.scrollTop = 0;
	}

	prev.addEventListener("click", () => {
		if (page > 0) {
			page -= 1;
			render();
		}
	});

	next.addEventListener("click", () => {
		if (page < pageCount - 1) {
			page += 1;
			render();
		}
	});

	pager.append(prev, info, next);
	panel.append(pager);
	render();
})();