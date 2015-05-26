'use strict';

function emptyFunction() {}

var WithCreateQuery = {
  createQuery: function(spec) {
    if (!spec.hasOwnProperty('read')) {
      throw new Error('spec requires a read key');
    }
    spec.fetchIfNeeded = spec.fetchIfNeeded || emptyFunction;

    return function(args) {
      var thisObj = {
        args: args,
      };

      var result = spec.read.call(thisObj, this);
      spec.fetchIfNeeded.call(thisObj, this, result);

      return this.read(function(db) {
        return spec.read.call(thisObj, db);
      });
    }.bind(this);
  },
};

module.exports = WithCreateQuery;
