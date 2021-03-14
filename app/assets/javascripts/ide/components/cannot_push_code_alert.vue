<script>
import { GlAlert, GlButton } from '@gitlab/ui';

export default {
  components: {
    GlAlert,
    GlButton,
  },
  props: {
    message: {
      type: String,
      required: true,
    },
    action: {
      type: Object,
      required: false,
      default: null,
    },
  },
  computed: {
    hasAction() {
      return Boolean(this.action?.href);
    },
  },
};
</script>

<template>
  <gl-alert :dismissible="false">
    {{ message }}
    <template v-if="hasAction" #actions>
      <gl-button variant="confirm" :href="action.href" :data-method="action.isForm ? 'post' : null">
        {{ action.text }}
      </gl-button>
    </template>
  </gl-alert>
</template>
