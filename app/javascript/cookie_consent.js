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

const normalizeLang = (value) => {
  if (!value) return "";
  return value.toLowerCase().split(/[-_]/)[0];
};

const getCookieValue = (name) => {
  const match = document.cookie.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : "";
};

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
  it: {
    consentModal: {
      title: "Usiamo i cookie",
      description: `${portalName} utilizza i cookie per fornire le funzionalità di base e migliorare il servizio. Puoi accettare i cookie di analisi o gestire le tue preferenze.`,
      acceptAllBtn: "Accetta tutti",
      acceptNecessaryBtn: "Rifiuta opzionali",
      showPreferencesBtn: "Gestisci preferenze",
    },
    preferencesModal: {
      title: "Preferenze cookie",
      acceptAllBtn: "Accetta tutti",
      acceptNecessaryBtn: "Rifiuta opzionali",
      savePreferencesBtn: "Salva preferenze",
      closeIconLabel: "Chiudi",
      sections: [
        {
          title: "Essenziali",
          description: "Necessari per il funzionamento del sito e non possono essere disattivati.",
          linkedCategory: "necessary",
        },
        {
          title: "Analisi",
          description: "Ci aiutano a capire l'utilizzo e a migliorare MatPortal.",
          linkedCategory: "analytics",
        },
        {
          title: "Ulteriori informazioni",
          description: `Leggi la nostra <a href=\"${privacyUrl}\" target=\"_blank\" rel=\"noopener\">informativa sulla privacy</a>.`,
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
  const translations = buildTranslations();
  const htmlLang = normalizeLang(document.documentElement.lang || "en");
  const cookieLang = normalizeLang(getCookieValue("locale"));
  const resolvedLang = translations[htmlLang]
    ? htmlLang
    : translations[cookieLang]
      ? cookieLang
      : "en";
  if (window.__matportalCookieConsentInitialized) {
    CookieConsent.setLanguage(resolvedLang);
    syncAnalyticsConsent();
    return;
  }

  window.__matportalCookieConsentInitialized = true;
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
