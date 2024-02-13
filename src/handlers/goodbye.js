'use strict';

module.exports.sayGoodbye = async function (context, req) {
  context.log('JavaScript HTTP trigger function processed a request.');

  if (req.query.name || (req.body && req.body.name)) {
    context.res = {
      body: 'Goodbye ' + (req.query.name || req.body.name),
    };
  } else {
    context.res = {
      status: 400,
      body: 'Please pass a name on the query string or in the request body',
    };
  }
};
