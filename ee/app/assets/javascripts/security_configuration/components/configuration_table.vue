<script>
import { GlLink, GlTable } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import FeatureStatus from './feature_status.vue';
import ManageFeature from './manage_feature.vue';

const borderClasses = 'gl-border-b-1! gl-border-b-solid! gl-border-gray-100!';
const thClass = `gl-text-gray-900 gl-bg-transparent! ${borderClasses}`;

export default {
  components: {
    GlLink,
    GlTable,
    FeatureStatus,
    ManageFeature,
  },
  props: {
    features: {
      type: Array,
      required: true,
    },
    autoDevopsEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    gitlabCiPresent: {
      type: Boolean,
      required: false,
      default: false,
    },
    gitlabCiHistoryPath: {
      type: String,
      required: false,
      default: '',
    },
  },
  methods: {
    getFeatureDocumentationLinkLabel(item) {
      return sprintf(s__('SecurityConfiguration|Feature documentation for %{featureName}'), {
        featureName: item.name,
      });
    },
  },
  fields: [
    {
      key: 'description',
      label: s__('SecurityConfiguration|Security Control'),
      thClass,
    },
    {
      key: 'status',
      label: s__('SecurityConfiguration|Status'),
      thClass,
    },
    {
      key: 'manage',
      label: s__('SecurityConfiguration|Manage'),
      thClass,
    },
  ],
};
</script>

<template>
  <gl-table
    :items="features"
    :fields="$options.fields"
    stacked="md"
    :tbody-tr-attr="{ 'data-testid': 'security-scanner-row' }"
  >
    <template #cell(description)="{ item }">
      <div class="gl-text-gray-900">{{ item.name }}</div>
      <div>
        {{ item.description }}
        <gl-link
          target="_blank"
          :href="item.helpPath"
          :aria-label="getFeatureDocumentationLinkLabel(item)"
        >
          {{ s__('SecurityConfiguration|More information') }}
        </gl-link>
      </div>
    </template>

    <template #cell(status)="{ item }">
      <feature-status
        :feature="item"
        :gitlab-ci-present="gitlabCiPresent"
        :gitlab-ci-history-path="gitlabCiHistoryPath"
        :data-qa-selector="`${item.type}_status`"
      />
    </template>

    <template #cell(manage)="{ item }">
      <manage-feature :feature="item" :auto-devops-enabled="autoDevopsEnabled" />
    </template>
  </gl-table>
</template>
