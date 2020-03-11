import { shallowMount } from '@vue/test-utils';
import MockAdapter from 'axios-mock-adapter';
import { TEST_HOST } from 'helpers/test_constants';

import PaginationLinks from '~/vue_shared/components/pagination_links.vue';
import SecurityDashboardApp from 'ee/security_dashboard/components/app.vue';
import Filters from 'ee/security_dashboard/components/filters.vue';
import SecurityDashboardTable from 'ee/security_dashboard/components/security_dashboard_table.vue';
import VulnerabilityChart from 'ee/security_dashboard/components/vulnerability_chart.vue';
import VulnerabilityCountList from 'ee/security_dashboard/components/vulnerability_count_list.vue';
import VulnerabilitySeverity from 'ee/security_dashboard/components/vulnerability_severity.vue';
import LoadingError from 'ee/security_dashboard/components/loading_error.vue';
import VulnerabilityList from 'ee/vulnerabilities/components/vulnerability_list.vue';

import createStore from 'ee/security_dashboard/store';
import { DASHBOARD_TYPES } from 'ee/security_dashboard/store/constants';
import { getParameterValues } from '~/lib/utils/url_utility';
import axios from '~/lib/utils/axios_utils';

const pipelineId = 123;
const vulnerabilitiesEndpoint = `${TEST_HOST}/vulnerabilities`;
const vulnerabilitiesCountEndpoint = `${TEST_HOST}/vulnerabilities_summary`;
const vulnerabilitiesHistoryEndpoint = `${TEST_HOST}/vulnerabilities_history`;
const vulnerableProjectsEndpoint = `${TEST_HOST}/vulnerable_projects`;

jest.mock('~/lib/utils/url_utility', () => ({
  getParameterValues: jest.fn().mockReturnValue([]),
}));

