import Vue from 'vue';
import vueResource from 'vue-resource';

Vue.use(vueResource);

class RelatedIssuesService {
  constructor(endpoint) {
    this.relatedIssuesResource = Vue.resource(endpoint);
  }

  static fetchIssueInfo(endpoint) {
    const issueResource = Vue.resource(endpoint);
    return issueResource.get()
      .then((res) => {
        const issue = res.json();
        if (!issue) {
          throw new Error('Response didn\'t return any issue data');
        }

        return issue;
      });
  }

  fetchRelatedIssues() {
    return this.relatedIssuesResource.get()
      .then((res) => {
        const issues = res.json();
        if (!issues) {
          throw new Error('Response didn\'t return any issues data');
        }

        return issues;
      });
  }

  addRelatedIssues(newIssueReferences) {
    return this.relatedIssuesResource.save({}, {
      issue_references: newIssueReferences,
    })
      .then((res) => {
        const resData = res.json();
        if (!resData) {
          throw new Error('Response didn\'t return any data');
        }

        return resData;
      });
  }

  static removeRelatedIssue(endpoint) {
    const relatedIssueResource = Vue.resource(endpoint);
    return relatedIssueResource.remove()
      .then((res) => {
        const resData = res.json();
        if (!resData) {
          throw new Error('Response didn\'t return any data');
        }

        return resData;
      });
  }
}
RelatedIssuesService.FETCHING_STATUS = 'FETCHING';

export default RelatedIssuesService;
