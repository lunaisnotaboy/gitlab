import initIntegrationOverrides from '~/integrations/overrides';

document.addEventListener('DOMContentLoaded', () => {
  initIntegrationOverrides(document.querySelector('.js-vue-integration-overrides'));
});