describe('Security Dashboard app', () => {
  let wrapper;
  let mock;
  let lockFilterSpy;
  let setPipelineIdSpy;
  let store;

  const setup = () => {
    mock = new MockAdapter(axios);
    lockFilterSpy = jest.fn();
    setPipelineIdSpy = jest.fn();
  };

  const createComponent = ({ props, options } = {}) => {
    store = createStore();
    wrapper = shallowMount(SecurityDashboardApp, {
      store,
      methods: {
        lockFilter: lockFilterSpy,
        setPipelineId: setPipelineIdSpy,
      },
      propsData: {
        dashboardDocumentation: '',
        vulnerabilitiesEndpoint,
        vulnerabilitiesCountEndpoint,
        vulnerabilitiesHistoryEndpoint,
        vulnerableProjectsEndpoint,
        pipelineId,
        vulnerabilityFeedbackHelpPath: `${TEST_HOST}/vulnerabilities_feedback_help`,
        ...props,
      },
      ...options,
    });
  };

  afterEach(() => {
    wrapper.destroy();
    mock.restore();
  });

  describe('default', () => {
    beforeEach(() => {
      setup();
      createComponent();
    });

    it('renders the filters', () => {
      expect(wrapper.find(Filters).exists()).toBe(true);
    });

    it('renders the security dashboard table ', () => {
      expect(wrapper.find(SecurityDashboardTable).exists()).toBe(true);
    });

    it('renders the vulnerability chart', () => {
      expect(wrapper.find(VulnerabilityChart).exists()).toBe(true);
    });

    it('does not render the vulnerability count list', () => {
      expect(wrapper.find(VulnerabilityCountList).exists()).toBe(false);
    });

    it('does not render the vulnerability list', () => {
      expect(wrapper.find(VulnerabilityList).exists()).toBe(false);
    });

    it('does not lock to a project', () => {
      expect(wrapper.vm.isLockedToProject).toBe(false);
    });

    it('does not lock project filters', () => {
      expect(lockFilterSpy).not.toHaveBeenCalled();
    });

    it('sets the pipeline id', () => {
      expect(setPipelineIdSpy).toHaveBeenCalledWith(pipelineId);
    });

    describe('when the total number of vulnerabilities change', () => {
      const newCount = 3;

      beforeEach(() => {
        store.state.vulnerabilities.pageInfo = { total: newCount };
      });

      it('emits a vulnerabilitiesCountChanged event', () => {
        expect(wrapper.emitted('vulnerabilitiesCountChanged')).toEqual([[newCount]]);
      });
    });
  });

  describe('with project lock', () => {
    const project = {
      id: 123,
    };
    beforeEach(() => {
      setup();
      createComponent({
        props: {
          lockToProject: project,
        },
      });
    });

    it('renders the vulnerability count list', () => {
      expect(wrapper.find(VulnerabilityCountList).exists()).toBe(true);
    });

    it('locks to a given project', () => {
      expect(wrapper.vm.isLockedToProject).toBe(true);
    });

    it('locks the filters to a given project', () => {
      expect(lockFilterSpy).toHaveBeenCalledWith({
        filterId: 'project_id',
        optionId: project.id,
      });
    });
  });

  describe.each`
    endpointProp                        | Component
    ${'vulnerabilitiesCountEndpoint'}   | ${VulnerabilityCountList}
    ${'vulnerabilitiesHistoryEndpoint'} | ${VulnerabilityChart}
    ${'vulnerableProjectsEndpoint'}     | ${VulnerabilitySeverity}
  `('with an empty $endpointProp', ({ endpointProp, Component }) => {
    beforeEach(() => {
      setup();
      createComponent({
        props: {
          [endpointProp]: '',
        },
      });
    });

    it(`does not show the ${Component.name}`, () => {
      expect(wrapper.find(Component).exists()).toBe(false);
    });
  });

  describe('dismissed vulnerabilities', () => {
    beforeEach(() => {
      setup();
    });

    it.each`
      description                                                        | getParameterValuesReturnValue | expected
      ${'hides dismissed vulnerabilities by default'}                    | ${[]}                         | ${true}
      ${'shows dismissed vulnerabilities if scope param is "all"'}       | ${['all']}                    | ${false}
      ${'hides dismissed vulnerabilities if scope param is "dismissed"'} | ${['dismissed']}              | ${true}
    `('$description', ({ getParameterValuesReturnValue, expected }) => {
      getParameterValues.mockImplementation(() => getParameterValuesReturnValue);
      createComponent();
      expect(store.state.filters.hideDismissed).toBe(expected);
    });
  });

  describe('on error', () => {
    beforeEach(() => {
      setup();
      createComponent();
    });

    it.each([401, 403])('displays an error on error %s', errorCode => {
      store.dispatch('vulnerabilities/receiveVulnerabilitiesError', errorCode);
      return wrapper.vm.$nextTick().then(() => {
        expect(wrapper.find(LoadingError).exists()).toBe(true);
      });
    });

    it.each([404, 500])('does not display an error on error %s', errorCode => {
      store.dispatch('vulnerabilities/receiveVulnerabilitiesError', errorCode);
      return wrapper.vm.$nextTick().then(() => {
        expect(wrapper.find(LoadingError).exists()).toBe(false);
      });
    });
  });

  describe('with the first_class_vulnerabilities feature flag turned on', () => {
    beforeEach(() => {
      setup();
      createComponent({
        options: {
          provide: {
            glFeatures: { firstClassVulnerabilities: true },
          },
        },
      });
    });

    describe.each`
      dashboardType               | showVulnerabilityList
      ${DASHBOARD_TYPES.PIPELINE} | ${false}
      ${DASHBOARD_TYPES.PROJECT}  | ${true}
      ${DASHBOARD_TYPES.GROUP}    | ${true}
      ${DASHBOARD_TYPES.INSTANCE} | ${true}
    `('with a dashboard type of $dashboardType', ({ dashboardType, showVulnerabilityList }) => {
      beforeEach(() => {
        store.state.dashboardType = dashboardType;
      });

      it(`should ${showVulnerabilityList ? '' : 'not '}show the vulnerability`, () => {
        expect(wrapper.find(VulnerabilityList).exists()).toEqual(showVulnerabilityList);
      });
    });

    describe('on the project dashboard', () => {
      beforeEach(() => {
        store.state.dashboardType = DASHBOARD_TYPES.PROJECT;
      });

      it('should not render the pagination', () => {
        expect(wrapper.find(PaginationLinks).exists()).toEqual(false);
      });

      it('should pass the vulnerabilities to the vulnerability list', () => {
        expect(wrapper.find(VulnerabilityList).props().vulnerabilities).toEqual(
          store.state.vulnerabilities.vulnerabilities,
        );
      });

      it('should pass the loading state to the vulnerability list', () => {
        expect(wrapper.find(VulnerabilityList).props().isLoading).toEqual(
          store.state.vulnerabilities.isLoadingVulnerabilities,
        );
      });

      describe('with more than one page of vulnerabilities', () => {
        beforeEach(() => {
          store.state.vulnerabilities.pageInfo = { total: 2 };
        });

        it('should render the pagination', () => {
          expect(wrapper.find(PaginationLinks).exists()).toEqual(true);
        });
      });
    });
  });
});
