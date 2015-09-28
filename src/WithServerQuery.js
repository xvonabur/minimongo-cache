'use strict';

var _ = require('lodash');
var invariant = require('invariant');

function defaultIdentity() {
  return JSON.stringify(Array.prototype.slice.call(arguments));
}

function defaultProcess(result) {
  return {
    result: result.result,
    loading: result.needsFetch,
  };
}

var WithServerQuery = {
  createServerQuery: function(spec) {
    spec = _.clone(spec);
    spec.identity = spec.identity || defaultIdentity;
    spec.process = spec.process || defaultProcess;

    // These need better names
    invariant(typeof spec.fetch === 'function', 'Forgot a fetch() function');
    invariant(typeof spec.update === 'function', 'Forgot an update() functino');
    invariant(typeof spec.query === 'function', 'Forgot a query() function');
    invariant(typeof spec.identity === 'function', 'Forgot an identity() function');
    invariant(typeof spec.process === 'function', 'Forgot a process() function');

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
          process.nextTick(function() {
            // Run in next tick to avoid synchronous callback race conditions and get fetch() out of the
            // ObservableRead transaction.
            this.fetch(spec.fetch.apply(this, args.concat([result.result])), function(err, body) {
              try {
                spec.update.apply(this, args.concat([err, body, result.result]));
              } finally {
                delete locks[identity];
              }
            });
          }.bind(this));
        }
      }

      return spec.process.call(this, result);
    }.bind(this);
  },

  injectFetcher: function(fetch) {
    invariant(!this.fetch, 'You may only call injectFetcher() once');
    this.fetch = fetch;
  },
};

module.exports = WithServerQuery;
