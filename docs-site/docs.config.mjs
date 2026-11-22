import { defineDocsConfig, MissingTranslation, NavIcon } from '@velezanthony/design/integration';

/* La documentación sigue en `docs/`, como con MkDocs: este proyecto solo la publica.
   Inglés por defecto y español por sufijo (`index.es.md`). No todo está traducido a propósito:
   lo que falta se sirve en inglés con un aviso, igual que `fallback_to_default` en MkDocs. */
export default defineDocsConfig({
  site: {
    name: 'Docker Control Center',
    // El «◐» que `dcc dash` pinta para un stack a medio levantar.
    favicon: 'logo.svg',
    social: { github: 'https://github.com/velezanthony/docker-control-center' },
    footer: { license: { label: 'MIT', href: 'https://github.com/velezanthony/docker-control-center/blob/main/LICENSE' } },
    seo: {
      description: {
        en: 'Docker Control Center documentation: a Docker dashboard for the terminal in Bash and make, with no daemon and nothing to install.',
        es: 'Documentación de Docker Control Center: un panel de Docker para la terminal en Bash y make, sin daemon y sin nada que instalar.',
      },
      image: {
        src: '/og.png',
        alt: {
          en: 'Docker Control Center logo, a half-filled cyan ring, next to the tagline: a Docker dashboard for the terminal',
          es: 'Logo de Docker Control Center, un anillo cian medio relleno, junto al lema: un panel de Docker para la terminal',
        },
      },
      ogLocales: { en: 'en_GB', es: 'es_ES' },
      schema: [
        {
          '@type': 'SoftwareSourceCode',
          name: 'Docker Control Center',
          description: 'A Docker dashboard for the terminal. Bash and make, no daemon, nothing resident.',
          url: 'https://velezanthony.github.io/docker-control-center/',
          codeRepository: 'https://github.com/velezanthony/docker-control-center',
          programmingLanguage: ['Bash', 'Makefile'],
          runtimePlatform: 'Linux',
          license: 'https://opensource.org/licenses/MIT',
          sameAs: ['https://github.com/velezanthony/docker-control-center'],
          author: {
            '@type': 'Person',
            '@id': 'https://velezanthony.github.io/#anthony',
            name: 'Anthony Velez Tapia',
            url: 'https://velezanthony.github.io/',
          },
        },
      ],
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
