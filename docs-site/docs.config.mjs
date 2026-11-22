import { defineDocsConfig, MissingTranslation, NavIcon } from '@velezanthony/design/integration';

/* La documentación sigue en `docs/`, como con MkDocs: este proyecto solo la publica.
   Inglés por defecto y español por sufijo (`index.es.md`). No todo está traducido a propósito:
   lo que falta se sirve en inglés con un aviso, igual que `fallback_to_default` en MkDocs. */
export default defineDocsConfig({
  site: {
    name: 'Docker Control Center',
    social: { github: 'https://github.com/velezanthony/docker-control-center' },
    footer: { license: { label: 'MIT', href: 'https://github.com/velezanthony/docker-control-center/blob/main/LICENSE' } },
    seo: {
      description: {
        en: 'A Docker dashboard for the terminal. Bash and make, nothing resident.',
        es: 'Un panel de control de Docker para la terminal. Bash y make, nada residente.',
      },
      ogLocales: { en: 'en_GB', es: 'es_ES' },
    },
  },
  i18n: { locales: ['en', 'es'], defaultLocale: 'en', missing: MissingTranslation.FALLBACK },
  content: {
    dir: '../docs',
    repoRoot: '..',
    editUrl: 'https://github.com/velezanthony/docker-control-center/edit/main',
    nav: [
      { label: { en: 'Home', es: 'Inicio' }, slug: 'index' },
      {
        label: { en: 'Using it', es: 'Usarlo' },
        dir: 'users',
        sidebar: ['users/installation', 'users/commands', 'users/language'],
      },
      {
        label: { en: 'Contributing', es: 'Contribuir' },
        dir: 'contributors',
        sidebar: ['contributors/engineering'],
      },
      { label: 'GitHub', href: 'https://github.com/velezanthony/docker-control-center', icon: NavIcon.GITHUB },
    ],
  },
});
