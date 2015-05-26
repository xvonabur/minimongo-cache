'use strict';

var _ = require('lodash');

function ObservableQuery(db, func, context) {
  this.db = db;
  this.func = func;
  this.context = context;

  this.lastReadTransaction = null;
  this.lastValue = null;
  this.subscribers = [];
  this.changeListener = this.changeListener.bind(this);

  this.db.on('change', this.changeListener);
  this.rerunTransaction();
}

ObservableQuery.prototype.subscribe = function(cb) {
  this.subscribers.push(cb);
  cb(this.lastValue);
};

ObservableQuery.prototype.dispose = function() {
  this.db.removeListener(this.changeListener);
};

ObservableQuery.prototype.rerunTransaction = function() {
  var rv = this.db.read(this.func, this.context);

  // If we read different data this time, notify of a change. This saves render() time
  var nextReadTransaction = rv.transaction;
  if (!this.lastReadTransaction ||
      !_.isEqual(this.lastReadTransaction.log, nextReadTransaction.log)) {
    this.lastReadTransaction = nextReadTransaction;
    this.lastValue = rv.value;

    this.subscribers.forEach(function(cb) {
      cb(this.lastValue);
    }, this);
  }
};

ObservableQuery.prototype.changeListener = function(changeRecords) {
  // If none of the data we read last time changed, don't rerun the transaction. This
  // saves query time.

  // Have we run the query before?
  if (!this.lastReadTransaction) {
    this.rerunTransaction();
    return;
  }

  for (var collectionName in changeRecords) {
    // Did we scan the collection?
    if (this.lastReadTransaction.dirtyScans[collectionName]) {
      this.rerunTransaction();
      return;
    }

    // Did we change this particular ID? (fine-grained for gets)
    var documentFragments = changeRecords[collectionName];
    for (var i = 0; i < documentFragments.length; i++) {
      var documentFragment = documentFragments[i];
      if (this.lastReadTransaction.dirtyIds[collectionName][documentFragment._id]) {
        this.rerunTransaction();
        return;
      }
    }
  }
};

var WithObservableQueries = {
  observe: function(func, context) {
    return new ObservableQuery(this, func, context);
  },
};

module.exports = WithObservableQueries;
