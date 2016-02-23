#cfml-redlock

A loose cf port of the callback implementation of https://github.com/mike-marcacci/node-redlock which is the node implementation of http://redis.io/topics/distlock
 
## How to run the tests
 
1. Download testbox from: http://www.ortussolutions.com/products/testbox
2. Unzip the testbox/ folder into the root of the application (as a peer to tests)
3. The tests expect a redis instance to be running on localhost:6379, edit the top of /tests/basicTest.cfc if your instance is different
3. run /tests/?opt_run=true

Note: some of the tests have a leeway factor to handle the time of CF doing the actions in the callbacks, you may need to expand those values if your system is slower.



## License

This software is licensed under the Apache 2 license, quoted below.

Copyright 2016 MotorsportReg
Copyright 2016 Ryan Guill <ryanguill@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations under
the License.