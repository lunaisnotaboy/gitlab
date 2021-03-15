<script>
import { GlFormCheckbox, GlFormGroup } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import DynamicFields from '../../components/dynamic_fields.vue';
import { isValidAnalyzerEntity } from '../../components/utils';

export default {
  components: {
    GlFormGroup,
    GlFormCheckbox,
    DynamicFields,
  },
  mixins: [glFeatureFlagsMixin()],
  model: {
    prop: 'entity',
    event: 'input',
  },
  props: {
    // SastCiConfigurationAnalyzersEntity from GraphQL endpoint
    entity: {
      type: Object,
      required: true,
      validator: isValidAnalyzerEntity,
    },
  },
  computed: {
    variables() {
      return this.entity.variables?.nodes ?? [];
    },
    hasVariables() {
      return this.variables.length > 0;
    },
  },
  methods: {
    onToggle(enabled) {
      const entity = { ...this.entity, enabled };
      this.$emit('input', entity);
    },
    onVariablesUpdate(variables) {
      const entity = { ...this.entity, variables: { nodes: variables } };
      this.$emit('input', entity);
    },
  },
};
</script>

<template>
  <gl-form-group>
    <gl-form-checkbox
      :id="entity.name"
      :checked="entity.enabled"
      :data-qa-selector="`${entity.name}_checkbox`"
      @input="onToggle"
    >
      <span class="gl-font-weight-bold">{{ entity.label }}</span>
      <span v-if="entity.description" class="gl-text-gray-500">({{ entity.description }})</span>
    </gl-form-checkbox>

    <dynamic-fields
      v-if="hasVariables"
      :disabled="!entity.enabled"
      class="gl-ml-6 gl-mb-0"
      :entities="variables"
      @input="onVariablesUpdate"
    />
  </gl-form-group>
</template>
