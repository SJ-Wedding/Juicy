// ============================================================
// 공용 헬퍼: 로그인 체크, GNB 렌더링, 유틸 함수
// ============================================================

const GNB_ITEMS = [
  { key: "home", href: "index.html", label: "홈" },
  { key: "recipes", href: "recipes.html", label: "신메뉴 레시피" },
  { key: "notices", href: "notices.html", label: "공지사항" },
  { key: "suggestions", href: "suggestions.html", label: "건의함 · FAQ" },
  { key: "orders", href: "orders.html", label: "본사 발주" },
  { key: "resources", href: "resources.html", label: "자료실" },
  { key: "company", href: "company.html", label: "업체 정보" },
];

// 페이지는 기본적으로 style.css에 의해 숨겨져 있습니다 (html:not(.js-ready) body{visibility:hidden}).
// 로그인 확인이 끝나고 화면을 보여줘도 되는 시점에만 이 함수를 호출하세요.
function revealPage() {
  document.documentElement.classList.add("js-ready");
}

// 로그인 안 되어 있으면 login.html 로 즉시 이동시키고(화면이 보이지 않은 채로), 되어 있으면 { session, profile } 반환
async function requireAuth() {
  const { data: { session }, error } = await sb.auth.getSession();
  if (error || !session) {
    location.replace("login.html");
    return null;
  }
  const { data: profile, error: profileError } = await sb
    .from("profiles")
    .select("*")
    .eq("id", session.user.id)
    .single();

  if (profileError) {
    console.error("프로필 조회 실패:", profileError.message);
  }
  return { session, profile: profile || null };
}

function isVisor(profile) {
  return !!profile && profile.role === "visor";
}

// GNB를 #gnb 요소 안에 그려줍니다.
function renderGnb(activeKey, profile) {
  const gnbEl = document.getElementById("gnb");
  if (!gnbEl) return;

  const linksHtml = GNB_ITEMS.map(
    (item) => `
      <a href="${item.href}" class="gnb-link ${item.key === activeKey ? "active" : ""}">${item.label}</a>
    `
  ).join("");

  gnbEl.innerHTML = `
    <div class="gnb-inner">
      <div class="gnb-brand">
        <span class="brand-logo">JUICY</span>
        <span class="gnb-divider"></span>
        <span class="gnb-sub">파트너 게시판</span>
      </div>
      <nav class="gnb-nav">${linksHtml}</nav>
      <div class="gnb-right">
        <div class="store-chip">${escapeHtml(profile ? profile.store_name : "")}</div>
        <button id="logoutBtn" class="btn-link">로그아웃</button>
      </div>
    </div>
  `;

  document.getElementById("logoutBtn").addEventListener("click", async () => {
    await sb.auth.signOut();
    location.href = "login.html";
  });
}

function escapeHtml(str) {
  if (str === null || str === undefined) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatDate(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${mm}.${dd}`;
}

function isWithinDays(isoString, days) {
  if (!isoString) return false;
  const then = new Date(isoString).getTime();
  const now = Date.now();
  return now - then <= days * 24 * 60 * 60 * 1000;
}

// 유튜브 링크(watch, youtu.be, shorts, embed 등 다양한 형태)에서 영상 ID를 추출합니다.
function getYoutubeId(url) {
  if (!url) return null;
  try {
    const u = new URL(url);
    const host = u.hostname.replace(/^www\./, "");
    if (host === "youtu.be") {
      return u.pathname.slice(1).split("/")[0] || null;
    }
    if (host === "youtube.com" || host === "m.youtube.com" || host === "music.youtube.com") {
      if (u.searchParams.get("v")) return u.searchParams.get("v");
      const parts = u.pathname.split("/").filter(Boolean); // ["shorts", "ID"] or ["embed", "ID"]
      if ((parts[0] === "shorts" || parts[0] === "embed" || parts[0] === "live") && parts[1]) {
        return parts[1];
      }
    }
  } catch (e) {
    return null;
  }
  return null;
}

// 유튜브 링크면 썸네일 이미지 URL을, 아니면 null을 반환합니다.
function getYoutubeThumbUrl(url) {
  const id = getYoutubeId(url);
  return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : null;
}

function showFormError(el, message) {
  el.textContent = message;
  el.classList.remove("hidden");
}

function clearFormError(el) {
  el.textContent = "";
  el.classList.add("hidden");
}
