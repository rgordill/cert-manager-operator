# Ambient Credentials for cert-manager

Cert-manager ACME dns-01 solvers for AWS Route53 and Google Cloud DNS can utilize ambient credentials available by default within the environment of the controller pod that is running on the cluster. The openshift-cert-manager-operator allows users to specify a cloud secret name for AWS and GCP clusters which would be used for the cert-manager ambient credentials. This is done by passing the name of the secret (which should mandatorily be present in the cert-manager namespace) containing the cloud credentials for authenticating with either AWS route53 or Google Cloud DNS.

Note: ClusterIssuer(s) have support for ambient credential mode available by default, for Issuer(s) to utilize ambient credentials the `--issuer-ambient-credentials` has to be passed as an arg to the cert-manager controller pod.

OpenShift clusters can utilize cluster cloud-credential operator to manage these secrets. For clusters with [credentials mode set as Manual (which is the case when using AWS STS or GCP Workload Identity based clusters)](https://docs.openshift.com/container-platform/latest/authentication/managing_cloud_provider_credentials/cco-mode-manual.html), then cluster administrators need to use ccoctl to generate the secret and manually apply the generated secret on the cluster. Otherwise, CredentialsRequest object once placed in the openshift-cloud-credential-operator namespace would automatically generate and place the k8s secret on the cluster.

## AWS

1. Create the following yaml file for credentials request object and `oc apply -f <yaml-file>` on the cluster. 
```yaml
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: cert-manager
  namespace: openshift-cloud-credential-operator
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
      - action:
          - route53:GetChange
        effect: Allow
        resource: arn:aws:route53:::change/*
      - action:
          - route53:ChangeResourceRecordSets
          - route53:ListResourceRecordSets
        effect: Allow
        resource: arn:aws:route53:::hostedzone/*
      - action:
          - route53:ListHostedZonesByName
        effect: Allow
        resource: "*"
  secretRef:
    name: aws-creds
    namespace: cert-manager
  serviceAccountNames:
    - cert-manager
```
2. Create a new directory `<cred-reqs-dir>` and place the `<yaml-file>` in that directory.
3. If using STS and or credentials mode as Manual on the cluster, use [`ccoctl`](https://github.com/openshift/cloud-credential-operator/blob/master/docs/ccoctl.md) to generate the secrets and apply it on the cluster.

If not using Manual credentials mode, skip steps 3, 4, 5 and directly proceed to 6.

```sh
ccoctl aws create-iam-roles --credentials-requests-dir <cred-reqs-dir> --identity-provider-arn <cluster-oidc-provider-arn>  --name <cluster-oidc-name>  --output-dir <output-dir> --region <cluster-aws-region>
```
The output of the previous ccoctl command would be similar to:

```log
2023/05/15 18:10:34 Role arn:aws:iam::XXXXXXXXXXXX:role/<oidc-prefix>-cert-manager-aws-creds created
2023/05/15 18:10:34 Saved credentials configuration to: <output-dir>/manifests/cert-manager-aws-creds-credentials.yaml
2023/05/15 18:10:35 Updated Role policy for Role <oidc-prefix>-cert-manager-aws-creds
```

From the output copy the `<aws-arn-id>` containing the arn role, eg. `arn:aws:iam::XXXXXXXXXXXX:role/<oidc-prefix>-cert-manager-aws-creds` which would be used in next step.

4. Annotate the cert-manager service account in the cert-manager namespace to use the correct AWS ARN role and other sts related annotations. This is required for [aws-pod-identity-webhook](https://github.com/openshift/aws-pod-identity-webhook) running on the cluster to correctly assign AWS roles to the pod(s) used by cert-manager.

```sh
oc -n cert-manager annotate serviceaccount cert-manager eks.amazonaws.com/role-arn="<aws-arn-id>"
oc -n cert-manager annotate serviceaccount cert-manager eks.amazonaws.com/audience="sts.amazonaws.com"
oc -n cert-manager annotate serviceaccount cert-manager eks.amazonaws.com/sts-regional-endpoints="true"
oc -n cert-manager annotate serviceaccount cert-manager eks.amazonaws.com/token-expiration="86400"
```

5. Apply the generated secrets on the cluster 
```sh
ls <output-dir>/manifests/*-credentials.yaml | xargs -I{} oc apply -f {}
```
6. Patch the subscription object on the cluster to inject the secret name in the operator deployment.
```sh
oc -n cert-manager-operator patch subscription cert-manager-operator --type='merge' -p '{"spec":{"config":{"env":[{"name":"CLOUD_CREDENTIALS_SECRET_NAME","value":"aws-creds"}]}}}'
```


## GCP

1. Create the following yaml file for credentials request object and `oc apply -f <yaml-file>` on the cluster. 
```yaml
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  labels:
    app: cert-manager
    app.kubernetes.io/component: controller
    app.kubernetes.io/instance: cert-manager
    app.kubernetes.io/name: cert-manager
  name: cert-manager
  namespace: openshift-cloud-credential-operator
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: GCPProviderSpec
    predefinedRoles:
    - roles/dns.admin
  secretRef:
    name: gcp-credentials
    namespace: cert-manager
  serviceAccountNames:
  - cert-manager
```
2. Create a new directory `<cred-reqs-dir>` and place the `<yaml-file>` in that directory.
3. If using STS and or credentials mode as Manual on the cluster, use [`ccoctl`](https://github.com/openshift/cloud-credential-operator/blob/master/docs/ccoctl.md) to generate the secrets and apply it on the cluster. 
```sh
ccoctl gcp create-service-accounts --credentials-requests-dir <cred-reqs-dir> --name <unique-resource-name> --output-dir <output-dir> --workload-identity-pool <cluster-gcp-identity-pool-name> --workload-identity-provider <cluster-gcp-identity-pool> --project <gcp-project-name>
```
If not using Manual credentials mode, skip steps 3, 4 and directly proceed to 5.

4. Apply the generated secrets on the cluster 
```
ls manifests/*-credentials.yaml | xargs -I{} oc apply -f {}
```
5. Patch the subscription object on the cluster to inject the secret name in the operator deployment.
```
oc -n cert-manager-operator patch subscription cert-manager-operator --type='merge' -p '{"spec":{"config":{"env":[{"name":"CLOUD_CREDENTIALS_SECRET_NAME","value":"gcp-credentials"}]}}}'
```
