import { defineDocsSite } from '@velezanthony/design/integration';
import docsConfig from './docs.config.mjs';

/* Página de proyecto de GitHub Pages: https://velezanthony.github.io/docker-control-center/ */
export default defineDocsSite(docsConfig, {
  base: '/docker-control-center',
  site: 'https://velezanthony.github.io',
});
