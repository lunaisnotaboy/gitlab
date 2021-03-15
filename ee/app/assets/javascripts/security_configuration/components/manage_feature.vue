<script>
import { GlButton } from '@gitlab/ui';

export default {
  components: {
    GlButton,
  },
  props: {
    feature: {
      type: Object,
      required: true,
    },
    autoDevopsEnabled: {
      type: Boolean,
      required: true,
    },
  },
  computed: {
    canConfigureFeature() {
      return Boolean(this.feature.configuration_path);
    },
    canManageProfiles() {
      return this.feature.type === 'dast_profiles';
    },
  },
};
</script>

<template>
  <gl-button
    v-if="canManageProfiles"
    :href="feature.configuration_path"
    data-testid="manageButton"
    >{{ s__('SecurityConfiguration|Manage') }}</gl-button
  >

  <gl-button
    v-else-if="canConfigureFeature && feature.configured"
    :href="feature.configuration_path"
    data-testid="configureButton"
    >{{ s__('SecurityConfiguration|Configure') }}</gl-button
  >

  <gl-button
    v-else-if="canConfigureFeature"
    variant="success"
    category="primary"
    :href="feature.configuration_path"
    data-testid="enableButton"
    :data-qa-selector="`${feature.type}_enable_button`"
    >{{ s__('SecurityConfiguration|Enable') }}</gl-button
  >
</template>
