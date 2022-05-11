# CoreDNS domain forwards in Openshift

This repository tries to collect the information and resources required to create a domain zone DNS forward in Openshift's CoreDNS in order to test this integration between DNS servers.

## Create Container Image

First of all, it is required an "external" DNS that accepts the request forwarded by the Openshift's CoreDNS. In order to create this container image based on BIND9, it is required to follow the next procedure:

- Build a new container image

```$bash
podman build . -t bind9:acidonpe
```

- Push the new image to a public image registry in order to access to it externally

```$bash
podman tag bind9:acidonpe quay.io/acidonpe/bind9:acidonpe
podman login quay.io
podman quay.io/acidonpe/bind9:acidonpe
```

### Test the DNS container image locally

In order to the new container image locally, it is possible to deploy the DNS and a client container. Please follow the next steps in order to test the final container image:

- Create a podman network in order to test the solution

```$bash
podman network create --subnet=172.20.0.0/16 acidonpe-net
```

- Deploy the bind9 image

```$bash
podman run -d --rm --name=dns-server --net=acidonpe-net --ip=172.20.0.2 bind9:acidonpe
podman exec -d dns-server /etc/init.d/bind9 start
```

- Deploy a client container and execute a resolve DNS entry test

```$bash
podman run -d --rm --name=host1 --net=acidonpe-net --ip=172.20.0.3 --dns=172.20.0.2 sequenceiq/alpine-dig /bin/sh -c "while :; do sleep 10; done"
podman exec -it host1 sh -c "/usr/bin/dig -t A host1.acidonpe.com @172.20.0.2"
```

## Setting Up

Once the container image is published in a public container registry, it is time to deploy the "external" DNS in Openshift. In order to integrate this new piece in Openshift, it is required to execute the following commands:

- Add SCC to the default service account in order to execute the pod with anyuid

```$bash
oc adm policy add-scc-to-user anyuid -z default
```

- Create the namespace and required resources

```$bash
oc new-project dns-test

oc apply -f openshift/dns-deployment.yaml
```

### Test the "external" DNS service in Openshift

Once the pods *acidonpe-dns* and *acidonpe-dns-test* are running, it is possible to test the service through the testing pod. Please follow the next steps in order to test this new DNS service:

- Test the DNS functionality (UDP and TCP)

```$bash
POD=$(oc get po -l=name=acidonpe-dns-test -o jsonpath='{.items[0].metadata.name}')

oc get po -l=name=acidonpe-dns -o jsonpath='{.items[0].status.podIP}'

oc rsh ${POD}
/usr/bin/dig -t A host1.acidonpe.com @**POD_IP** +tcp
/usr/bin/dig -t A host1.acidonpe.com @**POD_IP**
```

## Config CoreDNS

Finally, it is required to configure CoreDNS in order to forward all requests to the "external" DNS that was deployed in the previous steps. It is important to bear in

- Apply the forward configuration through the respective k8s object

```$bash
SVC_IP=$(oc get svc -l=app=acidonpe-dns -o jsonpath='{.items[0].spec.clusterIP}')

cat <<EOF | oc apply -f -
apiVersion: operator.openshift.io/v1
kind: DNS
metadata:
  name: default
spec:
  servers:
  - name: acidonpe 
    zones: 
      - acidonpe.com
    forwardPlugin:
      upstreams: 
        - ${SVC_IP}:5353
EOF
```

- View the ConfigMap in order to review the configuration

```$bash
oc get configmap/dns-default -n openshift-dns -o yaml
```

### Test the DNS domain zone forward in Openshift

Once the pods CoreDNS has been properly configured, it is possible to test the service through the testing pod. Please follow the next steps in order to test this new DNS forwarded functionality:

- Connect to the *acidonpe-dns-test* pod

```$bash
POD=$(oc get po -l=name=acidonpe-dns-test -o jsonpath='{.items[0].metadata.name}')

oc rsh ${POD}
```

- Test the DNS functionality (TCP)

```$bash
/usr/bin/dig -t A host1.acidonpe.com +tcp
...
;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 512
;; QUESTION SECTION:
;host1.acidonpe.com.            IN      A

;; ANSWER SECTION:
host1.acidonpe.com.     604800  IN      A       172.20.0.3

;; Query time: 2 msec
;; SERVER: 172.30.0.10#53(172.30.0.10)
;; WHEN: Wed May 11 16:03:12 UTC 2022
;; MSG SIZE  rcvd: 81
```

- Test the DNS functionality (UDP)

```$bash
/usr/bin/dig -t A host1.acidonpe.com 
...
;; ANSWER SECTION:
host1.acidonpe.com.     604800  IN      A       172.20.0.3

;; AUTHORITY SECTION:
acidonpe.com.           604800  IN      NS      ns1.acidonpe.com.

;; ADDITIONAL SECTION:
ns1.acidonpe.com.       604800  IN      A       172.20.0.2

;; Query time: 1 msec
;; SERVER: 172.30.0.10#53(172.30.0.10)
;; WHEN: Wed May 11 16:03:16 UTC 2022
;; MSG SIZE  rcvd: 155
```

## Author

Asier Cidon @RedHat
