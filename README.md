# [Umee](https://www.umee.cc/) [Peggo](https://github.com/umee-network/peggo) [Exporter](https://prometheus.io/docs/instrumenting/exporters/)

* If you don't know what is all about, words above are clickable ^^

This is proof of concept [peggo](https://github.com/umee-network/peggo) metrics collection script which return valid [prometheus](https://prometheus.io/) format.

This was initial research we been doing on cluster health condition, this all eventually grow in to bigger project [PEGGO.INFO](https://peggo.info/)

However, provided script can be a good start for monitoring peggo orchestrator or just as educational material.

#### Completed:

* full peggo statistics which include all bonded validators
* individual metrics for specified validator
* general cluster statistic
* exporter health
* RPC health
* collecded data primitive checks

#### To do:

* all checks are primitive, need to write proper checks
* no actual exporter integration, documentation need to be improved
* no JSON checks _( this is critical for prod )_
* some falure points need to be handled properly

Script *is not yet* production ready, but can be shaped in relatively short period of time. 

Repository contain example of this script output: [example.metrics.txt](https://github.com/matsuro-hadouken/umee-peggo-exporter/blob/main/example.metrics.txt)

PEGGO HEALTH CAN BE OBSERVED HERE: [PEGGO.INFO](https://peggo.info/)
