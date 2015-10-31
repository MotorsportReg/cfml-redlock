#cfml-redlock

A loose cf port of the callback implementation of https://github.com/mike-marcacci/node-redlock which is the node implementation of http://redis.io/topics/distlock
 
## How to run the tests
 
1. Download testbox from: http://www.ortussolutions.com/products/testbox
2. Unzip the testbox/ folder into the root of the application (as a peer to tests)
3. The tests expect a redis instance to be running on localhost:6379, edit the top of /tests/basicTest.cfc if your instance is different
3. run /tests/?opt_run=true

Note: some of the tests have a leeway factor to handle the time of CF doing the actions in the callbacks, you may need to expand those values if your system is slower.


