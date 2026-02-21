import * as CookieConsent from "vanilla-cookieconsent";

const portalNameMeta = document.querySelector('meta[name="portal-name"]');
const privacyUrlMeta = document.querySelector('meta[name="privacy-policy-url"]');

const portalName = portalNameMeta?.content || "MatPortal";
const privacyUrl = privacyUrlMeta?.content || "/";

const resolveCookieDomain = () => {
  const host = window.location.hostname;
  if (host.endsWith(".stage.matportal.org")) {
    return ".stage.matportal.org";
  }
  if (host.endsWith(".matportal.org")) {
    return ".matportal.org";
  }
  return undefined;
};

const cookieDomain = resolveCookieDomain();

const setPortalCookie = (value) => {
  const maxAgeDays = 180;
  const maxAge = maxAgeDays * 24 * 60 * 60;
  const attributes = [
    `cookies_accepted=${value}`,
    `max-age=${maxAge}`,
    "path=/",
    "SameSite=Lax",
  ];

  if (cookieDomain) {
    attributes.push(`domain=${cookieDomain}`);
  }

  if (window.location.protocol === "https:") {
    attributes.push("Secure");
  }

  document.cookie = attributes.join("; ");
};

const syncAnalyticsConsent = () => {
  const accepted = CookieConsent.acceptedCategory("analytics");
  setPortalCookie(accepted ? "true" : "false");
  if (accepted) {
    window._paq = window._paq || [];
    window._paq.push(["rememberCookieConsentGiven"]);
  } else {
    window._paq = window._paq || [];
    window._paq.push(["forgetCookieConsentGiven"]);
  }
};

const buildTranslations = () => ({
  en: {
    consentModal: {
      title: "We use cookies",
      description: `${portalName} uses cookies to provide core features and improve the service. You can accept analytics cookies or manage your preferences.`,
      acceptAllBtn: "Accept all",
      acceptNecessaryBtn: "Reject optional",
      showPreferencesBtn: "Manage preferences",
    },
    preferencesModal: {
      title: "Cookie preferences",
      acceptAllBtn: "Accept all",
      acceptNecessaryBtn: "Reject optional",
      savePreferencesBtn: "Save preferences",
      closeIconLabel: "Close",
      sections: [
        {
          title: "Essential",
          description: "Required for the site to function and cannot be switched off.",
          linkedCategory: "necessary",
        },
        {
          title: "Analytics",
          description: "Helps us understand usage and improve MatPortal.",
          linkedCategory: "analytics",
        },
        {
          title: "More information",
          description: `Read our <a href=\"${privacyUrl}\" target=\"_blank\" rel=\"noopener\">privacy policy</a>.`,
        },
      ],
    },
  },
  fr: {
    consentModal: {
      title: "Nous utilisons des cookies",
      description: `${portalName} utilise des cookies pour fournir les fonctionnalités de base et améliorer le service. Vous pouvez accepter les cookies d'analyse ou gérer vos préférences.`,
      acceptAllBtn: "Tout accepter",
      acceptNecessaryBtn: "Refuser les optionnels",
      showPreferencesBtn: "Gérer les préférences",
    },
    preferencesModal: {
      title: "Préférences de cookies",
      acceptAllBtn: "Tout accepter",
      acceptNecessaryBtn: "Refuser les optionnels",
      savePreferencesBtn: "Enregistrer",
      closeIconLabel: "Fermer",
      sections: [
        {
          title: "Essentiels",
          description: "Nécessaires au fonctionnement du site et ne peuvent pas être désactivés.",
          linkedCategory: "necessary",
        },
        {
          title: "Analyse",
          description: "Nous aide à comprendre l'usage et à améliorer MatPortal.",
          linkedCategory: "analytics",
        },
        {
          title: "Plus d'informations",
          description: `Consultez notre <a href=\"${privacyUrl}\" target=\"_blank\" rel=\"noopener\">politique de confidentialité</a>.`,
        },
      ],
    },
  },
  de: {
    consentModal: {
      title: "Wir verwenden Cookies",
      description: `${portalName} verwendet Cookies, um grundlegende Funktionen bereitzustellen und den Dienst zu verbessern. Sie können Analyse-Cookies akzeptieren oder Ihre Einstellungen verwalten.`,
      acceptAllBtn: "Alle akzeptieren",
      acceptNecessaryBtn: "Optionale ablehnen",
      showPreferencesBtn: "Einstellungen verwalten",
    },
    preferencesModal: {
      title: "Cookie-Einstellungen",
      acceptAllBtn: "Alle akzeptieren",
      acceptNecessaryBtn: "Optionale ablehnen",
      savePreferencesBtn: "Einstellungen speichern",
      closeIconLabel: "Schließen",
      sections: [
        {
          title: "Essentiell",
          description: "Erforderlich für den Betrieb der Website und kann nicht deaktiviert werden.",
          linkedCategory: "necessary",
        },
        {
          title: "Analyse",
          description: "Hilft uns, die Nutzung zu verstehen und MatPortal zu verbessern.",
          linkedCategory: "analytics",
        },
        {
          title: "Weitere Informationen",
          description: `Lesen Sie unsere <a href=\"${privacyUrl}\" target=\"_blank\" rel=\"noopener\">Datenschutzerklärung</a>.`,
        },
      ],
    },
  },
});

const initCookieConsent = () => {

  const lang = (document.documentElement.lang || "en").toLowerCase();
  const translations = buildTranslations();
  const resolvedLang = translations[lang] ? lang : "en";
  const cookieConfig = {
    name: "matportal_cookie_consent",
    path: "/",
    sameSite: "Lax",
  };

  if (cookieDomain) {
    cookieConfig.domain = cookieDomain;
  }

  CookieConsent.run({
    cookie: cookieConfig,
    categories: {
      necessary: {
        readOnly: true,
      },
      analytics: {},
    },
    guiOptions: {
      consentModal: {
        layout: "box",
        position: "bottom right",
        equalWeightButtons: true,
      },
      preferencesModal: {
        layout: "box",
        position: "right",
      },
    },
    language: {
      default: resolvedLang,
      translations,
    },
    onConsent: () => {
      syncAnalyticsConsent();
    },
    onChange: () => {
      syncAnalyticsConsent();
    },
  });

  syncAnalyticsConsent();
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initCookieConsent);
} else {
  initCookieConsent();
}

document.addEventListener("turbo:load", initCookieConsent);
