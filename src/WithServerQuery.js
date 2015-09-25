'use strict';

var _ = require('lodash');
var invariant = require('invariant');

function defaultIdentity() {
  return JSON.stringify(Array.prototype.slice.call(arguments));
}

var WithServerQuery = {
  createServerQuery: function(spec) {
    spec = _.clone(spec);
    spec.identity = spec.identity || defaultIdentity;

    invariant(typeof spec.fetch === 'function', 'Forgot a fetch() function');
    invariant(typeof spec.update === 'function', 'Forgot an update() functino');
    invariant(typeof spec.query === 'function', 'Forgot a query() function');
    invariant(typeof spec.identity === 'function', 'Forgot a key() function');

    var locks = {};

    return function() {
      invariant(typeof this.fetch === 'function', 'You did not injectFetcher() yet');

      var args = Array.prototype.slice.call(arguments);
      var result = spec.query.apply(this, arguments);

      invariant(
        typeof result === 'object' &&
          result &&
          typeof result.needsFetch === 'boolean' &&
          result.hasOwnProperty('result'),
        'query() must return an object with needsFetch and result fields'
      );

      if (result.needsFetch) {
        // Cache is empty

        var identity = spec.identity.apply(this, arguments);

        if (!locks[identity]) {
          // No pending fetch for this data.
          locks[identity] = true;
          this.fetch(spec.fetch.apply(this, args.concat([result.result])), function(err, body) {
            try {
              spec.update.apply(this, args.concat([result.result, err, body]));
            } finally {
              delete locks[identity];
            }
          });
        }

        return result.result;
      } else {
        return result.result;
      }
    }.bind(this);
  },

  injectFetcher: function(fetch) {
    invariant(!this.fetch, 'You may only call injectFetcher() once');
    this.fetch = fetch;
  },
};

module.exports = WithServerQuery;
