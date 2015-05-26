'use strict';

function emptyFunction() {}

var WithCreateQuery = {
  createQuery: function(spec) {
    if (!spec.hasOwnProperty('read')) {
      throw new Error('spec requires a read key');
    }
    spec.fetchIfNeeded = spec.fetchIfNeeded || emptyFunction;

    function Query(args) {
      this.args = args;
    }

    for (var name in spec) {
      Query.prototype[name] = spec[name];
    }

    return function(args) {
      var thisObj = new Query(args);
      var result = thisObj.read(this);
      thisObj.fetchIfNeeded(this, result);

      return this.read(function(db) {
        return thisObj.read(db);
      });
    }.bind(this);
  },
};

module.exports = WithCreateQuery;
