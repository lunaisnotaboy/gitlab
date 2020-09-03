<script>
import { GlTable } from '@gitlab/ui';
import { __ } from '~/locale';
import axios from '~/lib/utils/axios_utils';

export default {
  name: 'IntegrationOverrides',
  components: {
    GlTable,
  },
  props: {
    endpoint: {
      type: String,
      required: true,
    },
  },
  fields: [
    {
      key: 'project_name',
      label: __('Project'),
    },
    {
      key: 'actions',
      label: '',
    },
  ],
  data() {
    return {
      overrides: [],
    };
  },
  async created() {
    this.overrides = await this.getOverrides();
  },
  methods: {
    getOverrides() {
      return axios.get(this.endpoint).then(res => res.data);
      // .catch(() => flash(__('An error occurred while loading data')));;
    },
  },
};
</script>

<template>
  <div>
    <gl-table :items="overrides" :fields="$options.fields">
      <template #cell(project_name)="{ item }">
        {{ item.name }}
      </template>
    </gl-table>
  </div>
</template>
