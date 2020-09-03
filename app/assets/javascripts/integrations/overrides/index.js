import Vue from 'vue';
import Overrides from './components/overrides.vue';

export default el => {
  if (!el) {
    return null;
  }

  const { endpoint } = el.dataset;

  return new Vue({
    el,
    render(createElement) {
      return createElement(Overrides, {
        props: {
          endpoint,
        },
      });
    },
  });
};
