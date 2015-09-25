'use strict';

var _ = require('lodash');
var invariant = require('invariant');

function defaultDefault() {
  return null;
}

function defaultIdentity() {
  return JSON.stringify(Array.prototype.slice.call(arguments));
}

var WithServerQuery = {
  createServerQuery: function(spec) {
    spec = _.clone(spec);
    spec.default = spec.default || defaultDefault;
    spec.identity = spec.identity || defaultIdentity;

    invariant(typeof spec.fetch === 'function', 'Forgot a fetch() function');
    invariant(typeof spec.update === 'function', 'Forgot an update() functino');
    invariant(typeof spec.query === 'function', 'Forgot a query() function');
    invariant(typeof spec.default === 'function', 'Forgot a default() function');
    invariant(typeof spec.identity === 'function', 'Forgot a key() function');

    var locks = {};

    return function() {
      invariant(typeof this.fetch === 'function', 'You did not injectFetcher() yet');

      var args = Array.prototype.slice.call(arguments);
      var result = spec.query.apply(this, arguments);

      if (result === null) {
        // Cache is empty

        var identity = spec.identity.apply(this, arguments);

        if (!locks[identity]) {
          // No pending fetch for this data.
          locks[identity] = true;
          this.fetch(spec.fetch.apply(this, arguments), function(err, body) {
            try {
              spec.update.apply(this, args.concat([err, body]));
            } finally {
              delete locks[identity];
            }
          });
        }

        return spec.default.apply(this, arguments);
      } else {
        return result;
      }
    }.bind(this);
  },

  injectFetcher: function(fetch) {
    invariant(!this.fetch, 'You may only call injectFetcher() once');
    this.fetch = fetch;
  },
};

module.exports = WithServerQuery;
