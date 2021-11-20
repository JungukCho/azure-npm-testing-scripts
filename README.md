This repository has some scripts to manually test network policy with conformance and cyclonus.

1. After creating docker container, go to `~/test` dir in the docker container. There are all scripts to run conformance and cyclonus tests.
```shell
# to create test docker container
./setup-docker-for-v2-npm-on-aks.sh aks-for-conformance.config e2e.test.vamsi v1.4.1  

# to delete created docker container
./clean-docker.sh aks-for-conformance.config
```
