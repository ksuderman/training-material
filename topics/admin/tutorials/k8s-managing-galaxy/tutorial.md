---
layout: tutorial_hands_on

title: "Managing Galaxy on Kubernetes"
level: "Intermediate"
questions:
- How do I change Galaxy configs?
- How can I upgrade to a new version?
- How do I rollback my changes?
- How do I scale Galaxy?
objectives:
- Have an understanding of how to modify Galaxy configuration
- Be able to upgrade and scale galaxy
time_estimation: "30m"
key_points:
- Modifying configuration is a matter of having some local config files
  that are mapped in their entirety into the Galaxy container.
- Scaling is a simple matter of changing the number of replicas.
- K8S enables zero downtime upgrades and sets the stage for continuous
  delivery
contributors:
  - nuwang
  - afgane
  - almahmoud
  - pcm32
  - jdavcs
tags:
  - kubernetes
subtopic: cloud
requirements:
  - type: "internal"
    topic_name: admin
    tutorials:
      - k8s-deploying-galaxy
priority: 1
---

# Managing Galaxy on Kubernetes

## Overview


A primary advantage of Galaxy on [Kubernetes](https://kubernetes.io/) is the ease with which common
administrative tasks can be performed reliably and without disruption of
service. In particular, because of containerization, Kubernetes provides a significant
advantage over managing individual virtual machines, where updates to system
libraries or components can cause unexpected breakage of dependent components.
With containerization, this becomes a simpler problem of swapping out a
container and replacing it with an updated version. It also reduces reliance
on the underlying operating system, allowing the OS to be upgraded and
have the latest security patches applied without having to worry about
how it will affect the applications running within. Kubernetes has built-in
functionality for draining a node of all containers and for transparently
moving those containers to a different node, allowing maintenance tasks to be
performed on the underlying node without disruption of service.

In this section, we will look at how to perform common management tasks on
a Galaxy deployment on Kubernetes, including:
- How to upgrade a deployment
- Change the configuration of a running Galaxy instance
- Map arbitrary files into Galaxy's config folder
- Rollback changes in the case of an error
- Scale the number of job and web handlers
- Delete a deployment

> <agenda-title></agenda-title>
>
> 1. TOC
> {:toc}
>
{: .agenda}

## Prerequisites
This tutorial builds on the material of the previous
[tutorial]({{ site.baseurl }}/topics/admin/tutorials/k8s-deploying-galaxy/tutorial.html)
and we recommend following it first to set up the required environment.
You must have some familiarity with Helm commands, know how to change values
in a Helm Chart and how to use the `kubectl` command.

## Assumptions
This tutorial assumes:

1. You have added the Galaxy Helm chart repository to your Helm installation
   by running `helm repo add galaxy https://gxy.io/k8s/charts`
2. Galaxy was installed using `galaxy` as the release name
3. Galaxy was installed in the `galaxy` namespace

Your `helm install` command should have been similar to: `helm install galaxy --namespace galaxy galaxy/galaxy --create-namespace --values custom-values.yaml`

# Changing the configuration of a Galaxy instance
We will start off by looking at how to change the configuration of a Galaxy
instance. We will first reduce the number of tools that are loaded for faster
startup, and then change some common settings in `galaxy.yml`.

## Changing tool configuration
We will change the Galaxy configuration to limit the initial list of tools
that Galaxy will use by pointing to our custom `tool_conf.xml`. This will make
your chart start up much faster for the remainder of this tutorial, as the
default configuration loads the full list of tools used by
[https://usegalaxy.org/](https://usegalaxy.org/).

> <hands-on-title>Creating a custom tool set</hands-on-title>
>
> 1. First, let's create a simpler list of tools by saving the following tool
>    config as a file called `custom_tool_conf.xml` in your local directory.
>
>    {% raw %}
>    ```xml
>    <?xml version='1.0' encoding='utf-8'?>
>    <toolbox monitor="true">
>      <section id="get_data" name="Get Data">
>        <tool file="data_source/upload.xml" />
>      </section>
>      <section id="send" name="Send Data">
>        <tool file="data_export/export_remote.xml" />
>      </section>
>      <section id="collection_operations" name="Collection Operations">
>        <tool file="${model_tools_path}/unzip_collection.xml" />
>        <tool file="${model_tools_path}/zip_collection.xml" />
>      </section>
>      <section id="expression_tools" name="Expression Tools">
>        <tool file="expression_tools/parse_values_from_file.xml"/>
>        <tool file="expression_tools/pick_value.xml"/>
>      </section>
>    </toolbox>
>    ```
>    {% endraw %}
>
> 2. Next, let's create a new values file, `custom_tool_conf.yml`, that overrides the `tool_config_file`
>    entry in the `galaxy.yml` so it only loads our `custom_tool_conf.xml`.
> 
>    {% raw %}
>    ```yaml
>    configs:
>      galaxy.yml:
>        galaxy:
>          tool_config_file: /galaxy/server/config/custom_tool_conf.xml
>    ```
>    {% endraw %}
>
>    We could override the `tool_config_file` entry on the command line, but using
>    a values file is more maintainable and allows for more modular configurations.
>
> 4. Now, let's upgrade the chart to use our `custom_tool_conf.xml` by running the `helm upgrade` command.
>
>    {% raw %}
>    ```bash
>    helm upgrade galaxy -n galaxy galaxy/galaxy --reuse-values --set-file "configs.custom_tool_conf\.xml"=custom_tool_conf.xml --values custom_tool_conf.yml
>    ```
>    {% endraw %}
>
>    Note the `--reuse-values` flag, which instructs Helm to reuse any
>    previously set values, and apply the new ones on top.  The `--set-file`
>    option will set the value of the `configs.custom_tool_conf.xml`
>    key in your values file to the contents of the specified file, as a text
>    string. Each file under the `configs` key in `values.yaml` is automatically
>    mapped into Galaxy's `config` directory.
>
> 5. Notice that while the chart is upgrading, the existing version continues
>    to function. The changeover will occur when the new containera are online
>    and signals readiness to Kubernetes by responding to web requests on
>    the relevant port. Log into the Kubernetes dashboard and watch the logs
>    as the new pods come online.
>
> 6. List the installed helm charts and note that the revision of the galaxy chart
>    has changed. These revisions are useful because it allows us to rollback
>    our changes if they are incorrect. This will be covered in a later section.
>
>    {% raw %}
>    ```bash
>    helm list
>    NAME  	REVISION	UPDATED                 	STATUS  	CHART                 	APP VERSION	NAMESPACE
>    galaxy	2       	Wed Jun 26 14:51:17 2019	DEPLOYED	galaxy-3.0.0          	v19.05     	default
>    ```
>    {% endraw %}
>
> 6. Let's now exec into the running container and check that the files were
>    mapped in. First, let's get a list of running pods.
>
>    {% raw %}
>    ```bash
>    kubectl get pods -n galaxy
>    NAME                          READY   STATUS    RESTARTS   AGE
>    galaxy-galaxy-postgres-0      1/1     Running   0          2d6h
>    galaxy-job-69864b6797-zs5mn   1/1     Running   0          2d6h
>    galaxy-web-7568c58b94-jzkvm   1/1     Running   0          2d6h
>    ```
>    {% endraw %}
>
>    Exec into the web pod by running:
>    {% raw %}
>    ```bash
>    kubectl exec -it galaxy-web-7568c58b94-jzkvm /bin/bash
>    ```
>    {% endraw %}
>
>    Now run `ls /galaxy/server/config/` and note that the `galaxy.yml` contains
>    the content that you've provided and that `custom_tool_conf.xml` has also been
>    mapped into the config folder. In this same way, any of Galaxy's config
>    files can be overridden by simply mapping in the relevant file into the
>    config folder.
{: .hands_on}

## Setting the admin user and changing the brand
Next, we will set the admin user and change the brand in `galaxy.yml`. We will
rollback our change to understand how Helm manages configuration.

> <hands-on-title>Setting admin user and changing the brand</hands-on-title>
>
> 1. Modify the following entries in your `galaxy.yml`. Make sure to add these
>    keys under the `galaxy:` section of the file.
>
>    {% raw %}
>    ```
>    brand: "Hello World"
>    admin_users: "admin@mydomain.com"
>    ```
>    {% endraw %}
>
> 2. Now, let’s upgrade the chart to apply the new configuration.
>
>    {% raw %}
>    ```bash
>    helm upgrade --reuse-values --set-file "configs.galaxy\.yml"=galaxy.yml galaxy galaxy/galaxy
>    ```
>    {% endraw %}
>
> 3. Inspect the currently set Helm values by:
>
>    {% raw %}
>    ```bash
>    helm get values galaxy
>    ```
>    {% endraw %}
>
> 4. List the installed Helm charts again and note that the revision of the chart has changed as expected.
>
>    {% raw %}
>    ```bash
>    helm list
>    NAME  	REVISION	UPDATED                 	STATUS  	CHART                 	APP VERSION	NAMESPACE
>    cvmfs 	1       	Wed Jun 26 14:47:46 2019	DEPLOYED	galaxy-cvmfs-csi-1.0.1	1.0        	cvmfs
>    galaxy	3       	Wed Jun 26 14:51:17 2019	DEPLOYED	galaxy-3.0.0          	v19.05     	default
>    ```
>    {% endraw %}
>
> 5. Let’s now roll back to the previous revision.
>
>    {% raw %}
>    ```bash
>    helm rollback galaxy 2
>    ```
>    {% endraw %}
>
>    Use `helm get values` again to observe that the values have reverted to
>    the previous revision. After a short while, once the new container is up
>    and running, Kubernetes will automatically switch over to it and you can
>    see that the previous configuration has been restored.
>
{: .hands_on}

# Scaling Galaxy
In Galaxy deployment on Kubernetes, there are two containers by default, one
web handler and one job handler. We will now look at how these can be scaled.

> <hands-on-title>Setting admin user and changing the brand</hands-on-title>
>
> 1. View the `values-cvmfs.yaml` file in the Galaxy Helm chart and note down the
>    number of web and job handlers.
>
>    {% raw %}
>    ```yaml
>    webHandlers:
>        replicaCount: 1
>    jobHandlers:
>        replicaCount: 1
>    ```
>    {% endraw %}
>
> 2. Let’s increase the number of web handlers by simply setting new values for the number of replicas.
>
>    {% raw %}
>    ```bash
>    helm upgrade --reuse-values --set webHandlers.replicaCount=2 galaxy galaxy/galaxy
>    ```
>    {% endraw %}
>
> 3. Check whether the new replicas have been created.
>
>    {% raw %}
>    ```bash
>    kubectl get pods
>    NAME                          READY   STATUS    RESTARTS   AGE
>    galaxy-galaxy-postgres-0      1/1     Running   0          2d9h
>    galaxy-job-5cc75c6588-8dsbg   1/1     Running   0          7m13s
>    galaxy-web-7c9576cf89-49nlm   1/1     Running   0          7m13s
>    galaxy-web-7c9576cf89-r6rcj   0/1     Running   0          9s
>    ```
>    {% endraw %}
>
> 4. Follow the pod logs and check whether the new handler is receiving web requests
>    as expected.
>
>    {% raw %}
>    ```bash
>    kubectl logs -f galaxy-web-7c9576cf89-r6rcj
>    ```
>    {% endraw %}
>
>    You will notice that Kubernetes automatically load balances requests between the
>    available web handler replicas in a round-robin fashion.
>
{: .hands_on}

# Testing Kubernetes resilience
To observe how Kubernetes handles failures, let’s exec into a running container and
manually kill a process to simulate a possible process failure. Kubernetes
continuously monitors running containers, and attempts to bring the environment
back to the “desired” state. The moment it notices a failure, it will respawn
a new pod to replace the failed one. Typically, a Kubernetes container will also
have a [liveness probe][k8sliveness] defined. A liveness probe can be an http
request to a port, or even a manually executed shell script, which will test
whether the relevant container is healthy, and if not, Kubernetes will immediately
provision a new replacement.

> <hands-on-title>Handling failures</hands-on-title>
>
> 1. First list the available pods.
>
>    {% raw %}
>    ```bash
>    kubectl get pods
>    NAME                          READY   STATUS    RESTARTS   AGE
>    galaxy-galaxy-postgres-0      1/1     Running   0          2d9h
>    galaxy-job-5cc75c6588-8dsbg   1/1     Running   0          14m
>    galaxy-web-7c9576cf89-49nlm   1/1     Running   0          14m
>    galaxy-web-7c9576cf89-r6rcj   0/1     Running   1          7m36s
>    ```
>    {% endraw %}
>
>    Then exec into one:
>    {% raw %}
>    ```bash
>    kubectl exec -it galaxy-web-7c9576cf89-r6rcj /bin/bash
>    ```
>    {% endraw %}
>
> 2. Now kill the main container process.
>
>    {% raw %}
>    ```bash
>    kill 1
>    ```
>    {% endraw %}
>
> 3. If we run `kubectl get pods`, we can notice how Kubernetes immediately
>    starts a new pod to replace the failed one, bringing the environment back to
>    the desired state. Take a look at the liveness probe defined for the galaxy
>    web container in the helm chart source code
>    (`templates/deployment-web.yaml`).
>
{: .hands_on}

# Deleting Galaxy
Finally, let’s take a look at how we can uninstall Galaxy and remove all
related containers.

> <hands-on-title>Deleting Galaxy</hands-on-title>
>
> 1. To permanently delete the Galaxy release, run:
>
>    {% raw %}
>    ```bash
>    helm delete --purge galaxy
>    ```
>    {% endraw %}
>
>    The purge flag instructs helm to permanently remove galaxy from its history.
>
> 2. Use `kubectl get pods` to verify that the pods have been deleted.
>
{: .hands_on}

# Next Steps
This tutorial provided an overview of some common Galaxy administration tasks.
Advanced customizations would include running custom shell scripts on Galaxy
startup to perform additional tasks, running additional containers on
startup, administering and managing storage, building custom Galaxy containers
with desired modifications etc. For more info on some of these
topics, take a look at the [Galaxy Helm chart] repository as well as
[other tutorials](../..) tagged with _kubernetes_. Also, feel free to reach out
on Gitter: [https://gitter.im/galaxyproject/FederatedGalaxy][fedG].


[fedG]: https://gitter.im/galaxyproject/FederatedGalaxy
[k8sliveness]: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/
[Galaxy Helm chart]: https://github.com/galaxyproject/galaxy-helm
